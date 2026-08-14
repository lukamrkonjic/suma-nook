"""Map an existing glb's colours onto Suma's palette, keeping its hierarchy.

Run inside Blender:

    blender --background --factory-startup --python tools/palette_map_asset.py -- \
        --source in.glb --output out.glb [--profile generic]

prepare_model_import.py does this as one step of a much larger job -- it also
re-roots, renames, grounds, and can split a tree's canopy -- so running it over
an asset whose node structure is load-bearing would destroy that structure. The
wardrobe's doors are exactly such nodes: the game finds them by name and rotates
them.

So this reuses only the colour half, apply_flat_style, and leaves every object,
name and transform alone. That is what lets a hand-assembled asset still look
like it belongs to the game rather than keeping whatever colours its source
textures happened to carry.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))

import glb_export  # noqa: E402
import prepare_model_import as P  # noqa: E402


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--profile",
        default="generic",
        choices=("tree", "shrub", "wood_prop", "stone_prop", "generic"),
    )
    # Source textures bake their lighting in, so the SAME paint arrives as a lit
    # sample and a shaded one. At the import defaults those two survive as
    # separate clusters and get separate palette slots -- which is how a wardrobe
    # whose body is one colour ended up with a stripe of another down its side.
    # These widen the "same paint" test so a paint's lit and shaded faces merge,
    # while a genuinely different, darker trim stays its own colour.
    parser.add_argument("--value-window", type=float, default=0.22)
    parser.add_argument("--merge-distance", type=float, default=0.20)
    # How many material slots the asset ends up with. Small leftover clusters are
    # baked lighting rather than paint, and given their own palette entry they
    # read as patches on an otherwise even surface -- so fold down to the number
    # of tones the source actually has.
    parser.add_argument("--max-slots", type=int, default=0)
    # Nearest-match picks the palette entry closest in hue and saturation, which
    # is the right rule but cannot invent a colour the palette does not hold --
    # the wardrobe's mid orange has no saturated equivalent, so it resolves to a
    # paler one. Naming the slots outright records that decision in the recipe
    # instead of leaving it to be rediscovered. Given in cluster order, largest
    # first; omitted clusters keep their automatic match.
    parser.add_argument("--slot", action="append", default=[])
    return parser.parse_args(argv)


# Weights for _paint_distance. Hue moves very little between two paints of the
# same family -- the wardrobe's brown and its orange are 30 and 34 degrees apart
# -- so measured in raw 0..1 hue units the signal is tiny next to a saturation
# difference, and has to be scaled up to be heard at all.
PAINT_HUE_WEIGHT = 20.0
PAINT_SATURATION_WEIGHT = 1.0


def _paint_distance(
    left: tuple[float, float, float], right: tuple[float, float, float]
) -> float:
    """Distance between two sampled colours, ignoring how brightly they are lit.

    Source textures bake their shading in, so within ONE paint the value swings
    widely -- the wardrobe's orange samples #B8843E on the lit door and #6F3102
    on the shaded side -- while hue and saturation barely move. Between the two
    paints it is the reverse: the brown and the orange overlap in value and
    separate cleanly on hue (28-30 vs 33-34 degrees) and saturation.

    So value is the one channel that must NOT decide the split. Clustering on it
    grouped the wardrobe's shaded side with its top, which is a different paint,
    and left the model reading as three tones where the source has two.
    """
    left_hue, _, left_saturation = left
    right_hue, _, right_saturation = right
    gap = abs(left_hue - right_hue)
    hue_delta = min(gap, 1.0 - gap)
    return (
        hue_delta * PAINT_HUE_WEIGHT
        + abs(left_saturation - right_saturation) * PAINT_SATURATION_WEIGHT
    )


def _distance_for(faces: list):
    """Picks the metric that can actually tell this asset's paints apart.

    Hue is meaningless on a near-grey, so an asset with unsaturated regions --
    stone, metal, bone -- still has to be split on value. Only when every face
    carries real colour is hue trustworthy enough to lead.
    """
    chromatic = all(
        P._hls(face["srgb"])[2] > P.CLUSTER_GREY_SATURATION for face in faces
    )
    if not chromatic:
        return lambda left, right: P._perceptual_distance(left, right)
    return lambda left, right: _paint_distance(P._hls(left), P._hls(right))


def cluster_into(faces: list, count: int) -> list[dict]:
    """Splits the faces into exactly `count` groups by colour, k-means style.

    The greedy walk in prepare_model_import grows a cluster from whichever face
    it happens to meet first, so a face is judged against a moving average
    rather than against the finished groups. On the wardrobe that put a scatter
    of door-front triangles in the group belonging to the top and base, and the
    doors came out with a chevron of the wrong colour across a surface that is
    one flat tone in the source.

    Reassigning every face to its nearest final centre removes that order
    dependence: a face lands in a group because it matches it, not because of
    when it was visited. Seeded from the extremes so the run is deterministic.
    """
    distance = _distance_for(faces)
    ordered = sorted(faces, key=lambda face: P._hls(face["srgb"])[0])
    centres = [ordered[0]["srgb"], ordered[-1]["srgb"]]
    while len(centres) < count:
        # Farthest-first: each new centre is the face least like anything held
        # so far, which is where an extra group is actually worth spending.
        centres.append(
            max(
                faces,
                key=lambda face: min(
                    distance(face["srgb"], centre) for centre in centres
                ),
            )["srgb"]
        )

    groups: list[list] = []
    for _ in range(24):
        groups = [[] for _ in centres]
        for face in faces:
            nearest = min(
                range(len(centres)),
                key=lambda index: distance(face["srgb"], centres[index]),
            )
            groups[nearest].append(face)
        moved = False
        for index, group in enumerate(groups):
            if not group:
                continue
            mean = tuple(
                sum(face["srgb"][channel] for face in group) / len(group)
                for channel in range(3)
            )
            if distance(mean, centres[index]) > 1e-4:
                moved = True
            centres[index] = mean
        if not moved:
            break

    clusters = [
        {"faces": group, "srgb": centre, "hls": P._hls(centre)}
        for group, centre in zip(groups, centres)
        if group
    ]
    clusters.sort(key=lambda cluster: -len(cluster["faces"]))
    return clusters


def map_jointly(
    meshes: list, profile: str, slots: int = 0, overrides: list | None = None
) -> dict:
    """Clusters every mesh of the asset together, then assigns palette slots.

    apply_flat_style clusters each mesh object independently, which is right for
    a single-mesh import and wrong for an asset assembled from several: the
    wardrobe's closed state is one mesh and resolved to two tones, while its open
    state is three meshes and resolved to seven -- including a gold the closed
    state never had. Swapping between them would have flickered.

    Clustering the whole asset at once means both states see the same colours and
    land on the same slots.
    """
    faces: list[dict] = []
    for mesh_object in meshes:
        mesh = mesh_object.data
        samples = P.sampled_materials(mesh_object)
        for polygon in mesh.polygons:
            colour = P.average_component_color(mesh, [polygon.index], samples)
            srgb = tuple(
                P._srgb_channel(max(0.0, float(channel))) for channel in colour
            )
            faces.append(
                {"object": mesh_object, "index": polygon.index, "srgb": srgb}
            )

    if slots > 0:
        clusters = cluster_into(faces, slots)
    else:
        clusters = []
        for face in faces:
            hls = P._hls(face["srgb"])
            for cluster in clusters:
                if P._same_paint(hls, cluster["hls"]):
                    cluster["faces"].append(face)
                    weight = 1.0 / len(cluster["faces"])
                    cluster["srgb"] = tuple(
                        current + (new - current) * weight
                        for current, new in zip(cluster["srgb"], face["srgb"])
                    )
                    cluster["hls"] = P._hls(cluster["srgb"])
                    break
            else:
                clusters.append(
                    {"faces": [face], "srgb": face["srgb"], "hls": hls}
                )
        clusters.sort(key=lambda cluster: -len(cluster["faces"]))
        clusters = P._merge_near_clusters(clusters)
        clusters = P._merge_small_clusters(clusters, len(faces))

    candidates = (
        P.band_palette("green")
        if profile in {"tree", "shrub"}
        else P.usable_palette()
    )
    chosen = P.assign_distinct_slots(clusters, candidates)
    for index, name in enumerate(overrides or []):
        if index >= len(chosen):
            break
        if name not in candidates:
            raise RuntimeError("%s is not a usable palette entry" % name)
        chosen[index] = name

    per_object: dict = {}
    usage: dict = {}
    for cluster, slot in zip(clusters, chosen):
        for face in cluster["faces"]:
            per_object.setdefault(face["object"], {})[face["index"]] = slot
        usage[slot] = usage.get(slot, 0) + len(cluster["faces"])
        red, green, blue = cluster["srgb"]
        near = sorted(
            candidates,
            key=lambda name: P._perceptual_distance(
                cluster["srgb"], P._palette_srgb(name)
            ),
        )[:4]
        print(
            "  cluster %4d faces sRGB=(%.2f,%.2f,%.2f) #%02X%02X%02X -> %s"
            % (
                len(cluster["faces"]),
                red,
                green,
                blue,
                int(red * 255),
                int(green * 255),
                int(blue * 255),
                slot,
            )
        )
        print("    nearest: %s" % ", ".join(near))

    for mesh_object, assignment in per_object.items():
        mesh = mesh_object.data
        names = sorted(set(assignment.values()))
        mesh.materials.clear()
        for name in names:
            mesh.materials.append(P._flat_material(name))
        slot_index = {name: index for index, name in enumerate(names)}
        for face_index, name in assignment.items():
            mesh.polygons[face_index].material_index = slot_index[name]
        mesh.update()
    return usage


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh geometry to recolour")
    # Shading is left exactly as imported. This step recolours; how the surface
    # is shaded is the source's decision and then the player's, through the
    # asset's own smoothing setting.
    write_normals = glb_export.scene_authors_normals()
    P.CLUSTER_VALUE_WINDOW = arguments.value_window
    P._cluster_merge_distance = arguments.merge_distance
    if arguments.max_slots > 0:
        P.MAX_CLUSTERS = arguments.max_slots
    usage = map_jointly(
        meshes, arguments.profile, arguments.max_slots, arguments.slot
    )
    print(
        "PALETTE %s"
        % " ".join(
            "%s=%d" % (name, count) for name, count in sorted(usage.items())
        )
    )
    bpy.ops.object.select_all(action="SELECT")
    glb_export.export_selected(arguments.output, write_normals=write_normals)
    print(f"PALETTE_OUT={arguments.output}")


if __name__ == "__main__":
    main()

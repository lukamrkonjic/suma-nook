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
    return parser.parse_args(argv)


def map_jointly(meshes: list, profile: str) -> dict:
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

    clusters: list[dict] = []
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

    per_object: dict = {}
    usage: dict = {}
    for cluster, slot in zip(clusters, chosen):
        for face in cluster["faces"]:
            per_object.setdefault(face["object"], {})[face["index"]] = slot
        usage[slot] = usage.get(slot, 0) + len(cluster["faces"])
        red, green, blue = cluster["srgb"]
        print(
            "  cluster %4d faces sRGB=(%.2f,%.2f,%.2f) -> %s"
            % (len(cluster["faces"]), red, green, blue, slot)
        )

    for mesh_object, assignment in per_object.items():
        mesh = mesh_object.data
        names = sorted(set(assignment.values()))
        mesh.materials.clear()
        for name in names:
            mesh.materials.append(P._flat_material(name))
        slots = {name: index for index, name in enumerate(names)}
        for face_index, name in assignment.items():
            mesh.polygons[face_index].material_index = slots[name]
        mesh.update()
    return usage


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh geometry to recolour")
    usage = map_jointly(meshes, arguments.profile)
    print(
        "PALETTE %s"
        % " ".join(
            "%s=%d" % (name, count) for name, count in sorted(usage.items())
        )
    )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(arguments.output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
    )
    print(f"PALETTE_OUT={arguments.output}")


if __name__ == "__main__":
    main()

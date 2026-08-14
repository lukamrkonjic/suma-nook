"""Shift a glb's TEXTURE onto Suma's palette, keeping the texture itself.

Run inside Blender:

    blender --background --factory-startup --python tools/palette_shift_texture.py -- \
        --source in.glb --output out.glb

The flat per-face repaint loses everything the texture carries: per-stone tonal
variation, crevice shading, and -- decisively -- region boundaries that run
THROUGH faces. On the wishing well the moss is painted onto parts of faces, so
averaging each face to one colour painted whole faces green wherever the average
tipped, and the moss spread far outside its painted patches.

So instead of repainting geometry, this edits the texture in place:

1. Every pixel is classified by the same band rules the importer uses -- a dull
   yellow-green is moss, everything else here is stone.
2. Each class gets ONE palette target: the entry nearest the class's mean colour
   (greens choose among greens, the family invariant).
3. Each pixel becomes `target * pixel / class_mean`, channel-wise. That is a
   palette shift, not a repaint: the pixel's deviation from its class mean --
   all the baked shading and per-stone detail -- survives exactly, while the
   class as a whole lands on the game's colour.

The mesh is untouched apart from grounding and shading: flat, with normals
exported, because Godot generates soft averaged normals for a file without them
and the model arrives melted (measured on the wardrobe).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bmesh
import bpy
import numpy

sys.path.insert(0, str(Path(__file__).resolve().parent))

import glb_export  # noqa: E402
import prepare_model_import as P  # noqa: E402


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def classify_green(rgb: numpy.ndarray) -> numpy.ndarray:
    """Boolean mask of pixels whose paint is a green, by the importer's rules."""
    maximum = rgb.max(axis=-1)
    minimum = rgb.min(axis=-1)
    delta = maximum - minimum
    lightness = (maximum + minimum) * 0.5
    saturation = numpy.zeros_like(maximum)
    chromatic = delta > 1e-6
    denominator = 1.0 - numpy.abs(2.0 * lightness - 1.0)
    saturation[chromatic] = delta[chromatic] / numpy.maximum(
        denominator[chromatic], 1e-6
    )

    hue = numpy.zeros_like(maximum)
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    r_max = chromatic & (maximum == red)
    g_max = chromatic & (maximum == green) & ~r_max
    b_max = chromatic & ~r_max & ~g_max
    hue[r_max] = numpy.mod((green[r_max] - blue[r_max]) / delta[r_max], 6.0)
    hue[g_max] = (blue[g_max] - red[g_max]) / delta[g_max] + 2.0
    hue[b_max] = (red[b_max] - green[b_max]) / delta[b_max] + 4.0
    degrees = hue * 60.0

    saturated = saturation >= P.BAND_NEUTRAL_SATURATION
    in_green = (degrees >= P.GREEN_BAND[0]) & (degrees < P.GREEN_BAND[1])
    in_olive = (
        (degrees >= P.OLIVE_BAND[0])
        & (degrees < P.OLIVE_BAND[1])
        & (saturation < P.OLIVE_GOLD_SATURATION)
    )
    # The well's texture edges its moss patches in dark TEAL (hue 160-210),
    # just past the green band's end -- classified warm, those pixels kept
    # their blue cast through the stone transfer and rendered as cyan
    # outlines around every patch. Painted moss edging is moss.
    in_teal = (degrees >= 160.0) & (degrees < 210.0)
    return saturated & (in_green | in_olive | in_teal)


def nearest_entry(mean: tuple[float, float, float], greens_only: bool) -> str:
    candidates = P.usable_palette()
    if greens_only:
        greens = tuple(
            name
            for name in candidates
            if P._hue_band(P._palette_srgb(name)) == "green"
        )
        if greens:
            candidates = greens
    return min(
        candidates,
        key=lambda name: P._perceptual_distance(mean, P._palette_srgb(name)),
    )


def _to_srgb(linear: numpy.ndarray) -> numpy.ndarray:
    """Blender hands image.pixels over in linear space; all the palette maths
    -- band rules, palette entries, the class means -- live in sRGB."""
    return numpy.where(
        linear <= 0.0031308,
        linear * 12.92,
        1.055 * numpy.power(numpy.maximum(linear, 1e-7), 1.0 / 2.4) - 0.055,
    )


def _to_linear(srgb: numpy.ndarray) -> numpy.ndarray:
    return numpy.where(
        srgb <= 0.04045,
        srgb / 12.92,
        numpy.power((srgb + 0.055) / 1.055, 2.4),
    )


def _coherent_mask(
    flat: numpy.ndarray, width: int, height: int
) -> numpy.ndarray:
    """Majority-smooths the pixel classification over a small neighbourhood.

    Per-pixel banding leaves speckles at every paint boundary -- pixels a hair
    under a threshold classify as stone inside a moss patch and vice versa,
    and each speck becomes a wrong-coloured dot after the shift. Similar
    neighbouring colours belong to the same paint, so each pixel follows the
    majority of a 9x9 box around it: an integral-image box blur re-thresholded
    at one half.
    """
    mask = flat.reshape(height, width).astype(numpy.float32)
    radius = 4
    size = 2 * radius + 1
    padded = numpy.pad(mask, radius, mode="edge")
    integral = numpy.zeros(
        (padded.shape[0] + 1, padded.shape[1] + 1), dtype=numpy.float64
    )
    integral[1:, 1:] = padded.cumsum(axis=0).cumsum(axis=1)
    summed = (
        integral[size : size + height, size : size + width]
        - integral[0:height, size : size + width]
        - integral[size : size + height, 0:width]
        + integral[0:height, 0:width]
    )
    return (summed / float(size * size) >= 0.5).reshape(-1)


def _dilate(mask: numpy.ndarray, width: int, height: int, steps: int) -> numpy.ndarray:
    """Grows a boolean mask by `steps` pixels (4-neighbourhood)."""
    grid = mask.reshape(height, width).copy()
    for _ in range(steps):
        grown = grid.copy()
        for shift_y, shift_x in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grown |= numpy.roll(grid, (shift_y, shift_x), axis=(0, 1))
        grid = grown
    return grid.reshape(-1)


def _pad_edges(
    rgb: numpy.ndarray,
    mask: numpy.ndarray,
    width: int,
    height: int,
    steps: int = 4,
) -> numpy.ndarray:
    """Bleeds each class's colour a few pixels past its boundary.

    MASK-mode cutouts sample RGB bilinearly across the alpha edge, so whatever
    colour sits just OUTSIDE the mask tints the visible rim. Dilating the
    inside colours outward puts class-coloured pixels there instead.
    """
    grid = rgb.reshape(height, width, 3).copy()
    inside = mask.reshape(height, width).copy()
    for _ in range(steps):
        outside = ~inside
        grown = inside.copy()
        for shift_y, shift_x in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rolled = numpy.roll(inside, (shift_y, shift_x), axis=(0, 1))
            fresh = outside & rolled & ~grown
            if fresh.any():
                source = numpy.roll(grid, (shift_y, shift_x), axis=(0, 1))
                grid[fresh] = source[fresh]
                grown |= fresh
        inside = grown
    return grid.reshape(-1, 3)


def shift_image(image: bpy.types.Image) -> tuple:
    pixels = numpy.array(image.pixels[:], dtype=numpy.float32)
    pixels = pixels.reshape(-1, image.channels)
    rgb = _to_srgb(pixels[:, :3])

    green = classify_green(rgb)
    green = _coherent_mask(green, image.size[0], image.size[1])
    print(
        "  %s: %dx%d, %.1f%% green"
        % (
            image.name,
            image.size[0],
            image.size[1],
            100.0 * float(green.mean()),
        )
    )
    targets = {}
    for mask, greens_only, class_name in (
        (green, True, "well_moss"),
        (~green, False, "well_stone"),
    ):
        if not mask.any():
            continue
        mean = rgb[mask].mean(axis=0)
        entry = nearest_entry(tuple(float(c) for c in mean), greens_only)
        target = numpy.array(P._palette_srgb(entry), dtype=numpy.float32)
        targets[class_name] = tuple(float(c) for c in target)
        print(
            "    %s #%02X%02X%02X -> %s"
            % ("green" if greens_only else "base ", *(int(c * 255) for c in mean), entry)
        )
        if greens_only:
            # Luminance-only transfer for moss: every pixel becomes exactly
            # the target green scaled by its brightness. Channel-wise transfer
            # preserves hue deviations, which is right for stone's warm
            # variation and wrong here -- it let the teal patch edging stay
            # teal instead of reading as dark moss.
            luminance = rgb[mask] @ numpy.array(
                [0.2126, 0.7152, 0.0722], dtype=numpy.float32
            )
            mean_luminance = max(float(luminance.mean()), 1e-4)
            rgb[mask] = numpy.clip(
                target[None, :] * (luminance / mean_luminance)[:, None],
                0.0,
                1.0,
            )
        else:
            rgb[mask] = numpy.clip(
                target[None, :]
                * rgb[mask]
                / numpy.maximum(mean[None, :], 1e-4),
                0.0,
                1.0,
            )

    pixels[:, :3] = _to_linear(rgb)
    image.pixels = pixels.reshape(-1).tolist()
    image.pack()
    return green, targets


def _uv_coverage(mesh, uv_data, width: int, height: int) -> numpy.ndarray:
    """Boolean (height, width) mask of texels under any UV triangle."""
    coverage = numpy.zeros((height, width), dtype=bool)
    for triangle in mesh.loop_triangles:
        points = numpy.array(
            [
                [uv_data[loop].uv.x * width, uv_data[loop].uv.y * height]
                for loop in triangle.loops
            ],
            dtype=numpy.float64,
        )
        x0 = max(int(numpy.floor(points[:, 0].min())) - 1, 0)
        x1 = min(int(numpy.ceil(points[:, 0].max())) + 1, width - 1)
        y0 = max(int(numpy.floor(points[:, 1].min())) - 1, 0)
        y1 = min(int(numpy.ceil(points[:, 1].max())) + 1, height - 1)
        if x1 < x0 or y1 < y0:
            continue
        grid_y, grid_x = numpy.mgrid[y0 : y1 + 1, x0 : x1 + 1]
        centres = numpy.stack(
            (grid_x + 0.5, grid_y + 0.5), axis=-1
        ).astype(numpy.float64)
        a, b, c = points[0], points[1], points[2]
        v0, v1 = b - a, c - a
        v2 = centres - a
        denominator = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(denominator) < 1e-9:
            continue
        u = (v2[..., 0] * v1[1] - v1[0] * v2[..., 1]) / denominator
        v = (v0[0] * v2[..., 1] - v2[..., 0] * v0[1]) / denominator
        inside = (u >= -0.02) & (v >= -0.02) & (u + v <= 1.02)
        coverage[y0 : y1 + 1, x0 : x1 + 1] |= inside
    return coverage


def split_material_slots(
    class_masks: dict, class_targets: dict
) -> None:
    """Two editable slots covering EVERY pixel of their class, via a decal shell.

    A single material means Asset Studio tints moss and stone together. But
    assigning whole faces to a moss material cannot work either, in two ways
    that were both shipped and both wrong: mixed faces on the moss slot smear
    pale green (their stone pixels clip against the dark green colour factor),
    and mixed faces on the stone slot strand their moss outside the moss slot
    -- the user painted the moss red and only some patches turned.

    So the split is a shell, not a partition:

    - The BASE mesh keeps every face on `well_stone`, whose texture holds the
      complete shifted image. Its moss pixels render exactly, and are then
      hidden beneath the overlay.
    - The OVERLAY duplicates every face that samples any moss, pushed a hair
      outward along its normals, on `well_moss`: same texture with ALPHA set to
      the per-pixel moss mask and alpha-scissor edges. Only moss pixels are
      visible on it, with the texture's own painted boundary.

    Recolouring `well_moss` therefore moves ALL the moss and nothing else, and
    `well_stone` moves the stone (its covered moss pixels shift too, invisibly).

    Each material multiplies its texture by a colour factor (the studio's
    editable colour) through a multiply-mix node -- the only pattern the glTF
    exporter turns into baseColorFactor; a connected Base Color socket ignores
    default_value. Textures are normalized by the factor so factor x texture
    reproduces the shifted image exactly at default.

    Deliberately NOT named after palette entries: MaterialLibrary rebinds any
    material carrying a palette name to the flat palette material, which would
    throw the texture away.
    """
    for mesh_object in [
        o for o in bpy.context.scene.objects if o.type == "MESH"
    ]:
        mesh = mesh_object.data
        if not mesh.materials or mesh.uv_layers.active is None:
            continue
        base_material = mesh.materials[0]
        albedo = P.base_color_image(base_material)
        if albedo is None or albedo.name not in class_masks:
            continue
        flat_mask = class_masks[albedo.name]
        width, height = albedo.size[0], albedo.size[1]
        source_pixels = numpy.array(
            albedo.pixels[:], dtype=numpy.float32
        ).reshape(height, width, albedo.channels)

        # The atlas GUTTER -- unused space between UV islands -- is filled
        # with an arbitrary colour that no material slot can ever own, and
        # bilinear sampling reads it at every island border: bright lines
        # along every mesh edge, immune to recolouring. Standard edge
        # padding: bleed each island's border colours into the gutter, and
        # clamp the class mask to real islands so gutter texels cannot
        # classify as moss.
        mesh.calc_loop_triangles()
        uv_data = mesh.uv_layers.active.data
        coverage = _uv_coverage(mesh, uv_data, width, height)
        flat_mask = flat_mask & coverage.reshape(-1)
        mask = flat_mask.reshape(height, width)
        source_pixels[..., :3] = _pad_edges(
            source_pixels[..., :3].reshape(-1, 3),
            coverage.reshape(-1),
            width,
            height,
            steps=8,
        ).reshape(height, width, 3)

        def build_material(class_name: str, moss_only: bool):
            material = base_material.copy()
            material.name = class_name
            image = albedo.copy()
            image.name = "%s_detail" % class_name
            detail = source_pixels.copy()
            class_rows = mask if moss_only else numpy.ones_like(mask)
            class_pixels = detail[..., :3][class_rows.astype(bool)]
            factor = numpy.maximum(
                class_pixels.reshape(-1, 3).max(axis=0), 0.05
            )
            detail[..., :3] = numpy.clip(
                detail[..., :3] / factor[None, None, :], 0.0, 1.0
            )
            if moss_only and detail.shape[-1] >= 4:
                # The alpha mask must reach PAST every UV island border: the
                # mask ends exactly at each seam, so the cutoff discarded a
                # hair of shell along every seam edge inside a moss patch and
                # the base showed through as thin lines following the mesh
                # edges. Alpha grows 3 texels; RGB is padded further out so
                # the grown rim wears moss colour, not clipped stone.
                detail[..., :3] = _pad_edges(
                    detail[..., :3].reshape(-1, 3),
                    mask.reshape(-1),
                    width,
                    height,
                    steps=8,
                ).reshape(height, width, 3)
                alpha_mask = _dilate(mask.reshape(-1), width, height, 3)
                detail[..., 3] = numpy.where(
                    alpha_mask.reshape(height, width), 1.0, 0.0
                )
            # Fill everything this material must never show with its OWN mean
            # colour: the atlas gutter, and (for stone) the moss regions. An
            # 8-texel pad is enough for bilinear sampling but NOT for mipmaps,
            # which average over ever-larger areas -- that is how the green
            # gutter kept bleeding into the stone at edges and distance, as
            # thin lines no slot could recolour.
            fill_target = (~coverage).reshape(-1)
            if not moss_only:
                fill_target = fill_target | mask.reshape(-1)
            flat_rgb = detail[..., :3].reshape(-1, 3)
            keep = ~fill_target
            if keep.any() and fill_target.any():
                flat_rgb[fill_target] = flat_rgb[keep].mean(axis=0)
                detail[..., :3] = flat_rgb.reshape(height, width, 3)
            if not moss_only:
                # ERASE every moss pixel from the base texture. The shell hides
                # them, so their content is never meant to be seen -- but the
                # shell is offset outward, so wherever the two meshes part
                # company (convex edges, the silhouette) the base peeks
                # through, and while it held the original moss green those
                # peeks rendered as bright lines that belonged to NO slot and
                # no recolour could reach. Filled with the stone class mean,
                # any peek is stone-coloured and follows the stone slot.
                pass
            image.pixels = detail.reshape(-1).tolist()
            image.pack()
            tree = material.node_tree
            principled = next(
                node for node in tree.nodes if node.type == "BSDF_PRINCIPLED"
            )
            # Only the albedo may carry a texture. The source's other maps ride
            # along on the copied node tree and export as a metallicRoughness
            # texture -- fed by the DETAIL image, so roughness followed the
            # picture: dark moss pixels went glossy and reflected the sky as
            # cyan fringes along every edge. Strip every non-albedo texture
            # node and pin metallic/roughness to the game's flat-prop values.
            albedo_node = None
            base_links = principled.inputs["Base Color"].links
            if base_links:
                current = base_links[0].from_node
                seen = set()
                while current is not None and current not in seen:
                    seen.add(current)
                    if current.type == "TEX_IMAGE":
                        albedo_node = current
                        break
                    upstream = None
                    for socket in current.inputs:
                        if socket.links:
                            upstream = socket.links[0].from_node
                            break
                    current = upstream
            # nodes.remove() invalidates every other python node reference,
            # so removal works on NAMES and everything is re-fetched after.
            albedo_name = albedo_node.name if albedo_node is not None else ""
            doomed_names = [
                node.name
                for node in tree.nodes
                if node.type == "TEX_IMAGE" and node.name != albedo_name
            ]
            for name in doomed_names:
                tree.nodes.remove(tree.nodes[name])
            principled = next(
                node for node in tree.nodes if node.type == "BSDF_PRINCIPLED"
            )
            albedo_node = tree.nodes.get(albedo_name)
            if albedo_node is not None:
                albedo_node.image = image
            for input_name, value in (("Metallic", 0.0), ("Roughness", 1.0)):
                socket = principled.inputs[input_name]
                for link in list(socket.links):
                    tree.links.remove(link)
                socket.default_value = value
            base_input = principled.inputs["Base Color"]
            texture_socket = base_input.links[0].from_socket
            texture_node = base_input.links[0].from_node
            tree.links.remove(base_input.links[0])
            mix = tree.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (
                float(factor[0]), float(factor[1]), float(factor[2]), 1.0
            )
            tree.links.new(texture_socket, mix.inputs[6])
            tree.links.new(mix.outputs[2], base_input)
            if moss_only:
                material.blend_method = "CLIP"
                material.alpha_threshold = 0.5
                tree.links.new(
                    texture_node.outputs["Alpha"],
                    principled.inputs["Alpha"],
                )
            return material

        stone = build_material("well_stone", False)
        moss = build_material("well_moss", True)
        mesh.materials.clear()
        mesh.materials.append(stone)
        for polygon in mesh.polygons:
            polygon.material_index = 0

        # The shell duplicates the WHOLE mesh, not only moss-touching faces.
        # A partial shell has a boundary edge around every patch, and because
        # the shell is offset outward the base shows through along each one --
        # thin lines tracing the patches. A full shell has no boundary except
        # the model's own silhouette.

        overlay_object = mesh_object.copy()
        overlay_object.data = mesh_object.data.copy()
        overlay_object.name = "%sMossShell" % mesh_object.name
        overlay_object.data.name = overlay_object.name
        bpy.context.scene.collection.objects.link(overlay_object)
        overlay_object.parent = mesh_object.parent
        overlay_object.matrix_world = mesh_object.matrix_world.copy()

        working = bmesh.new()
        working.from_mesh(overlay_object.data)
        working.faces.ensure_lookup_table()
        # A hair outward along the vertex normals, so the shell wins the depth
        # test against the base it duplicates. Kept small: this offset is what
        # opens the wedge at convex edges where the base peeks through.
        for vertex in working.verts:
            vertex.co += vertex.normal * 0.0015
        working.to_mesh(overlay_object.data)
        working.free()
        overlay_object.data.materials.clear()
        overlay_object.data.materials.append(moss)
        for polygon in overlay_object.data.polygons:
            polygon.material_index = 0
        overlay_object.data.update()
        print(
            "  %s: %d base faces, %d shell faces (full duplicate)"
            % (mesh_object.name, len(mesh.polygons), len(mesh.polygons))
        )


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    bpy.context.view_layer.update()

    # Only the base-colour texture carries paint. The other maps -- roughness,
    # metallic, normal -- encode data as colours, and shifting them corrupts
    # the material (the well's Image_1 is a solid cyan data map).
    albedo_names = set()
    for material in bpy.data.materials:
        albedo = P.base_color_image(material)
        if albedo is not None:
            albedo_names.add(albedo.name)
    class_masks = {}
    class_targets = {}
    for image in bpy.data.images:
        if image.size[0] > 0 and image.name in albedo_names:
            mask, targets = shift_image(image)
            class_masks[image.name] = mask
            class_targets.update(targets)
    if len(class_targets) == 2:
        split_material_slots(class_masks, class_targets)

    # Ground at the base like every installed asset.
    lowest = min(
        (item.matrix_world @ vertex.co).z
        for item in bpy.context.scene.objects
        if item.type == "MESH"
        for vertex in item.data.vertices
    )
    for item in bpy.context.scene.objects:
        if item.parent is None:
            item.location.z -= lowest

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    glb_export.flatten_shading(meshes)
    bpy.ops.object.select_all(action="SELECT")
    glb_export.export_selected(arguments.output)
    _force_mask_alpha(arguments.output)
    print(f"SHIFT_OUT={arguments.output}")


def _force_mask_alpha(path: Path) -> None:
    """Rewrites well_moss to alphaMode MASK in the exported glb.

    Blender 4.5 dropped the blend_method property the exporter used to key
    MASK on, so the shell arrives as BLEND -- putting it in the transparent
    pass, where it stops writing depth and sorts per object. MASK keeps the
    crisp cut-out edge and the opaque pass. Patched in the file because the
    exporter offers no per-material override.
    """
    import json
    import struct

    data = bytearray(path.read_bytes())
    json_length = struct.unpack("<I", data[12:16])[0]
    document = json.loads(data[20 : 20 + json_length].decode("utf-8"))
    changed = False
    for material in document.get("materials", []):
        if material.get("name") == "well_moss":
            material["alphaMode"] = "MASK"
            material["alphaCutoff"] = 0.5
            changed = True
    if not changed:
        return
    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    rest = bytes(data[20 + json_length :])
    header = struct.pack("<I", 12 + 8 + len(encoded) + len(rest))
    out = (
        data[:8]
        + header
        + struct.pack("<I", len(encoded))
        + b"JSON"
        + encoded
        + rest
    )
    path.write_bytes(out)


if __name__ == "__main__":
    main()

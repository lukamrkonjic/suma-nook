#!/usr/bin/env python3
"""Rebuild the curated free itch.io models into Suma's runtime asset contract.

Run under Blender 4.5+ after extracting the pinned archives beside the
manifest (the extraction directory is intentionally git-ignored):

  blender --background --factory-startup --python \
    art_source/blender/process_itch_free_packs.py

The importer removes every source texture and source material. Each polygon is
sampled at its source UV centroid, mapped to the nearest canonical Suma palette
token, and assigned a new flat semantic material. Source topology and shading
flags are preserved exactly; only object transforms are changed to recentre,
ground, and normalise each placeable's gameplay footprint. The result is exported
as deterministic GLBs plus generated structure/wish registries.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import struct
import sys
import traceback
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
IMPORT_ROOT = ROOT / "art_source" / "imported" / "itch_free_packs"
MANIFEST_PATH = IMPORT_ROOT / "manifest.json"
ARCHIVE_ROOT = IMPORT_ROOT / "archives"
EXTRACTED_ROOT = IMPORT_ROOT / "extracted"
REPORT_PATH = IMPORT_ROOT / "generation_report.json"
OUT = ROOT / "assets" / "3d" / "reworked"
STRUCTURES_PATH = ROOT / "data" / "itch_structures.json"
REWARDS_PATH = ROOT / "data" / "itch_wish_rewards.json"

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_gg_assets import PALETTE, srgb  # noqa: E402


PALETTE_LINEAR = {
    token: tuple(srgb(hexcode)[:3]) for token, hexcode in PALETTE.items()
}
PALETTE_MATERIALS: dict[str, bpy.types.Material] = {}
IMAGE_PIXELS: dict[str, tuple[int, int, list[float]]] = {}

VALID_CATEGORIES = {
    "land", "furniture", "garden", "woodland", "camp", "waterside",
    "stonework", "homestead",
}

FOLIAGE_TOKENS = {
    "deep_grass", "earthy_olive", "grass_highlight", "grass_primary",
    "grass_secondary", "grass_shade", "grass_sunlit", "grass_vivid_accent",
    "leaf_bright", "leaf_medium", "leaf_olive", "leaf_soft_sage",
    "moss_bright", "moss_primary", "olive_shadow", "pine_deep",
    "pine_light", "pine_medium", "pine_shadow", "soft_sage_gray",
}
STONE_TOKENS = {
    "concrete_deep", "concrete_highlight", "concrete_light",
    "concrete_shadow", "ivory_highlight", "smoke", "snow_deep",
    "snow_highlight", "snow_light", "snow_shadow", "stone_deep_shadow",
    "stone_light", "stone_mid", "stone_mid_light", "stone_shadow",
    "stone_warm_shadow", "warm_near_black", "warm_white",
}
WATER_TOKENS = {
    "crystal", "soft_sage_gray", "water_abyss", "water_caustic",
    "water_deep", "water_deep_mid", "water_foam", "water_mid",
    "water_shallow", "water_shallow_highlight", "water_turquoise",
}
WARM_TOKENS = {
    "brown_fabric", "burnt_red", "coral", "cream_fabric", "dark_fabric",
    "earth_deep", "earth_light", "earth_mid", "earth_primary",
    "earth_shadow", "fire_core", "fire_orange", "fire_red", "fire_yellow",
    "gold_deep", "gold_highlight", "gold_primary", "mustard_fabric",
    "sand_deep", "sand_highlight", "sand_light", "sand_shadow", "sand_top",
    "soft_coral", "soil_deep", "soil_deepest", "soil_orange",
    "soil_red_shadow", "terracotta_light", "terracotta_orange",
    "terracotta_primary", "terracotta_shadow", "warm_near_black",
    "warm_white", "warm_yellow", "wood_brown",
}

TINY_WORDS = {
    "apple", "bowl", "cheese", "cup", "dart", "dragonfly", "flower",
    "fork", "frisbee", "grapes", "jam", "knife", "letter", "mug",
    "nail", "pebble", "pencil", "plate", "screw", "spoon", "trowel",
    "wine_glass", "water_lily_blossom",
}

def argv_has(flag: str) -> bool:
    return flag in sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else False


def argv_value(flag: str, fallback: str = "") -> str:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if flag not in args:
        return fallback
    index = args.index(flag)
    return args[index + 1] if index + 1 < len(args) else fallback


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def slug(value: str) -> str:
    clean = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return re.sub(r"_+", "_", clean)


def display_name(value: str) -> str:
    clean = re.sub(r"(?i)^th_", "", value)
    clean = re.sub(r"(?i)_color\d+$", "", clean)
    clean = re.sub(r"(?i)_mesh$", "", clean)
    clean = clean.replace("_", " ")
    clean = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", clean)
    return " ".join(word.capitalize() for word in clean.split())


def load_manifest() -> dict:
    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("schema_version") != 1:
        raise RuntimeError("Unsupported itch manifest schema")
    return manifest


def verify_archives(manifest: dict) -> None:
    for pack in manifest["packs"]:
        archive = ARCHIVE_ROOT / pack["archive"]
        if not archive.is_file():
            raise FileNotFoundError(f"Missing source archive: {archive}")
        actual = sha256(archive)
        if actual != pack["sha256"]:
            raise RuntimeError(
                f"Archive hash mismatch for {pack['id']}: {actual} != {pack['sha256']}"
            )


def selected_sources(pack: dict) -> list[Path]:
    root = EXTRACTED_ROOT / pack["id"]
    if not root.is_dir():
        raise FileNotFoundError(
            f"Missing extracted pack {root}. Extract the pinned archive first."
        )
    includes = [re.compile(pattern, re.IGNORECASE) for pattern in pack.get("include", [".*"])]
    excludes = [re.compile(pattern, re.IGNORECASE) for pattern in pack.get("exclude", [])]
    result = []
    for path in sorted(root.glob(pack["source_glob"]), key=lambda item: item.as_posix().lower()):
        if not path.is_file():
            continue
        if not any(pattern.search(path.name) for pattern in includes):
            continue
        if any(pattern.search(path.name) for pattern in excludes):
            continue
        result.append(path)
    if not result:
        raise RuntimeError(f"No curated sources matched for {pack['id']}")
    return result


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for armature in list(bpy.data.armatures):
        if armature.users == 0:
            bpy.data.armatures.remove(armature)


def import_source(path: Path) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    extension = path.suffix.lower()
    if extension in {".gltf", ".glb"}:
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif extension == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=False)
    else:
        raise RuntimeError(f"Unsupported source format: {path}")
    imported = [obj for obj in bpy.data.objects if obj not in before]
    for obj in list(imported):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
            imported.remove(obj)
    if not any(obj.type == "MESH" for obj in imported):
        raise RuntimeError(f"Imported source has no mesh: {path}")
    return imported


def palette_material(token: str) -> bpy.types.Material:
    cached = PALETTE_MATERIALS.get(token)
    if cached is not None and cached.name in bpy.data.materials:
        return cached
    material = bpy.data.materials.get(token) or bpy.data.materials.new(token)
    material.name = token
    material.use_nodes = True
    material.diffuse_color = (*PALETTE_LINEAR[token], 1.0)
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (*PALETTE_LINEAR[token], 1.0)
    shader.inputs["Roughness"].default_value = 0.82
    shader.inputs["Metallic"].default_value = 0.0
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    PALETTE_MATERIALS[token] = material
    return material


def material_color(material: bpy.types.Material | None) -> tuple[float, float, float]:
    if material is None:
        return PALETTE_LINEAR["earth_primary"]
    if material.use_nodes and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                color = node.inputs["Base Color"].default_value
                return tuple(float(channel) for channel in color[:3])
    return tuple(float(channel) for channel in material.diffuse_color[:3])


def material_image(material: bpy.types.Material | None) -> bpy.types.Image | None:
    if material is None or not material.use_nodes or not material.node_tree:
        return None
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image is not None:
            return node.image
    return None


def cached_pixels(image: bpy.types.Image) -> tuple[int, int, list[float]] | None:
    width, height = int(image.size[0]), int(image.size[1])
    if width <= 0 or height <= 0:
        return None
    raw_path = bpy.path.abspath(image.filepath) if image.filepath else ""
    key = f"{Path(raw_path).resolve() if raw_path else image.name}|{width}x{height}"
    if key not in IMAGE_PIXELS:
        IMAGE_PIXELS[key] = (width, height, list(image.pixels[:]))
    return IMAGE_PIXELS[key]


def sampled_color(
    mesh: bpy.types.Mesh,
    polygon: bpy.types.MeshPolygon,
    material: bpy.types.Material | None,
) -> tuple[float, float, float]:
    image = material_image(material)
    uv_layer = mesh.uv_layers.active
    cache = cached_pixels(image) if image is not None else None
    if cache is None or uv_layer is None or polygon.loop_total <= 0:
        return material_color(material)
    width, height, pixels = cache
    u = 0.0
    v = 0.0
    for loop_index in polygon.loop_indices:
        uv = uv_layer.data[loop_index].uv
        u += float(uv.x)
        v += float(uv.y)
    u = (u / polygon.loop_total) % 1.0
    v = (v / polygon.loop_total) % 1.0
    x = min(width - 1, max(0, int(u * width)))
    y = min(height - 1, max(0, int(v * height)))
    index = (y * width + x) * 4
    if index + 2 >= len(pixels):
        return material_color(material)
    # Blender exposes decoded image texels here in their stored sRGB values,
    # while Principled inputs and our canonical palette are scene-linear.
    def to_linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
    return tuple(to_linear(float(pixels[index + offset])) for offset in range(3))


def nearest_palette(color: tuple[float, float, float], category: str = "") -> str:
    red, green, blue = color
    chroma = max(color) - min(color)
    greenish = green > red * 1.10 and green > blue * 1.04
    if max(color) < 0.035:
        candidates = {"warm_near_black", "hair_deep", "soil_deepest"}
    elif category == "stonework" and greenish:
        candidates = FOLIAGE_TOKENS
    elif category == "stonework":
        candidates = STONE_TOKENS
    elif category == "waterside" and blue > red * 1.15 and blue > green * 1.08:
        candidates = WATER_TOKENS
    elif chroma < 0.075:
        candidates = STONE_TOKENS
    elif greenish:
        candidates = FOLIAGE_TOKENS
    elif blue > red * 1.12 and (blue > green * 1.08 or green > red * 1.28):
        candidates = WATER_TOKENS
    else:
        candidates = WARM_TOKENS
    # Above-water natural pieces must never drift into the separate underwater
    # material language merely because a source green is slightly blue-leaning.
    if category in {"woodland", "garden", "land", "stonework"}:
        candidates = candidates - {token for token in candidates if token.startswith("uw_")}
    return min(
        candidates,
        key=lambda token: sum(
            (float(color[index]) - PALETTE_LINEAR[token][index]) ** 2
            for index in range(3)
        ),
    )


def replace_with_suma_palette(mesh_object: bpy.types.Object, category: str) -> set[str]:
    mesh = mesh_object.data
    source_materials = [slot.material for slot in mesh_object.material_slots]
    assignments = []
    sampled_inputs = []
    tokens: set[str] = set()
    for polygon in mesh.polygons:
        source_material = (
            source_materials[polygon.material_index]
            if polygon.material_index < len(source_materials)
            else None
        )
        color = sampled_color(mesh, polygon, source_material)
        token = nearest_palette(color, category)
        assignments.append(token)
        if len(sampled_inputs) < 12:
            sampled_inputs.append((tuple(round(channel, 4) for channel in color), token))
        tokens.add(token)
    ordered = sorted(tokens)
    mesh.materials.clear()
    for token in ordered:
        mesh.materials.append(palette_material(token))
    indices = {token: index for index, token in enumerate(ordered)}
    for polygon, token in zip(mesh.polygons, assignments):
        polygon.material_index = indices[token]
    if argv_has("--debug-colors"):
        source_report = [
            {
                "name": material.name if material else "",
                "image": material_image(material).name if material_image(material) else "",
                "image_path": material_image(material).filepath if material_image(material) else "",
                "image_size": tuple(material_image(material).size) if material_image(material) else (),
                "color": tuple(round(channel, 4) for channel in material_color(material)),
            }
            for material in source_materials
        ]
        print(
            f"[colors] {mesh_object.name}: sources={source_report} "
            f"samples={sampled_inputs} tokens={sorted(tokens)}"
        )
    return tokens


def mesh_style_signature(mesh_object: bpy.types.Object) -> dict:
    """Topology/shading contract used to prevent accidental style mutation."""
    mesh = mesh_object.data
    return {
        "vertices": len(mesh.vertices),
        "edges": len(mesh.edges),
        "polygons": len(mesh.polygons),
        "smooth_faces": sum(1 for face in mesh.polygons if face.use_smooth),
        "sharp_edges": sum(1 for edge in mesh.edges if edge.use_edge_sharp),
    }


def hierarchy_roots(objects: list[bpy.types.Object]) -> list[bpy.types.Object]:
    object_set = set(objects)
    return [obj for obj in objects if obj.parent not in object_set]


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("Cannot calculate bounds without mesh objects")
    minimum = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
    maximum = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
    return minimum, maximum


def desired_size(name: str, category: str) -> tuple[float, float]:
    lowered = slug(name)
    if any(word in lowered for word in TINY_WORDS):
        return 0.42, 0.9
    if any(word in lowered for word in ("house", "building", "floor", "roof", "wall", "pond", "watertower")):
        return 1.52, 2.65
    if any(word in lowered for word in ("tree", "pine")):
        return 1.22, 3.2
    if category in {"stonework", "homestead"}:
        return 1.18, 2.1
    return 0.96, 1.85


def normalise_placeable(objects: list[bpy.types.Object], name: str, category: str) -> dict:
    roots = hierarchy_roots(objects)
    minimum, maximum = world_bounds(objects)
    centre = Vector(((minimum.x + maximum.x) * 0.5, (minimum.y + maximum.y) * 0.5, minimum.z))
    for root in roots:
        root.matrix_world.translation -= centre
    bpy.context.view_layer.update()
    minimum, maximum = world_bounds(objects)
    size = maximum - minimum
    footprint = max(float(size.x), float(size.y), 0.0001)
    target_footprint, max_height = desired_size(name, category)
    scale = min(target_footprint / footprint, max_height / max(float(size.z), 0.0001))
    scale = max(0.0001, min(100.0, scale))
    for root in roots:
        root.scale *= scale
    bpy.context.view_layer.update()
    minimum, maximum = world_bounds(objects)
    if abs(minimum.z) > 0.00001:
        for root in roots:
            root.matrix_world.translation.z -= minimum.z
        bpy.context.view_layer.update()
    minimum, maximum = world_bounds(objects)
    return {
        "min": [round(value, 5) for value in minimum],
        "max": [round(value, 5) for value in maximum],
        "size": [round(value, 5) for value in (maximum - minimum)],
        "scale_applied": round(scale, 7),
    }


def classify(pack_id: str, source_name: str) -> str:
    name = slug(source_name)
    if pack_id == "kaykit_forest":
        return "stonework" if "rock" in name else "woodland"
    if pack_id == "assetquest_pond":
        if any(word in name for word in ("rock", "pebble")):
            return "stonework"
        return "waterside"
    if pack_id == "treehouse_modular":
        return "furniture" if any(word in name for word in ("chair", "stool", "table", "chess", "chest", "bucket")) else "homestead"
    if pack_id == "kaykit_rpg_tools":
        return "camp" if any(word in name for word in ("lantern", "torch")) else "homestead"
    if pack_id == "gobkit_animals":
        return "waterside" if any(word in name for word in ("duck", "platypus")) else "woodland"
    if pack_id == "kaykit_city_bits":
        if "bench" in name:
            return "furniture"
        if "bush" in name:
            return "garden"
        return "homestead"
    if pack_id == "kaykit_adventurers":
        return "furniture"
    if pack_id == "tiny_pretty_park":
        if "floor" in name:
            return "land"
        if any(word in name for word in ("cobble",)):
            return "stonework"
        if any(word in name for word in ("fountain", "bird")):
            return "waterside"
        if "bench" in name:
            return "furniture"
        if "lantern" in name:
            return "camp"
        return "woodland" if "tree" in name else "garden"
    if pack_id == "tiny_pleasant_picnic":
        return "camp" if any(word in name for word in ("blanket", "basket", "cooler", "thermos", "radio", "frisbee")) else "furniture"
    if pack_id == "tiny_homely_house":
        if any(word in name for word in ("bench", "doormat")):
            return "furniture"
        if any(word in name for word in ("tree", "foliage")):
            return "woodland"
        if "cobble" in name:
            return "stonework"
        return "homestead"
    if pack_id == "fishing_village":
        if any(word in name for word in ("boat", "dock", "fish", "water")):
            return "waterside"
        if any(word in name for word in ("rock", "stone")):
            return "stonework"
        if any(word in name for word in ("tree", "bush", "grass")):
            return "woodland"
        return "homestead"
    return "homestead"


def structure_spec(asset_id: str, name: str, category: str, pack_id: str) -> dict:
    lowered = slug(name)
    tiny = any(word in lowered for word in TINY_WORDS)
    large = any(word in lowered for word in ("house", "building", "floor", "roof", "wall", "pond", "watertower"))
    natural = category in {"woodland", "garden", "waterside", "stonework"}
    # Imported miniatures remain ordinary placeables until their precise
    # support fit has been authored and tested against Suma's named slots.
    # Size alone is not enough to opt an object into tabletop stacking.
    placement_tags = ["decoration", "small"] if tiny else (["natural", "medium"] if natural else ["decoration", "large" if large else "medium"])
    allowed_surfaces = ["water"] if any(word in lowered for word in ("anglerfish", "jellyfish", "shark")) else ["flat", "stairs", "uneven"]
    return {
        "id": f"struct_{asset_id}",
        "name": display_name(name),
        "asset_id": asset_id,
        "kind": "decoration",
        "socket_type": "structure" if large else "decor",
        "blocks_movement": large,
        "collision_profile": "blocker" if large else "none",
        "grid_fit_profile": "tile_span" if large else "",
        "placement_sound": "stone" if category == "stonework" else "wood",
        "allowed_surfaces": allowed_surfaces,
        "placement_tags": placement_tags,
        "can_be_stacked": False,
        "support_slots": [],
        "itch_pack": pack_id,
    }


def reward_weight(pack_id: str, name: str) -> float:
    lowered = slug(name)
    if any(word in lowered for word in ("house", "fountain", "pond", "watertower")):
        return 0.12
    if pack_id == "kaykit_forest":
        return 0.16
    if pack_id in {"assetquest_pond", "treehouse_modular"}:
        return 0.22
    return 0.38


def export_glb(asset_id: str, objects: list[bpy.types.Object]) -> Path:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(obj for obj in objects if obj.type == "MESH")
    output = OUT / f"{asset_id}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
        export_materials="EXPORT",
    )
    return output


def repair_source_images(pack_id: str, mesh_objects: list[bpy.types.Object]) -> None:
    if pack_id != "assetquest_pond":
        return
    atlas_path = EXTRACTED_ROOT / pack_id / "Textures" / "Pond_Props_BaseColor.png"
    if not atlas_path.is_file():
        raise FileNotFoundError(f"Pond palette atlas is missing: {atlas_path}")
    atlas = bpy.data.images.load(str(atlas_path), check_existing=True)
    for mesh_object in mesh_objects:
        for slot in mesh_object.material_slots:
            material = slot.material
            if material is None or not material.use_nodes or not material.node_tree:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and (node.image is None or min(node.image.size) <= 0):
                    node.image = atlas


def validate_palette_only_glb(path: Path) -> dict:
    with path.open("rb") as handle:
        header = handle.read(12)
        if len(header) != 12 or header[:4] != b"glTF":
            raise RuntimeError(f"Invalid GLB header: {path}")
        chunk_length, chunk_type = struct.unpack("<II", handle.read(8))
        if chunk_type != 0x4E4F534A:
            raise RuntimeError(f"GLB JSON chunk is missing: {path}")
        document = json.loads(handle.read(chunk_length).decode("utf-8").rstrip("\x00 \t\r\n"))
    if document.get("images") or document.get("textures"):
        raise RuntimeError(f"Source texture leaked into palette-only output: {path}")
    material_names = [material.get("name", "") for material in document.get("materials", [])]
    unknown = sorted(name for name in material_names if name not in PALETTE)
    if unknown:
        raise RuntimeError(f"Non-palette materials in {path.name}: {unknown}")
    return {
        "materials": material_names,
        "image_count": len(document.get("images", [])),
        "texture_count": len(document.get("textures", [])),
    }


def process_group(pack: dict, source: Path, name: str, objects: list[bpy.types.Object]) -> dict:
    category = classify(pack["id"], name)
    if category not in VALID_CATEGORIES:
        raise RuntimeError(f"Invalid category {category} for {name}")
    palette_tokens: set[str] = set()
    mesh_objects = [obj for obj in objects if obj.type == "MESH"]
    repair_source_images(pack["id"], mesh_objects)
    source_geometry = [mesh_style_signature(obj) for obj in mesh_objects]
    for obj in mesh_objects:
        palette_tokens.update(replace_with_suma_palette(obj, category))
    ported_geometry = [mesh_style_signature(obj) for obj in mesh_objects]
    if ported_geometry != source_geometry:
        raise RuntimeError(f"Palette conversion changed source geometry or shading: {name}")
    bounds = normalise_placeable(objects, name, category)
    asset_id = f"itch_{pack['id']}_{slug(name)}"
    output = export_glb(asset_id, objects)
    glb_validation = validate_palette_only_glb(output)
    return {
        "asset_id": asset_id,
        "structure_id": f"struct_{asset_id}",
        "display_name": display_name(name),
        "category": category,
        "pack_id": pack["id"],
        "source": source.relative_to(ROOT).as_posix(),
        "output": output.relative_to(ROOT).as_posix(),
        "sha256": sha256(output),
        "palette_tokens": sorted(palette_tokens),
        "mesh_count": len(mesh_objects),
        "polygon_count": sum(len(obj.data.polygons) for obj in mesh_objects),
        "source_geometry": source_geometry,
        "bounds": bounds,
        "glb_validation": glb_validation,
    }


def split_groups(imported: list[bpy.types.Object]) -> list[tuple[str, list[bpy.types.Object]]]:
    meshes = [obj for obj in imported if obj.type == "MESH"]
    groups: list[tuple[str, list[bpy.types.Object]]] = []
    seen_names: set[str] = set()
    for index, mesh in enumerate(meshes):
        base = slug(mesh.name) or f"piece_{index + 1:02d}"
        unique = base
        serial = 2
        while unique in seen_names:
            unique = f"{base}_{serial}"
            serial += 1
        seen_names.add(unique)
        clone = mesh.copy()
        clone.data = mesh.data.copy()
        clone.animation_data_clear()
        clone.parent = None
        clone.matrix_world = mesh.matrix_world.copy()
        bpy.context.scene.collection.objects.link(clone)
        groups.append((unique, [clone]))
    return groups


def inspect_pack(pack: dict, sources: list[Path]) -> None:
    print(f"[inspect] {pack['id']} curated_sources={len(sources)}")
    for source in sources:
        clear_scene()
        imported = import_source(source)
        meshes = [obj for obj in imported if obj.type == "MESH"]
        materials = sorted({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material})
        print(
            f"  {source.name}: meshes={len(meshes)} materials={materials} "
            f"objects={[obj.name for obj in meshes[:80]]}"
        )


def process_pack(pack: dict, sources: list[Path], limit: int = 0) -> list[dict]:
    entries: list[dict] = []
    for source in sources[:limit or None]:
        clear_scene()
        imported = import_source(source)
        if pack.get("split_scene"):
            groups = split_groups(imported)
            for name, objects in groups:
                entry = process_group(pack, source, name, objects)
                entries.append(entry)
                for obj in objects:
                    bpy.data.objects.remove(obj, do_unlink=True)
        else:
            name = source.stem
            entries.append(process_group(pack, source, name, imported))
        print(f"[pack] {pack['id']} {source.name} -> total={len(entries)}")
    return entries


def write_generated_catalog(entries: list[dict]) -> None:
    structures = [
        structure_spec(
            entry["asset_id"], entry["display_name"], entry["category"], entry["pack_id"]
        )
        for entry in entries
    ]
    rewards = [
        {
            "kind": "structure",
            "id": entry["structure_id"],
            "category": entry["category"],
            "weight": reward_weight(entry["pack_id"], entry["display_name"]),
        }
        for entry in entries
    ]
    STRUCTURES_PATH.write_text(
        json.dumps({"structures": structures}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    REWARDS_PATH.write_text(
        json.dumps({"pool_id": "void_unknown", "rewards": rewards}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    verify_archives(manifest)
    if argv_has("--catalog-only"):
        with REPORT_PATH.open("r", encoding="utf-8") as handle:
            existing_report = json.load(handle)
        write_generated_catalog(existing_report["assets"])
        print(f"ITCH CATALOG REFRESH COMPLETE assets={len(existing_report['assets'])}")
        return
    pack_filter = argv_value("--pack")
    limit = int(argv_value("--limit", "0"))
    selected_packs = [
        pack for pack in manifest["packs"] if not pack_filter or pack["id"] == pack_filter
    ]
    if not selected_packs:
        raise RuntimeError(f"Unknown pack filter: {pack_filter}")
    all_sources = {pack["id"]: selected_sources(pack) for pack in selected_packs}
    if argv_has("--inspect"):
        for pack in selected_packs:
            inspect_pack(pack, all_sources[pack["id"]])
        return
    entries: list[dict] = []
    for pack in selected_packs:
        entries.extend(process_pack(pack, all_sources[pack["id"]], limit))
    asset_ids = [entry["asset_id"] for entry in entries]
    if len(asset_ids) != len(set(asset_ids)):
        raise RuntimeError("Duplicate generated asset ids")
    report = {
        "schema_version": 1,
        "generator": "art_source/blender/process_itch_free_packs.py",
        "palette": "assets/palettes/gg_material_palette.tres",
        "texture_policy": "Source textures sampled for classification, then completely removed.",
        "pack_count": len(selected_packs),
        "asset_count": len(entries),
        "packs": [
            {
                "id": pack["id"],
                "name": pack["name"],
                "url": pack["url"],
                "license": pack["license"],
                "archive_sha256": pack["sha256"],
                "asset_count": sum(1 for entry in entries if entry["pack_id"] == pack["id"]),
            }
            for pack in selected_packs
        ],
        "assets": entries,
    }
    REPORT_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if not pack_filter and not limit:
        write_generated_catalog(entries)
    print(f"ITCH PORT COMPLETE assets={len(entries)} report={REPORT_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)

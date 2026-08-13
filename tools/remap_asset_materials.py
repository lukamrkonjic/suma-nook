"""Rename semantic material slots inside a shipped GLB.

The Meshy importer quantises a source texture onto Suma's semantic palette by
nearest tone, and sometimes lands on a slot that is numerically close but
semantically wrong -- bamboo's pale yellow snapping to `gold_primary`, the
treasure/metal tone, rather than a wood tone.

Renaming the slot in the GLB beats a runtime override in
data/asset_edits.json, because MaterialLibrary rebinds by material NAME at
load, so the corrected name is what the game resolves.

The rename alone is not enough. Offline renders read the colour baked into
the GLB, not the runtime palette, so a renamed-but-not-recoloured slot looks
unchanged in every review image while being correct in game -- the renders
quietly lie. This tool therefore also writes the new token's palette colour
into the material, so the GLB and the runtime agree.

Palette colours are authored sRGB and glTF stores linear, so the value is
converted on the way in; skipping that step is how a corrected asset ends up
render-accurate but visibly too bright.

Run headless:
  blender --background --factory-startup --python tools/remap_asset_materials.py \
    -- --asset assets/3d/reworked/prop_bamboo_table.glb --map gold_primary=wood_gold
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import bpy

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PALETTE_PATH = REPOSITORY_ROOT / "assets" / "palettes" / "gg_material_palette.tres"


def palette_colour(token: str) -> tuple[float, float, float] | None:
    """First sRGB entry for a token in the shared palette, as linear RGB."""
    pattern = re.compile(
        rf'"{re.escape(token)}"\s*:\s*Color\(([^)]+)\)'
    )
    match = pattern.search(PALETTE_PATH.read_text(encoding="utf-8"))
    if match is None:
        return None
    parts = [float(value) for value in match.group(1).split(",")[:3]]
    return tuple(
        channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        for channel in parts
    )


def set_base_colour(material: bpy.types.Material, colour: tuple[float, float, float]) -> bool:
    if not material.use_nodes:
        return False
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            node.inputs["Base Color"].default_value = (*colour, 1.0)
            return True
    return False


def parse_args() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", required=True, type=Path)
    parser.add_argument(
        "--map",
        nargs="+",
        required=True,
        metavar="OLD=NEW",
        help="Slot renames, e.g. gold_primary=wood_gold.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Defaults to overwriting --asset in place.",
    )
    return parser.parse_args(arguments)


def main() -> None:
    arguments = parse_args()
    source = arguments.asset.resolve()
    if not source.is_file():
        raise SystemExit(f"Missing asset: {source}")

    renames: dict[str, str] = {}
    for pair in arguments.map:
        if "=" not in pair:
            raise SystemExit(f"Expected OLD=NEW, got {pair!r}")
        old, new = pair.split("=", 1)
        renames[old.strip()] = new.strip()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))

    # Count faces per slot before renaming so the report proves which slots
    # actually carried geometry, not merely which were declared.
    counts: dict[str, int] = {}
    for item in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        for polygon in item.data.polygons:
            if polygon.material_index < len(item.data.materials):
                material = item.data.materials[polygon.material_index]
                if material is not None:
                    counts[material.name] = counts.get(material.name, 0) + 1

    applied: dict[str, int] = {}
    for material in bpy.data.materials:
        target = renames.get(material.name)
        if target is None:
            continue
        colour = palette_colour(target)
        if colour is None:
            raise SystemExit(f"No palette entry for token {target!r}")
        recoloured = set_base_colour(material, colour)
        applied[f"{material.name} -> {target}"] = counts.get(material.name, 0)
        material.name = target
        if not recoloured:
            print(f"WARNING no Principled BSDF on {target}; name changed, colour not")

    missing = [old for old in renames if not any(old in key for key in applied)]
    if missing:
        raise SystemExit(
            f"Slots not present in {source.name}: {', '.join(missing)}. "
            f"Found: {', '.join(sorted(counts))}"
        )

    destination = (arguments.output or arguments.asset).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
    )
    for change, faces in applied.items():
        print(f"REMAPPED {change} ({faces} faces)")
    print(f"REMAP_OUT={destination}")


if __name__ == "__main__":
    main()

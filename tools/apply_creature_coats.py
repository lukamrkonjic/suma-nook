"""Stamp fitting 'coat' properties onto every creature definition.

Coat = shader surface life (pattern/ruffle/strands/gloss) + geometry
accents (feathers/wool/ridge/fur tufts). Each creature gets properties
that suit what it is: tabby stripes, deer speckles, panda patches, bee
bands, wool puffs, dragon ridges, slime gloss, ghost wisp-ruffle.

Run:  python tools/apply_creature_coats.py
"""
import json
from pathlib import Path

CREATURE_DIR = Path(__file__).resolve().parent.parent / "data" / "creatures"

COATS = {
    "nook_kit": {"style": "fur", "pattern": "stripes", "pattern_color": "#C96B3F", "pattern_scale": 16, "strength": 0.22, "ruffle": 0.0035, "strands": 0.5, "accent_color": "#F6E6C8", "sway": 0.1},
    "nook_owl": {"style": "feathers", "pattern": "bands", "pattern_color": "#8E7657", "pattern_scale": 26, "strength": 0.18, "ruffle": 0.003, "strands": 0.55, "accent_color": "#8E7657", "sway": 0.12},
    "meadow_pup": {"style": "fur", "pattern": "patches", "pattern_color": "#B08A5A", "pattern_scale": 9, "strength": 0.4, "ruffle": 0.0035, "strands": 0.5, "accent_color": "#D9B27E"},
    "boing_roo": {"style": "fur", "pattern": "none", "ruffle": 0.003, "strands": 0.45, "accent_color": "#D19C72"},
    "sprout_scout": {"style": "fur", "pattern": "speckle", "pattern_color": "#5E7A52", "pattern_scale": 30, "strength": 0.3, "ruffle": 0.0025, "strands": 0.35, "accent_color": "#93BA7A"},
    "moss_scuttler": {"style": "scales", "pattern": "speckle", "pattern_color": "#54786D", "pattern_scale": 34, "strength": 0.4, "gloss": 0.25, "accent_color": "#54786D"},
    "triblob": {"pattern": "none", "gloss": 0.3, "ruffle": 0.002},
    "ember_cat": {"style": "fur", "pattern": "stripes", "pattern_color": "#D9843C", "pattern_scale": 22, "strength": 0.5, "ruffle": 0.003, "strands": 0.55, "accent_color": "#D98B48"},
    "dusk_fox": {"style": "fur", "pattern": "none", "ruffle": 0.0035, "strands": 0.6, "accent_color": "#FBEFD6"},
    "dawn_fawn": {"style": "fur", "pattern": "speckle", "pattern_color": "#F5E9CE", "pattern_scale": 26, "strength": 0.55, "ruffle": 0.0025, "strands": 0.4, "accent_color": "#E2B37C"},
    "bramble_bear": {"style": "fur", "pattern": "none", "ruffle": 0.004, "strands": 0.55, "accent_color": "#997656"},
    "pebble_phant": {"pattern": "patches", "pattern_color": "#8B93A8", "pattern_scale": 8, "strength": 0.18, "ruffle": 0.0015},
    "puddle_pig": {"pattern": "speckle", "pattern_color": "#F6C3CE", "pattern_scale": 20, "strength": 0.3, "gloss": 0.12, "ruffle": 0.0015},
    "cloud_sheep": {"style": "wool", "pattern": "none", "ruffle": 0.0045, "accent_color": "#F7F1E4", "sway": 0.05},
    "patch_cow": {"pattern": "patches", "pattern_color": "#5A524A", "pattern_scale": 7, "strength": 0.75, "ruffle": 0.002, "strands": 0.25},
    "breeze_pony": {"style": "fur", "pattern": "none", "ruffle": 0.0025, "strands": 0.5, "accent_color": "#8A6748", "sway": 0.14},
    "thimble_mouse": {"style": "fur", "pattern": "none", "ruffle": 0.002, "strands": 0.4, "accent_color": "#C9C2D1"},
    "bristle_hog": {"style": "scales", "pattern": "speckle", "pattern_color": "#6E5C4C", "pattern_scale": 40, "strength": 0.35, "ruffle": 0.002, "accent_color": "#584A3E"},
    "moss_shell": {"style": "scales", "pattern": "patches", "pattern_color": "#66865C", "pattern_scale": 12, "strength": 0.5, "gloss": 0.15, "accent_color": "#66865C"},
    "bandit_coon": {"style": "fur", "pattern": "stripes", "pattern_color": "#5E5866", "pattern_scale": 12, "strength": 0.4, "ruffle": 0.003, "strands": 0.5, "accent_color": "#9BA1AF"},
    "bamboo_bun": {"style": "fur", "pattern": "patches", "pattern_color": "#3F3B44", "pattern_scale": 8, "strength": 0.85, "ruffle": 0.003, "strands": 0.4, "accent_color": "#F6F1E8"},
    "waddle_pen": {"style": "feathers", "pattern": "none", "gloss": 0.12, "ruffle": 0.002, "strands": 0.4, "accent_color": "#3E4858", "sway": 0.08},
    "puddle_duck": {"style": "feathers", "pattern": "bands", "pattern_color": "#EFCB55", "pattern_scale": 22, "strength": 0.25, "ruffle": 0.0025, "strands": 0.45, "accent_color": "#EFCB55", "sway": 0.11},
    "pip_chick": {"style": "feathers", "pattern": "none", "ruffle": 0.0045, "strands": 0.5, "accent_color": "#FAE9AC", "sway": 0.16},
    "clover_hop": {"style": "fur", "pattern": "none", "ruffle": 0.0035, "strands": 0.5, "accent_color": "#E2D8CA"},
    "lily_hop": {"pattern": "speckle", "pattern_color": "#5F9E5C", "pattern_scale": 24, "strength": 0.5, "gloss": 0.3, "ruffle": 0.0015},
    "buzz_bee": {"style": "fur", "pattern": "bands", "pattern_color": "#5E4A2E", "pattern_scale": 30, "strength": 0.85, "ruffle": 0.004, "strands": 0.35, "accent_color": "#F6CE6A", "sway": 0.18},
    "dot_beetle": {"pattern": "speckle", "pattern_color": "#3F3B44", "pattern_scale": 16, "strength": 0.8, "gloss": 0.35},
    "glimmer_slime": {"pattern": "speckle", "pattern_color": "#C4E9EF", "pattern_scale": 18, "strength": 0.3, "gloss": 0.45, "ruffle": 0.003},
    "pogo_imp": {"style": "fur", "pattern": "stripes", "pattern_color": "#9E5F8E", "pattern_scale": 14, "strength": 0.28, "ruffle": 0.0025, "strands": 0.4, "accent_color": "#D190BF"},
    "grumble_gob": {"pattern": "speckle", "pattern_color": "#75894A", "pattern_scale": 30, "strength": 0.35, "gloss": 0.08, "ruffle": 0.0015},
    "wisp_ghost": {"pattern": "none", "ruffle": 0.006, "ruffle_speed": 1.4},
    "spark_dragonet": {"style": "scales", "pattern": "speckle", "pattern_color": "#8A4F43", "pattern_scale": 30, "strength": 0.5, "gloss": 0.2, "accent_color": "#8A4F43"},
    "shroomling": {"pattern": "speckle", "pattern_color": "#F6EDD8", "pattern_scale": 13, "strength": 0.6, "ruffle": 0.0015},
    "cactus_kid": {"style": "scales", "pattern": "speckle", "pattern_color": "#639458", "pattern_scale": 36, "strength": 0.45, "accent_color": "#4E7A46"},
    "snow_lump": {"style": "fur", "pattern": "none", "ruffle": 0.005, "strands": 0.6, "accent_color": "#F2F7F7", "sway": 0.07},
}


def dump_compact(data: dict) -> str:
    lines = ["{"]
    keys = list(data.keys())
    for index, key in enumerate(keys):
        comma = "," if index < len(keys) - 1 else ""
        value = json.dumps(data[key], separators=(", ", ": "))
        lines.append(f'  "{key}": {value}{comma}')
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> None:
    stamped = 0
    for path in sorted(CREATURE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        coat = COATS.get(data.get("id", ""))
        if coat is None:
            print(f"skip (no coat entry): {path.name}")
            continue
        data["coat"] = coat
        path.write_text(dump_compact(data), encoding="utf-8")
        stamped += 1
    print(f"stamped coats on {stamped} creatures")


if __name__ == "__main__":
    main()

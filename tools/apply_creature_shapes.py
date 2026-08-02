"""Stamp unique silhouette sculpting onto every creature definition.

Uses the tapered-SDF upgrade: real 3D snouts (fox point, pig disc, elephant
trunk), pear/egg torso tapers, tapered ears and tails. Snouted creatures
switch to the "pup" face style, which relocates nose/mouth decals onto the
sculpted snout tip.

Run:  python tools/apply_creature_shapes.py
"""
import json
from pathlib import Path

CREATURE_DIR = Path(__file__).resolve().parent.parent / "data" / "creatures"

# id -> {snout, torso_taper, ears_taper, tail_taper, face}
SHAPES = {
    "meadow_pup": {"snout": {"length": 0.55, "radius": 0.4, "drop": -0.18, "taper": 0.75}, "torso_taper": 1.08},
    "dusk_fox": {"snout": {"length": 0.62, "radius": 0.34, "drop": -0.16, "taper": 0.5}, "torso_taper": 0.95, "tail_taper": 0.85, "face": "pup"},
    "ember_cat": {"snout": {"length": 0.3, "radius": 0.36, "drop": -0.2, "taper": 0.78}, "torso_taper": 0.94, "tail_taper": 0.72, "face": "pup"},
    "dawn_fawn": {"snout": {"length": 0.5, "radius": 0.32, "drop": -0.2, "taper": 0.6}, "torso_taper": 0.98, "face": "pup"},
    "bramble_bear": {"snout": {"length": 0.5, "radius": 0.46, "drop": -0.22, "taper": 0.8}, "torso_taper": 0.88},
    "pebble_phant": {"snout": {"length": 1.15, "radius": 0.3, "drop": -0.3, "dip": 0.55, "taper": 0.62}, "torso_taper": 1.0},
    "puddle_pig": {"snout": {"length": 0.3, "radius": 0.44, "drop": -0.12, "taper": 0.95}, "torso_taper": 1.1},
    "patch_cow": {"snout": {"length": 0.42, "radius": 0.46, "drop": -0.2, "taper": 0.85}, "torso_taper": 1.02},
    "breeze_pony": {"snout": {"length": 0.62, "radius": 0.4, "drop": -0.24, "taper": 0.7}, "torso_taper": 0.96},
    "thimble_mouse": {"snout": {"length": 0.5, "radius": 0.32, "drop": -0.14, "taper": 0.42}, "tail_taper": 0.5, "face": "pup"},
    "bristle_hog": {"snout": {"length": 0.58, "radius": 0.3, "drop": -0.18, "taper": 0.45}, "torso_taper": 1.06, "face": "pup"},
    "bandit_coon": {"snout": {"length": 0.45, "radius": 0.34, "drop": -0.16, "taper": 0.6}, "tail_taper": 0.82, "face": "pup"},
    "bamboo_bun": {"snout": {"length": 0.3, "radius": 0.4, "drop": -0.2, "taper": 0.85}, "torso_taper": 1.05, "face": "pup"},
    "boing_roo": {"snout": {"length": 0.44, "radius": 0.36, "drop": -0.16, "taper": 0.7}, "torso_taper": 0.85, "face": "pup"},
    "nook_kit": {"snout": {"length": 0.42, "radius": 0.36, "drop": -0.22, "taper": 0.58}, "torso_taper": 0.9, "tail_taper": 0.85, "face": "pup"},
    "spark_dragonet": {"snout": {"length": 0.55, "radius": 0.38, "drop": -0.1, "taper": 0.68}, "torso_taper": 0.9, "tail_taper": 0.45, "face": "pup"},
    "grumble_gob": {"snout": {"length": 0.34, "radius": 0.3, "drop": -0.08, "taper": 0.65}, "torso_taper": 0.84},
    "snow_lump": {"snout": {"length": 0.4, "radius": 0.44, "drop": -0.16, "taper": 0.85}, "torso_taper": 1.15},
    "cloud_sheep": {"torso_taper": 1.06},
    "moss_shell": {"torso_taper": 0.9},
    "moss_scuttler": {"torso_taper": 0.82, "tail_taper": 0.6},
    "waddle_pen": {"torso_taper": 0.8},
    "puddle_duck": {"torso_taper": 0.86, "tail_taper": 0.5},
    "pip_chick": {"torso_taper": 0.84},
    "clover_hop": {"torso_taper": 0.88, "ears_taper": 0.6},
    "lily_hop": {"torso_taper": 1.05},
    "buzz_bee": {"torso_taper": 1.15, "tail_taper": 0.35},
    "dot_beetle": {"torso_taper": 0.75},
    "sprout_scout": {"torso_taper": 0.9},
    "triblob": {"torso_taper": 0.82},
    "pogo_imp": {"torso_taper": 0.88, "tail_taper": 0.4},
    "glimmer_slime": {"torso_taper": 0.78},
    "wisp_ghost": {"torso_taper": 0.72, "tail_taper": 0.35},
    "shroomling": {"torso_taper": 0.95},
    "cactus_kid": {"torso_taper": 0.92},
    "nook_owl": {"torso_taper": 0.94, "ears_taper": 0.5},
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
        shape = SHAPES.get(data.get("id", ""))
        if shape is None:
            print(f"skip: {path.name}")
            continue
        if "snout" in shape:
            data.setdefault("head", {})["snout"] = shape["snout"]
        if "face" in shape:
            data.setdefault("head", {})["face"] = shape["face"]
        if "torso_taper" in shape:
            data.setdefault("torso", {})["taper"] = shape["torso_taper"]
        if "ears_taper" in shape and "ears" in data:
            data["ears"]["taper"] = shape["ears_taper"]
        if "tail_taper" in shape and "tail" in data:
            data["tail"]["taper"] = shape["tail_taper"]
        path.write_text(dump_compact(data), encoding="utf-8")
        stamped += 1
    print(f"stamped shapes on {stamped} creatures")


if __name__ == "__main__":
    main()

"""Silhouette-variance pass: chunky, sleek, or leggy — never same-y.

Multiplies core dimensions per creature so the cast stops sharing one
generic SDF body: ball-bodied chunks (bear, pig, penguin, slime, yeti),
sleek prowlers (cat, fox), delicate leggy grazers (fawn, pony), and
big-headed babies (mouse, chick, pup). Stance widens with girth so
nobody tips over.

Run:  python tools/apply_chunky_pass.py
"""
import json
from pathlib import Path

CREATURE_DIR = Path(__file__).resolve().parent.parent / "data" / "creatures"

# id -> (torso_radius x, leg_length x, head_radius x, stance x)
TUNING = {
    "bramble_bear": (1.28, 0.78, 1.06, 1.18),
    "pebble_phant": (1.22, 0.85, 1.05, 1.15),
    "puddle_pig": (1.24, 0.72, 1.0, 1.15),
    "cloud_sheep": (1.2, 0.85, 0.95, 1.12),
    "patch_cow": (1.15, 0.85, 1.0, 1.1),
    "moss_shell": (1.18, 0.8, 1.0, 1.1),
    "waddle_pen": (1.18, 0.7, 1.05, 1.1),
    "lily_hop": (1.18, 1.0, 1.05, 1.12),
    "glimmer_slime": (1.28, 1.0, 1.1, 1.0),
    "snow_lump": (1.26, 0.82, 1.05, 1.16),
    "triblob": (1.18, 0.85, 1.08, 1.1),
    "grumble_gob": (1.12, 0.85, 1.1, 1.08),
    "meadow_pup": (1.12, 0.85, 1.18, 1.08),
    "bamboo_bun": (1.18, 0.82, 1.1, 1.1),
    "boing_roo": (1.08, 1.0, 1.05, 1.05),
    "clover_hop": (1.1, 1.0, 1.12, 1.06),
    "buzz_bee": (1.15, 1.0, 1.1, 1.0),
    "dot_beetle": (1.15, 0.9, 1.05, 1.08),
    "moss_scuttler": (1.1, 0.95, 1.08, 1.05),
    "shroomling": (1.08, 0.9, 1.15, 1.05),
    "cactus_kid": (1.1, 0.88, 1.08, 1.06),
    "pogo_imp": (1.08, 1.0, 1.12, 1.0),
    "wisp_ghost": (1.12, 1.0, 1.1, 1.0),
    "spark_dragonet": (1.1, 0.95, 1.08, 1.05),
    "puddle_duck": (1.1, 0.85, 1.12, 1.05),
    "pip_chick": (1.05, 0.8, 1.2, 1.0),
    "thimble_mouse": (0.95, 0.85, 1.25, 1.0),
    "ember_cat": (0.88, 1.12, 1.02, 0.95),
    "dusk_fox": (0.92, 1.1, 1.0, 0.98),
    "dawn_fawn": (0.88, 1.28, 1.0, 0.95),
    "breeze_pony": (0.95, 1.18, 0.98, 1.0),
    "bandit_coon": (1.08, 0.9, 1.05, 1.05),
    "bristle_hog": (1.15, 0.85, 1.02, 1.08),
    "sprout_scout": (1.05, 0.9, 1.1, 1.02),
    "nook_kit": (1.05, 0.95, 1.05, 1.0),
    "nook_owl": (1.08, 0.9, 1.08, 1.05),
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


def scale(section: dict, key: str, factor: float) -> None:
    if key in section:
        section[key] = round(section[key] * factor, 4)


def main() -> None:
    stamped = 0
    for path in sorted(CREATURE_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        tuning = TUNING.get(data.get("id", ""))
        if tuning is None:
            print(f"skip: {path.name}")
            continue
        torso_factor, leg_factor, head_factor, stance_factor = tuning
        scale(data.get("torso", {}), "radius", torso_factor)
        scale(data.get("torso", {}), "height", leg_factor)
        legs = data.get("legs", {})
        scale(legs, "length", leg_factor)
        scale(legs, "stance", stance_factor)
        scale(legs, "radius", (torso_factor + 1.0) * 0.5)
        scale(legs, "foot_radius", (torso_factor + 1.0) * 0.5)
        scale(data.get("head", {}), "radius", head_factor)
        path.write_text(dump_compact(data), encoding="utf-8")
        stamped += 1
    print(f"stamped chunky variance on {stamped} creatures")


if __name__ == "__main__":
    main()

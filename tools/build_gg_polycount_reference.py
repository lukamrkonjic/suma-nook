"""Condense the measured Garden Galaxy library into per-category budgets.

Reads the raw fingerprint of the GG GLB export (produced by
`measure_style_fingerprint.py --directory ...`) and writes the small,
checked-in table that tools/asset_brief_app.py uses to recommend a polycount.

The point is that the recommendation is arithmetic over measured reference
assets rather than a number a model made up. Run:

  python tools/build_gg_polycount_reference.py \
    --fingerprint artifacts/gg_fingerprint.json
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = REPOSITORY_ROOT / "data" / "gg_polycount_reference.json"

# Ordered because the first match wins: a "MushroomTable" is furniture only if
# the mushroom pattern does not claim it first, so put the specific ones early.
CATEGORIES: list[tuple[str, str]] = [
    ("mushroom", r"mushroom|shroom|fungi|toadstool"),
    ("tree_plant", r"tree|plant|bush|leaf|flower|fern|palm|cactus|grass|shrub|vine|moss|lily|tulip|rose|sprout|sapling|berry|daisy|nettle|sunflower|hydrangea"),
    ("furniture", r"table|desk|bench|chair|stool|shelf|cabinet|counter|seat"),
    ("container", r"box|crate|barrel|basket|pot|bucket|jar|vase|bin"),
    ("rock_stone", r"rock|stone|pebble|boulder|cliff|gravel"),
    ("building", r"house|roof|wall|door|window|hut|shed|tower|bridge|fence"),
    ("animal", r"bird|duck|frog|cat|dog|fish|bee|bug|snail|deer|fox|bear|sheep|cow"),
    ("decor_small", r"lamp|lantern|candle|sign|statue|bell|clock|book|cup|mug|bottle|coin"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fingerprint", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(int(len(ordered) * fraction), len(ordered) - 1)]


def summarise(entries: list[dict]) -> dict:
    triangles = [entry["triangles"] for entry in entries]
    densities = [entry["triangles"] / entry["surface_area"] for entry in entries]
    return {
        "sample_size": len(entries),
        "triangles": {
            "p25": round(percentile(triangles, 0.25)),
            "median": round(percentile(triangles, 0.5)),
            "p75": round(percentile(triangles, 0.75)),
            "p90": round(percentile(triangles, 0.9)),
            "max": round(max(triangles)),
        },
        "triangles_per_square_metre": {
            "p25": round(percentile(densities, 0.25)),
            "median": round(percentile(densities, 0.5)),
            "p75": round(percentile(densities, 0.75)),
        },
    }


def main() -> None:
    arguments = parse_args()
    raw = json.loads(arguments.fingerprint.read_text(encoding="utf-8"))

    usable = []
    for name, entry in raw.items():
        if not entry.get("triangles") or not entry.get("surface_area"):
            continue
        usable.append(
            {
                "name": re.sub(r"__sharedassets0__\d+", "", name),
                "triangles": entry["triangles"],
                "surface_area": entry["surface_area"],
            }
        )

    categories: dict[str, dict] = {}
    for label, pattern in CATEGORIES:
        matched = [
            item for item in usable if re.search(pattern, item["name"], re.IGNORECASE)
        ]
        if len(matched) >= 3:
            categories[label] = summarise(matched)
            categories[label]["examples"] = [
                {"name": item["name"], "triangles": item["triangles"]}
                for item in sorted(matched, key=lambda item: item["triangles"])[:6]
            ]

    payload = {
        "_comment": (
            "Measured from Garden Galaxy's shipped GLB export. Garden Galaxy "
            "models are modular -- a table is a separate top and legs mesh -- "
            "so a finished multi-part object is roughly the sum of two or "
            "three entries here. Regenerate with "
            "tools/build_gg_polycount_reference.py."
        ),
        "source_assets": len(usable),
        "overall": summarise(usable),
        "categories": categories,
    }
    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    arguments.out.write_text(json.dumps(payload, indent="\t") + "\n", encoding="utf-8")
    print(f"wrote {arguments.out} from {len(usable)} assets")


if __name__ == "__main__":
    main()

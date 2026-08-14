"""Rebuild prop_gift_wardrobe.glb from the two authored source models.

    python tools/rebuild_gift_wardrobe.py \
        --closed-source ~/Desktop/wardrobe.glb \
        --open-source   ~/Desktop/wardrobe-open.glb

The asset is not a straight import: it is one glb carrying both wardrobe states,
with the open state's doors split onto their own nodes so the game can swing
them. That takes four Blender passes, and the order and the arguments matter
enough that reconstructing them by hand went wrong repeatedly. This records the
recipe so the asset can be rebuilt from the sources at any time.

Order, and why:

1. Split the doors out of the OPEN model. It has to be the open one -- the
   detector keys on door panels protruding forward, which shut doors do not.
2. Ground each state separately, AFTER the split. The splitter re-parents with
   an identity parent inverse, which drops any grounding offset the source's
   parent empty was carrying, so grounding first silently sinks the open state.
3. Merge into StateClosed / StateOpen under one root, hierarchies untouched.
4. Recolour onto Suma's palette LAST, so both states cluster together and land
   on the same slots -- otherwise swapping between them changes colour.

Shading is never altered. The sources author no glTF NORMAL attribute, which is
what keeps them welded and lets the renderer decide the shading; every pass
preserves that. See tools/glb_export.py.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

BLENDER = Path(
    r"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
)
TOOLS = Path(__file__).resolve().parent
DEFAULT_OUTPUT = (
    TOOLS.parent / "assets" / "3d" / "reworked" / "prop_gift_wardrobe.glb"
)

# Two paints, matching the source: the body and doors in the lighter, warmer
# tone, the top slab, base and handles in the browner one. Measured from
# wardrobe.glb -- body #C9954A, top #9C734B.
SLOT_COUNT = 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--closed-source", required=True, type=Path)
    parser.add_argument("--open-source", required=True, type=Path)
    parser.add_argument("--output", default=DEFAULT_OUTPUT, type=Path)
    # Palette entries for the clusters, largest first. Left automatic by
    # default; name them to pick the colours by hand.
    parser.add_argument("--slot", action="append", default=[])
    return parser.parse_args()


def run(script: str, *arguments: str) -> None:
    command = [
        str(BLENDER),
        "--background",
        "--factory-startup",
        "--python",
        str(TOOLS / script),
        "--",
        *arguments,
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit("%s failed" % script)
    for line in result.stdout.splitlines():
        if line.startswith(("GROUNDED", "MERGED", "CLOSED_YAW", "  cluster", "PALETTE ")):
            print(line)


def main() -> None:
    arguments = parse_args()
    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory)
        run(
            "build_wardrobe_hinged.py",
            "--source", str(arguments.open_source),
            "--output", str(stage / "hinged_raw.glb"),
        )
        run(
            "ground_asset.py",
            "--source", str(arguments.closed_source),
            "--output", str(stage / "closed.glb"),
        )
        run(
            "ground_asset.py",
            "--source", str(stage / "hinged_raw.glb"),
            "--output", str(stage / "hinged.glb"),
        )
        run(
            "merge_wardrobe_states.py",
            "--closed", str(stage / "closed.glb"),
            "--open", str(stage / "hinged.glb"),
            "--output", str(stage / "merged.glb"),
        )
        slots: list[str] = []
        for name in arguments.slot:
            slots += ["--slot", name]
        run(
            "palette_map_asset.py",
            "--source", str(stage / "merged.glb"),
            "--output", str(arguments.output),
            "--profile", "wood_prop",
            "--max-slots", str(SLOT_COUNT),
            *slots,
        )
    print("WARDROBE_OUT=%s" % arguments.output)


if __name__ == "__main__":
    main()

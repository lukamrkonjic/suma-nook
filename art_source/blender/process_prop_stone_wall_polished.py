"""Rebuild the game-ready normals-only stone-wall placeable."""

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from normals_only_placeable import process

ROOT = SCRIPT_DIR.parents[1]

process(
    source=ROOT / "art_source" / "imported" / "prop_stone_wall_polished" / "stone-wall_source.glb",
    output=ROOT / "assets" / "3d" / "reworked" / "prop_stone_wall_polished.glb",
    expected_source_sha256="2bf9a664c2b89b155f092434abdc8bc4ce22c9c8ac5e61fcbc86923a934c38ab",
    object_name="StoneWallPolished",
)

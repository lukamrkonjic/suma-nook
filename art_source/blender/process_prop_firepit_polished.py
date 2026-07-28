"""Rebuild the game-ready normals-only firepit placeable."""

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from normals_only_placeable import process

ROOT = SCRIPT_DIR.parents[1]

process(
    source=ROOT / "art_source" / "imported" / "prop_firepit_polished" / "firepit_source.glb",
    output=ROOT / "assets" / "3d" / "reworked" / "prop_firepit_polished.glb",
    expected_source_sha256="119abd694fa6a6579f9f66620e54bafb52c403aef79bd91c26f626be7b407fe7",
    object_name="FirepitPolished",
)

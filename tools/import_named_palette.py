#!/usr/bin/env python3
"""Import exact semantic source colors and screen targets into the palette.

The input JSON objects must contain every canonical semantic color plus every
alias. Alias values must equal their canonical target. The canonical resource
stores one entry per real semantic color; aliases remain in the separate
``aliases`` dictionary and resolve through ``PaletteDefinition``.

Usage:
    python tools/import_named_palette.py SOURCE.json SCREEN_TARGETS.json
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

from palette_io import CANONICAL_PALETTE, _block_span


ROOT = Path(__file__).resolve().parents[1]
_KEY = re.compile(r'^"([^"]+)"\s*:', re.MULTILINE)
_ALIAS = re.compile(r'^"([^"]+)"\s*:\s*"([^"]+)"', re.MULTILINE)


def _block(text: str, name: str) -> str:
    start, end = _block_span(text, name)
    return text[start:end]


def _load_palette(path: Path, label: str) -> dict[str, tuple[float, ...]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{label} must be a JSON object")
    result: dict[str, tuple[float, ...]] = {}
    for key, value in payload.items():
        if not isinstance(key, str) or not key:
            raise ValueError(f"{label} contains an invalid color key")
        if not isinstance(value, list) or len(value) != 4:
            raise ValueError(f"{label}.{key} must be an RGBA array")
        color = tuple(float(component) for component in value)
        if not all(math.isfinite(component) for component in color):
            raise ValueError(f"{label}.{key} contains a non-finite component")
        if not all(0.0 <= component <= 1.0 for component in color):
            raise ValueError(f"{label}.{key} must stay within 0.0-1.0")
        result[key] = color
    return result


def _format_float(value: float) -> str:
    rendered = f"{value:.9f}".rstrip("0").rstrip(".")
    return rendered if "." in rendered else rendered + ".0"


def _color_block(values: dict[str, tuple[float, ...]], order: list[str]) -> str:
    lines = []
    for key in order:
        components = ", ".join(_format_float(value) for value in values[key])
        lines.append(f'"{key}": Color({components})')
    return "\n" + ",\n".join(lines) + "\n"


def _replace_block(text: str, name: str, replacement: str) -> str:
    start, end = _block_span(text, name)
    return text[:start] + replacement + text[end:]


def import_palette(source_path: Path, target_path: Path, palette_path: Path) -> None:
    text = palette_path.read_text(encoding="utf-8")
    canonical_order = _KEY.findall(_block(text, "colors"))
    aliases = dict(_ALIAS.findall(_block(text, "aliases")))
    if not canonical_order:
        raise ValueError("Canonical palette has no semantic colors")

    source = _load_palette(source_path, "source palette")
    targets = _load_palette(target_path, "screen targets")
    expected = set(canonical_order) | set(aliases)
    for label, values in (("source palette", source), ("screen targets", targets)):
        missing = sorted(expected - set(values))
        extra = sorted(set(values) - expected)
        if missing or extra:
            details = []
            if missing:
                details.append("missing " + ", ".join(missing))
            if extra:
                details.append("extra " + ", ".join(extra))
            raise ValueError(f"{label} key mismatch: {'; '.join(details)}")
        for alias, canonical in aliases.items():
            if values[alias] != values[canonical]:
                raise ValueError(
                    f"{label} alias '{alias}' differs from '{canonical}'"
                )

    canonical_source = {key: source[key] for key in canonical_order}
    canonical_targets = {key: targets[key] for key in canonical_order}
    updated = _replace_block(
        text, "colors", _color_block(canonical_source, canonical_order)
    )
    updated = _replace_block(
        updated,
        "render_targets",
        _color_block(canonical_targets, canonical_order),
    )
    palette_path.write_text(updated, encoding="utf-8")
    print(
        f"Imported {len(canonical_order)} canonical colors and screen targets "
        f"plus {len(aliases)} resolving aliases into {palette_path}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="game-ready RGBA JSON")
    parser.add_argument("screen_targets", type=Path, help="screen-space RGBA JSON")
    parser.add_argument(
        "--palette",
        type=Path,
        default=ROOT / CANONICAL_PALETTE,
        help="canonical Godot palette resource",
    )
    args = parser.parse_args()
    import_palette(args.source, args.screen_targets, args.palette)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

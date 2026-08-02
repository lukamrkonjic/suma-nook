"""Rename primitive palette swatches to role-neutral hue/tonal references.

The operation is deterministic and updates both dictionary keys and every
reference inside the canonical palette. Run without ``--apply`` to preview.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from palette_io import (
    CANONICAL_PALETTE,
    _block_span,
    build_reference_token_names,
    read_color_block,
)


def _number(value: float) -> str:
    rendered = f"{value:.6f}".rstrip("0").rstrip(".")
    return rendered if "." in rendered else rendered + ".0"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("palette", nargs="?", type=Path, default=CANONICAL_PALETTE)
    args = parser.parse_args()

    palette = args.palette
    swatches = read_color_block(palette, "swatches")
    replacements = build_reference_token_names(swatches)
    source = palette.read_text(encoding="utf-8")
    migrated = source
    for old_id, new_id in replacements.items():
        migrated = migrated.replace(f'"{old_id}"', f'"{new_id}"')
    renamed_swatches = {
        replacements[old_id]: color for old_id, color in swatches.items()
    }
    start, end = _block_span(migrated, "swatches")
    ordered_block = "\n" + ",\n".join(
        f'"{reference_id}": Color('
        + ", ".join(_number(component) for component in color)
        + ")"
        for reference_id, color in sorted(renamed_swatches.items())
    ) + "\n"
    migrated = migrated[:start] + ordered_block + migrated[end:]

    changed = sum(old_id != new_id for old_id, new_id in replacements.items())
    print(f"{len(swatches)} reference tokens; {changed} rename(s) required")
    for old_id, new_id in sorted(replacements.items(), key=lambda item: item[1]):
        if old_id != new_id:
            print(f"  {old_id} -> {new_id}")
    if not args.apply:
        print("Preview only; pass --apply to update the canonical palette.")
        return 0
    if migrated == source:
        print("Canonical palette already follows the reference-token scale.")
        return 0
    palette.write_text(migrated, encoding="utf-8")
    print(f"Updated {palette}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Enforce Suma's single-source color design-system contract."""

from __future__ import annotations

import re
import sys
from pathlib import Path

from palette_io import (
    CANONICAL_PALETTE,
    REFERENCE_FAMILIES,
    REFERENCE_TONES,
    _block_span,
    build_reference_token_names,
    read_color_block,
    read_token_specs,
)


ROOT = Path(__file__).resolve().parents[1]
PALETTE = ROOT / CANONICAL_PALETTE
REQUIRED_SECTIONS = (
    "swatches",
    "colors",
    "render_targets",
    "aliases",
    "environment_profiles",
    "world_themes",
    "background_presets",
    "schemes",
    "token_domains",
    "design_rules",
)
IGNORED_RESOURCE_PARTS = {
    "archive",
    "lab",
    "review",
    "tests",
    ".godot",
}
RUNTIME_CODE_ROOTS = ("scripts", "world", "characters")
RUNTIME_RESOURCE_ROOTS = ("assets", "scenes", "world", "characters", "data")
ALLOWED_NUMERIC_COLOR_FILES = {
    # These constructors encode vector math or neutral multipliers, not hues.
    Path("scripts/visuals/void_cloud_controller.gd"),
}


def _relative(path: Path) -> Path:
    return path.relative_to(ROOT)


def _dictionary_text(text: str, name: str) -> str:
    start, end = _block_span(text, name)
    return text[start:end]


def _aliases(text: str) -> dict[str, str]:
    block = _dictionary_text(text, "aliases")
    return dict(re.findall(r'^"([^"]+)"\s*:\s*"([^"]+)"', block, re.MULTILINE))


def _ignored(path: Path) -> bool:
    relative = _relative(path)
    return bool(set(relative.parts) & IGNORED_RESOURCE_PARTS) or "review" in path.stem


def validate() -> list[str]:
    errors: list[str] = []
    if not PALETTE.exists():
        return [f"Missing canonical palette: {PALETTE}"]

    palette_assets = sorted(
        path for path in (ROOT / "assets/palettes").iterdir() if path.is_file()
    )
    if palette_assets != [PALETTE]:
        listed = ", ".join(str(_relative(path)) for path in palette_assets)
        errors.append(f"assets/palettes must contain only the canonical file; found {listed}")

    text = PALETTE.read_text(encoding="utf-8")
    for section in REQUIRED_SECTIONS:
        if f"{section} = {{" not in text:
            errors.append(f"Canonical palette is missing '{section}'")

    swatches = read_color_block(PALETTE, "swatches")
    color_references = read_token_specs(PALETTE, "colors")
    color_literals = read_color_block(PALETTE, "colors")
    colors = set(color_references) | set(color_literals)
    duplicate_colors = set(color_references) & set(color_literals)
    if duplicate_colors:
        errors.append(
            "Semantic colors have duplicate literal/reference definitions: "
            + ", ".join(sorted(duplicate_colors))
        )
    render_targets = read_color_block(PALETTE, "render_targets")
    if len(colors) < 200:
        errors.append(
            f"Expected comprehensive semantic coverage; found only {len(colors)} tokens"
        )
    if len(swatches) > 128:
        errors.append(f"Primitive palette exceeds the 128-swatch cap: {len(swatches)}")
    if not swatches:
        errors.append("Primitive palette is empty")
    expected_names = build_reference_token_names(swatches)
    for reference_id, expected_id in expected_names.items():
        if reference_id != expected_id:
            errors.append(
                f"Reference token '{reference_id}' must be named '{expected_id}'"
            )
    for token, spec in color_references.items():
        swatch_id = str(spec["swatch"])
        if swatch_id not in swatches:
            errors.append(f"Token '{token}' references missing swatch '{swatch_id}'")
    for token, value in color_literals.items():
        if len(value) != 4:
            errors.append(f"Token '{token}' must have exactly four RGBA components")
    if not render_targets:
        errors.append("render_targets is empty")
    missing_targets = colors - set(render_targets)
    extra_targets = set(render_targets) - colors
    if missing_targets:
        errors.append(
            "Semantic colors missing render targets: "
            + ", ".join(sorted(missing_targets))
        )
    if extra_targets:
        errors.append(
            "Render targets without semantic colors: "
            + ", ".join(sorted(extra_targets))
        )

    for section in ("environment_profiles", "world_themes", "background_presets"):
        block = _dictionary_text(text, section)
        for reference_id in re.findall(r':\s*"([^"]+)"', block):
            if reference_id not in swatches:
                errors.append(
                    f"{section} references missing swatch '{reference_id}'"
                )
    character_block = _dictionary_text(text, "character_swatch_groups")
    reference_pattern = re.compile(
        rf'"((?:{"|".join(REFERENCE_FAMILIES)})_'
        rf'(?:{"|".join(f"{tone:03d}" for tone in REFERENCE_TONES)}))"'
    )
    for reference_id in reference_pattern.findall(character_block):
        if reference_id not in swatches:
            errors.append(
                "character_swatch_groups references missing swatch "
                f"'{reference_id}'"
            )

    aliases = _aliases(text)
    known_tokens = colors | set(aliases)
    for alias, target in aliases.items():
        if target not in colors:
            errors.append(f"Alias '{alias}' targets missing token '{target}'")

    environment_block = _dictionary_text(text, "environment_profiles")
    for profile_path in (ROOT / "assets/visual_profiles").glob("*.tres"):
        profile_source = profile_path.read_text(encoding="utf-8")
        match = re.search(r'^profile_id\s*=\s*"([^"]+)"', profile_source, re.MULTILINE)
        if match and f'"{match.group(1)}": {{' not in environment_block:
            errors.append(
                f"{_relative(profile_path)} has no environment_profiles entry"
            )

    runtime_scripts = (
        path
        for directory in RUNTIME_CODE_ROOTS
        for path in (ROOT / directory).rglob("*.gd")
    )
    for path in runtime_scripts:
        if _ignored(path) or path == ROOT / "scripts/resources/palette_definition.gd":
            continue
        source = path.read_text(encoding="utf-8")
        for token in re.findall(r'\.color\(\s*"([^"]+)"', source):
            if token not in known_tokens:
                errors.append(f"{_relative(path)} references unknown color token '{token}'")
        if _relative(path) not in ALLOWED_NUMERIC_COLOR_FILES:
            for match in re.finditer(r'Color\(\s*(?:["\']|[0-9])', source):
                line = source.count("\n", 0, match.start()) + 1
                errors.append(
                    f"{_relative(path)}:{line} authors a numeric/string Color outside the palette"
                )

    for path in (ROOT / "data").rglob("*.json"):
        if _ignored(path):
            continue
        source = path.read_text(encoding="utf-8")
        if re.search(r'"color"\s*:\s*"[0-9a-fA-F#]{6,9}"', source):
            errors.append(f"{_relative(path)} ships a raw color; use color_token")
        for token in re.findall(r'"color_token"\s*:\s*"([^"]+)"', source):
            if token not in known_tokens:
                errors.append(f"{_relative(path)} references unknown color token '{token}'")

    for suffix in ("*.tres", "*.tscn"):
        runtime_resources = (
            path
            for directory in RUNTIME_RESOURCE_ROOTS
            for path in (ROOT / directory).rglob(suffix)
        )
        for path in runtime_resources:
            if path == PALETTE or _ignored(path):
                continue
            source = path.read_text(encoding="utf-8", errors="ignore")
            if "Color(" in source:
                errors.append(f"{_relative(path)} serializes a color outside the palette")

    non_neutral_uniform = re.compile(
        r":\s*source_color\s*=\s*vec[34]\((?!\s*1(?:\.0)?\s*\))",
        re.MULTILINE,
    )
    for path in list((ROOT / "assets").rglob("*.gdshader")) + list(
        (ROOT / "world").rglob("*.gdshader")
    ):
        source = path.read_text(encoding="utf-8")
        if non_neutral_uniform.search(source):
            errors.append(
                f"{_relative(path)} has a non-neutral source_color default; bind a token at runtime"
            )

    return errors


def main() -> int:
    errors = validate()
    if errors:
        print("Color design-system validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    count = len(
        set(read_token_specs(PALETTE, "colors"))
        | set(read_color_block(PALETTE, "colors"))
    )
    swatch_count = len(read_color_block(PALETTE, "swatches"))
    target_count = len(read_color_block(PALETTE, "render_targets"))
    print(
        "Color design-system validation passed: "
        f"{count} semantic tokens, {swatch_count}/128 reference tokens, "
        f"{target_count} render targets, one canonical file."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

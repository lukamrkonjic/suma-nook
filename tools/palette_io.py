"""Read and update Suma's canonical Godot color design-system resource."""

from __future__ import annotations

import re
from collections import defaultdict
from colorsys import rgb_to_hsv
from pathlib import Path
from typing import Hashable, Mapping


CANONICAL_PALETTE = Path("assets/palettes/gg_material_palette.tres")
REFERENCE_FAMILIES = (
    "blue",
    "brown",
    "green",
    "neutral",
    "olive",
    "orange",
    "pink",
    "red",
    "sand",
    "teal",
    "violet",
    "yellow",
)
REFERENCE_TONES = tuple(range(50, 951, 50))
_ENTRY = re.compile(r'(?m)^"([^"]+)"\s*:\s*Color\(([^)]*)\)(,?)$')
_TOKEN_STRING = re.compile(r'(?m)^"([^"]+)"\s*:\s*"([^"]+)"(,?)$')
_TOKEN_ALPHA = re.compile(
    r'(?m)^"([^"]+)"\s*:\s*\{"swatch":\s*"([^"]+)",\s*'
    r'"alpha":\s*([0-9.]+)\}(,?)$'
)


def _block_span(text: str, name: str) -> tuple[int, int]:
    marker = f"{name} = {{"
    start = text.index(marker) + len(marker)
    depth = 1
    index = start
    while index < len(text) and depth:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    if depth:
        raise ValueError(f"Unclosed {name} dictionary")
    return start, index - 1


def read_color_block(path: Path, name: str) -> dict[str, tuple[float, ...]]:
    text = path.read_text(encoding="utf-8")
    start, end = _block_span(text, name)
    result: dict[str, tuple[float, ...]] = {}
    for match in _ENTRY.finditer(text[start:end]):
        result[match.group(1)] = tuple(
            float(component.strip()) for component in match.group(2).split(",")
        )
    return result


def color_to_hex(color: tuple[float, ...]) -> str:
    return "#%02X%02X%02X" % tuple(
        round(max(0.0, min(1.0, component)) * 255.0)
        for component in color[:3]
    )


def read_color_hexes(path: Path, name: str) -> dict[str, str]:
    return {key: color_to_hex(value) for key, value in read_color_block(path, name).items()}


def read_token_specs(path: Path, name: str = "colors") -> dict[str, dict[str, object]]:
    """Read semantic token -> primitive swatch mappings."""

    text = path.read_text(encoding="utf-8")
    start, end = _block_span(text, name)
    block = text[start:end]
    result: dict[str, dict[str, object]] = {}
    for match in _TOKEN_STRING.finditer(block):
        result[match.group(1)] = {"swatch": match.group(2), "alpha": 1.0}
    for match in _TOKEN_ALPHA.finditer(block):
        result[match.group(1)] = {
            "swatch": match.group(2),
            "alpha": float(match.group(3)),
        }
    return result


def build_reference_token_names(
    colors: Mapping[Hashable, tuple[float, ...]],
) -> dict[Hashable, str]:
    """Build role-neutral ``family_tone`` names from primitive RGB values.

    Tone 050 is the lightest member of a hue family and 950 is its darkest.
    Ranking within a family avoids falsely implying that two different hue
    families share an identical measured luminance curve.
    """

    groups: dict[str, list[tuple[Hashable, tuple[float, ...]]]] = defaultdict(list)
    for key, color in colors.items():
        groups[_reference_family(color)].append((key, color))

    result: dict[Hashable, str] = {}
    for family, members in groups.items():
        if len(members) > len(REFERENCE_TONES):
            raise ValueError(
                f"Reference family '{family}' needs {len(members)} tones; "
                f"only {len(REFERENCE_TONES)} are available"
            )
        members.sort(key=lambda item: (-_relative_luminance(item[1]), str(item[0])))
        if len(members) == 1:
            tone_indexes = [len(REFERENCE_TONES) // 2]
        else:
            tone_indexes = [
                round(index * (len(REFERENCE_TONES) - 1) / (len(members) - 1))
                for index in range(len(members))
            ]
        for (key, _color), tone_index in zip(members, tone_indexes):
            result[key] = f"{family}_{REFERENCE_TONES[tone_index]:03d}"
    if len(result) != len(set(result.values())):
        raise ValueError("Reference token generation produced duplicate names")
    return result


def _reference_family(color: tuple[float, ...]) -> str:
    red, green, blue = color[:3]
    peak = max(red, green, blue, 1e-9)
    if peak > 1.0:
        red, green, blue = red / peak, green / peak, blue / peak
    red, green, blue = (
        max(0.0, min(1.0, component)) for component in (red, green, blue)
    )
    hue, saturation, value = rgb_to_hsv(red, green, blue)
    degrees = hue * 360.0
    if saturation < 0.11:
        return "neutral"
    if degrees < 15.0 or degrees >= 345.0:
        return "red"
    if degrees < 38.0:
        if value < 0.58:
            return "brown"
        if saturation < 0.43:
            return "sand"
        return "orange"
    if degrees < 68.0:
        if value < 0.55:
            return "olive"
        if saturation < 0.38:
            return "sand"
        return "yellow"
    if degrees < 85.0:
        return "olive"
    if degrees < 165.0:
        return "green"
    if degrees < 195.0:
        return "teal"
    if degrees < 250.0:
        return "blue"
    if degrees < 285.0:
        return "violet"
    if degrees < 345.0:
        return "pink"
    return "red"


def _relative_luminance(color: tuple[float, ...]) -> float:
    def linear(component: float) -> float:
        component = max(0.0, min(1.0, component))
        if component <= 0.04045:
            return component / 12.92
        return ((component + 0.055) / 1.055) ** 2.4

    red, green, blue = (linear(component) for component in color[:3])
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def update_color_block(
    path: Path,
    name: str,
    replacements: dict[str, tuple[float, float, float, float]],
) -> None:
    """Update named entries without rewriting unrelated design-system data."""

    text = path.read_text(encoding="utf-8")
    start, end = _block_span(text, name)
    block = text[start:end]

    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in replacements:
            return match.group(0)
        color = replacements[key]
        values = ", ".join(_format_float(component) for component in color)
        return f'"{key}": Color({values}){match.group(3)}'

    existing = {match.group(1) for match in _ENTRY.finditer(block)}
    updated = _ENTRY.sub(replace, block)
    missing = sorted(set(replacements) - existing)
    if missing:
        raise KeyError(f"Unknown {name} tokens: {', '.join(missing)}")
    path.write_text(text[:start] + updated + text[end:], encoding="utf-8")


def _format_float(value: float) -> str:
    rendered = f"{value:.4f}".rstrip("0").rstrip(".")
    return rendered if "." in rendered else rendered + ".0"

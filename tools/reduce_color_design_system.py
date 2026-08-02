"""Collapse authored colors into a bounded primitive swatch palette.

The game keeps all semantic token names. This tool clusters their RGB values,
stores a small set of perceptual medoids in ``swatches``, and rewrites every
runtime color role to reference one of those primitives. Alpha remains a token
property, so translucent UI states do not consume extra hue swatches.

Run without ``--apply`` for a report. The migration is intentionally one-way;
after conversion, ongoing enforcement belongs to
``validate_color_design_system.py``.
"""

from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass
from pathlib import Path

from palette_io import CANONICAL_PALETTE, _block_span, build_reference_token_names


DEFAULT_TARGET = 120
HARD_LIMIT = 128
COLOR_SECTIONS = (
    "colors",
    "environment_profiles",
    "world_themes",
    "background_presets",
)
CHARACTER_ARRAYS = {
    "skin": "skin_tones",
    "hair": "hair_colors",
    "outfit": "outfit_colors",
}
_COLOR_LINE = re.compile(
    r'^(?P<indent>\s*)"(?P<key>[^"]+)"\s*:\s*Color\((?P<value>[^)]*)\)'
    r'(?P<comma>,?)(?P<newline>\r?\n?)$'
)
_OPEN_LINE = re.compile(r'^\s*"([^"]+)"\s*:\s*\{\s*$')


@dataclass(frozen=True)
class Entry:
    section: str
    path: tuple[str, ...]
    rgba: tuple[float, float, float, float]
    weight: float
    protected: bool

    @property
    def rgb(self) -> tuple[float, float, float]:
        return tuple(round(value, 6) for value in self.rgba[:3])

    @property
    def label(self) -> str:
        return f"{self.section}:{'/'.join(self.path)}"

    @property
    def id_hint(self) -> str:
        if self.section == "colors":
            return self.path[-1]
        if self.section == "character":
            return f"character_{self.path[0]}_{int(self.path[1]) + 1:02d}"
        prefix = {
            "environment_profiles": "environment",
            "world_themes": "theme",
            "background_presets": "background",
        }[self.section]
        return f"{prefix}_{'_'.join(self.path)}"


@dataclass
class Point:
    rgb: tuple[float, float, float]
    lab: tuple[float, float, float]
    entries: list[Entry]
    weight: float
    protected: bool
    hdr: bool


def _parse_color(value: str) -> tuple[float, float, float, float]:
    parts = [float(component.strip()) for component in value.split(",")]
    parts.extend([1.0] * (4 - len(parts)))
    return tuple(parts[:4])


def _entry_weight(section: str, path: tuple[str, ...]) -> float:
    if section == "character":
        return 3.0
    if section == "world_themes":
        return 2.5
    if section == "environment_profiles":
        return 2.2
    if section == "background_presets":
        return 2.0
    token = path[-1]
    if token.startswith("ui_"):
        return 1.6
    if token.startswith(("cloud_", "environment_")):
        return 2.2
    if token.startswith("debug_"):
        return 3.0
    return 1.0


def _entry_is_protected(
    section: str,
    path: tuple[str, ...],
    rgba: tuple[float, float, float, float],
) -> bool:
    if max(rgba[:3]) > 1.0 or section == "character":
        return True
    if section != "colors":
        return False
    token = path[-1]
    return token.startswith(
        (
            "skin_",
            "hair_",
            "outfit_",
            "character_",
            "pigeon_",
            "debug_",
        )
    ) or token in {
        "neutral_white",
        "warm_near_black",
        "ui_good",
        "ui_bad",
        "ui_info",
        "ui_health",
    }


def _entries_from_block(text: str, section: str) -> list[Entry]:
    start, end = _block_span(text, section)
    stack: list[str] = []
    result: list[Entry] = []
    for line in text[start:end].splitlines():
        stripped = line.strip()
        opened = _OPEN_LINE.match(stripped)
        if opened:
            stack.append(opened.group(1))
            continue
        if stripped.startswith("}"):
            if stack:
                stack.pop()
            continue
        color = _COLOR_LINE.match(line)
        if not color:
            continue
        path = tuple(stack + [color.group("key")])
        rgba = _parse_color(color.group("value"))
        result.append(
            Entry(
                section,
                path,
                rgba,
                _entry_weight(section, path),
                _entry_is_protected(section, path, rgba),
            )
        )
    return result


def _character_entries(text: str) -> list[Entry]:
    result: list[Entry] = []
    for group, property_name in CHARACTER_ARRAYS.items():
        match = re.search(
            rf"{property_name}\s*=\s*PackedColorArray\(([^)]*)\)", text
        )
        if not match:
            raise ValueError(f"Missing {property_name}")
        values = [float(value.strip()) for value in match.group(1).split(",")]
        for index in range(0, len(values), 4):
            rgba = tuple(values[index : index + 4])
            path = (group, str(index // 4))
            result.append(Entry("character", path, rgba, 3.0, True))
    return result


def _srgb_to_lab(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    clipped = [max(0.0, min(1.0, value)) for value in rgb]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in clipped
    ]
    x = linear[0] * 0.4124564 + linear[1] * 0.3575761 + linear[2] * 0.1804375
    y = linear[0] * 0.2126729 + linear[1] * 0.7151522 + linear[2] * 0.0721750
    z = linear[0] * 0.0193339 + linear[1] * 0.1191920 + linear[2] * 0.9503041

    def pivot(value: float) -> float:
        epsilon = 216.0 / 24389.0
        kappa = 24389.0 / 27.0
        return value ** (1.0 / 3.0) if value > epsilon else (kappa * value + 16.0) / 116.0

    fx = pivot(x / 0.95047)
    fy = pivot(y)
    fz = pivot(z / 1.08883)
    return 116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)


def _distance_squared(first: Point, second: Point) -> float:
    if first.hdr != second.hdr:
        return 1.0e12
    return sum((a - b) ** 2 for a, b in zip(first.lab, second.lab))


def _points(entries: list[Entry]) -> list[Point]:
    grouped: dict[tuple[float, float, float], list[Entry]] = {}
    for entry in entries:
        grouped.setdefault(entry.rgb, []).append(entry)
    return [
        Point(
            rgb,
            _srgb_to_lab(rgb),
            grouped_entries,
            sum(entry.weight for entry in grouped_entries),
            any(entry.protected for entry in grouped_entries),
            max(rgb) > 1.0,
        )
        for rgb, grouped_entries in grouped.items()
    ]


def _cluster(points: list[Point], target: int) -> list[int]:
    centers = [index for index, point in enumerate(points) if point.protected]
    if len(centers) > target:
        raise ValueError(
            f"{len(centers)} protected colors exceed requested {target} swatches"
        )
    nearest = [
        min(_distance_squared(point, points[center]) for center in centers)
        if centers
        else math.inf
        for point in points
    ]
    while len(centers) < target:
        candidates = (
            (nearest[index] * point.weight, index)
            for index, point in enumerate(points)
            if index not in centers
        )
        _, selected = max(candidates)
        centers.append(selected)
        for index, point in enumerate(points):
            nearest[index] = min(
                nearest[index], _distance_squared(point, points[selected])
            )

    protected = set(centers[: sum(point.protected for point in points)])
    for _iteration in range(8):
        assignments = [
            min(
                range(len(centers)),
                key=lambda center_index: _distance_squared(
                    point, points[centers[center_index]]
                ),
            )
            for point in points
        ]
        updated: list[int] = []
        for center_index, center in enumerate(centers):
            if center in protected:
                updated.append(center)
                continue
            members = [
                index
                for index, assignment in enumerate(assignments)
                if assignment == center_index
            ]
            if not members:
                updated.append(center)
                continue
            updated.append(
                min(
                    members,
                    key=lambda candidate: sum(
                        _distance_squared(points[candidate], points[member])
                        * points[member].weight
                        for member in members
                    ),
                )
            )
        if updated == centers:
            break
        centers = updated
    return centers


def _assignments(points: list[Point], centers: list[int]) -> list[int]:
    return [
        min(
            centers,
            key=lambda center: _distance_squared(point, points[center]),
        )
        for point in points
    ]


def _swatch_ids(points: list[Point], centers: list[int]) -> dict[int, str]:
    colors = {center: points[center].rgb for center in centers}
    return build_reference_token_names(colors)


def _format_number(value: float) -> str:
    rendered = f"{value:.6f}".rstrip("0").rstrip(".")
    return rendered if "." in rendered else rendered + ".0"


def _format_spec(swatch_id: str, alpha: float) -> str:
    if math.isclose(alpha, 1.0, abs_tol=0.000001):
        return f'"{swatch_id}"'
    return (
        f'{{"swatch": "{swatch_id}", '
        f'"alpha": {_format_number(alpha)}}}'
    )


def _transform_block(
    text: str,
    section: str,
    entry_swatches: dict[tuple[str, tuple[str, ...]], str],
) -> str:
    start, end = _block_span(text, section)
    stack: list[str] = []
    output: list[str] = []
    for line in text[start:end].splitlines(keepends=True):
        stripped = line.strip()
        opened = _OPEN_LINE.match(stripped)
        if opened:
            stack.append(opened.group(1))
            output.append(line)
            continue
        if stripped.startswith("}"):
            if stack:
                stack.pop()
            output.append(line)
            continue
        color = _COLOR_LINE.match(line)
        if not color:
            output.append(line)
            continue
        path = tuple(stack + [color.group("key")])
        swatch_id = entry_swatches[(section, path)]
        alpha = _parse_color(color.group("value"))[3]
        output.append(
            f'{color.group("indent")}"{color.group("key")}": '
            f'{_format_spec(swatch_id, alpha)}{color.group("comma")}'
            f'{color.group("newline")}'
        )
    return text[:start] + "".join(output) + text[end:]


def _apply_migration(
    path: Path,
    text: str,
    points: list[Point],
    centers: list[int],
    point_assignments: list[int],
    swatch_ids: dict[int, str],
    entries: list[Entry],
) -> None:
    point_index = {point.rgb: index for index, point in enumerate(points)}
    entry_swatches = {
        (entry.section, entry.path): swatch_ids[
            point_assignments[point_index[entry.rgb]]
        ]
        for entry in entries
    }
    migrated = text
    for section in COLOR_SECTIONS:
        migrated = _transform_block(migrated, section, entry_swatches)

    swatch_lines = []
    for center, swatch_id in sorted(
        swatch_ids.items(), key=lambda item: item[1]
    ):
        rgb = points[center].rgb
        swatch_lines.append(
            f'"{swatch_id}": Color('
            + ", ".join(_format_number(value) for value in rgb)
            + ", 1)"
        )
    swatch_block = "swatches = {\n" + ",\n".join(swatch_lines) + "\n}\n"
    migrated = migrated.replace("colors = {", swatch_block + "colors = {", 1)

    group_lines = []
    for group in CHARACTER_ARRAYS:
        group_entries = sorted(
            (entry for entry in entries if entry.section == "character" and entry.path[0] == group),
            key=lambda entry: int(entry.path[1]),
        )
        ids = [
            entry_swatches[(entry.section, entry.path)] for entry in group_entries
        ]
        group_lines.append(
            f'"{group}": [' + ", ".join(f'"{swatch_id}"' for swatch_id in ids) + "]"
        )
    group_block = (
        "character_swatch_groups = {\n"
        + ",\n".join(group_lines)
        + "\n}\n"
    )
    migrated = migrated.replace("active_scheme =", group_block + "active_scheme =", 1)
    for property_name in CHARACTER_ARRAYS.values():
        migrated = re.sub(
            rf"{property_name}\s*=\s*PackedColorArray\([^)]*\)",
            f"{property_name} = PackedColorArray()",
            migrated,
        )
    path.write_text(migrated, encoding="utf-8")


def _report(points: list[Point], centers: list[int], assignments: list[int]) -> None:
    distances = [
        math.sqrt(_distance_squared(point, points[assignment]))
        for point, assignment in zip(points, assignments)
    ]
    ordered = sorted(distances)
    p95 = ordered[min(len(ordered) - 1, round(len(ordered) * 0.95))]
    print(
        f"{len(points)} unique RGB values -> {len(centers)} master swatches; "
        f"mean DeltaE76 {sum(distances) / len(distances):.2f}, "
        f"p95 {p95:.2f}, max {max(distances):.2f}."
    )
    print("Largest perceptual merges:")
    for index in sorted(range(len(points)), key=distances.__getitem__, reverse=True)[:12]:
        source = points[index]
        target = points[assignments[index]]
        print(
            f"  {distances[index]:5.1f}  {source.entries[0].label} "
            f"-> {target.entries[0].label}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--max-swatches", type=int, default=DEFAULT_TARGET)
    parser.add_argument("--palette", type=Path, default=CANONICAL_PALETTE)
    args = parser.parse_args()
    if args.max_swatches > HARD_LIMIT or args.max_swatches < 1:
        parser.error(f"--max-swatches must be between 1 and {HARD_LIMIT}")
    text = args.palette.read_text(encoding="utf-8")
    if "swatches = {" in text:
        raise SystemExit("Palette already uses primitive swatches; migration not applied.")

    entries = [
        entry
        for section in COLOR_SECTIONS
        for entry in _entries_from_block(text, section)
    ]
    entries.extend(_character_entries(text))
    points = _points(entries)
    centers = _cluster(points, args.max_swatches)
    assignments = _assignments(points, centers)
    _report(points, centers, assignments)
    if not args.apply:
        print("Dry run only; pass --apply to rewrite the canonical palette.")
        return 0
    _apply_migration(
        args.palette,
        text,
        points,
        centers,
        assignments,
        _swatch_ids(points, centers),
        entries,
    )
    print(f"Rewrote {args.palette} with {len(centers)} master swatches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

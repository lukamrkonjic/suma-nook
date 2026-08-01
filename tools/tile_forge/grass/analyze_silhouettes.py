#!/usr/bin/env python3
"""Silhouette gate for the carpet-tuft grass rebuild.

Run with the SYSTEM python (not Blender's). Requires Pillow only -- numpy is
deliberately not used, because this machine does not have it and a pure-Pillow
implementation is fast enough when the per-pixel work stays inside C (row
slices, ``bytes.find``, ``bytes.count``) instead of Python loops.

    python tools/tile_forge/grass/analyze_silhouettes.py --shot-dir <abs> [--out <json>]

WHY EACH METRIC EXISTS
----------------------
The brief asks for carpet tufts: low, chunky, overlapping teardrop lobes that
read as ONE soft mass. Every previous attempt died the same way -- it looked
plausible shaded and fell apart the moment it was reduced to an outline. Each
metric below is a specific failure mode from that history, measured from the
top-down silhouette so colour and shading cannot hide it:

  fill_ratio           solid area / convex hull area. Catches STAR and SPIDER
                       silhouettes: a shape made of separate radiating spikes
                       has a huge hull and little solid inside it. A chunky
                       mass fills its own hull.
  internal_gap_ratio   enclosed background over solid+enclosed. Catches HOLLOW
                       ROSETTES -- leaves arranged in a ring with daylight
                       punched through the middle. A carpet tuft is opaque.
  central_occupancy    how solid the middle of the shape is. Catches an OPEN
                       CROWN: a tuft that splays outward and thins at the core
                       still has a convex-ish hull and no fully enclosed hole,
                       so it slips past the two metrics above, but it reads as
                       a wreath rather than a lump.
  major_outer_peaks    significant lobes on the outline. Catches "READS AS
                       INDIVIDUAL BLADES": many sharp radial maxima mean the
                       eye resolves separate leaves instead of one soft mass.

GATE (art brief)
----------------
    fill_ratio          >= 0.74
    internal_gap_ratio  <= 0.03
    central_occupancy   >= 0.95
    major_outer_peaks   <= 5

Carpet modules gate the run (exit 1 on failure). Accent modules and the
grouped contact sheet are measured and printed for reference only -- an accent
leaf is *supposed* to be leafy, and a 12-tuft sheet is 12 separate shapes, so
gating either would be meaningless.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment problem, not a logic path
    sys.stderr.write(
        "analyze_silhouettes.py needs Pillow: python -m pip install Pillow\n"
    )
    raise SystemExit(2)


# A silhouette pass renders near-black geometry on a bright plate, so "darker
# than 50% luma" is a wide, forgiving separation rather than a knife edge.
SOLID_LUMA_MAX = 128

FILL_RATIO_MIN = 0.74
INTERNAL_GAP_RATIO_MAX = 0.03
CENTRAL_OCCUPANCY_MIN = 0.95
MAJOR_OUTER_PEAKS_MAX = 5

# Fraction of the bounding box treated as "the middle" for central_occupancy.
CENTRAL_BOX_FRACTION = 0.45

# Radial-profile tuning (see _major_outer_peaks for the heuristic write-up).
RADIAL_SAMPLES = 360
RADIAL_STEP_PX = 0.5
RADIAL_SMOOTH_WINDOW = 9
PEAK_RADIUS_FACTOR = 1.06
PEAK_MIN_SEPARATION_DEG = 25


# ---------------------------------------------------------------------------
# mask loading
# ---------------------------------------------------------------------------


def _load_mask(path: Path) -> tuple[bytearray, int, int]:
	"""Return a 1-byte-per-pixel solid mask, padded by one background pixel.

	The pad matters: the hole detector floods background inward from (0, 0), and
	a tuft that touches the image edge would otherwise trap real background and
	report it as an internal gap.
	"""
	with Image.open(path) as source:
		image = source
		# A transparent render would read as "black = solid" once flattened
		# naively, so composite onto white and let the alpha become background.
		if image.mode in ("RGBA", "LA") or "transparency" in image.info:
			image = image.convert("RGBA")
			plate = Image.new("RGBA", image.size, (255, 255, 255, 255))
			image = Image.alpha_composite(plate, image)
		grey = image.convert("L")

	width, height = grey.size
	# One LUT pass in C turns luma into a 0/1 mask; no per-pixel Python.
	lut = bytes([1] * SOLID_LUMA_MAX + [0] * (256 - SOLID_LUMA_MAX))
	rows = grey.point(lut, mode="L").tobytes()

	padded_width = width + 2
	padded_height = height + 2
	mask = bytearray(padded_width * padded_height)
	for y in range(height):
		start = (y + 1) * padded_width + 1
		mask[start:start + width] = rows[y * width:(y + 1) * width]
	return mask, padded_width, padded_height


def _solid_runs(mask: bytearray, width: int, height: int) -> list[tuple[int, int, int]]:
	"""Horizontal runs of solid pixels as (y, x_first, x_last), inclusive.

	Everything downstream (area, bbox, centroid, hull seeds) is derived from
	these runs, so the image is scanned exactly once and the Python loop count
	is proportional to outline complexity rather than to pixel count.
	"""
	runs: list[tuple[int, int, int]] = []
	for y in range(height):
		row = y * width
		cursor = row
		row_end = row + width
		while True:
			start = mask.find(1, cursor, row_end)
			if start < 0:
				break
			stop = mask.find(0, start, row_end)
			if stop < 0:
				stop = row_end
			runs.append((y, start - row, stop - row - 1))
			cursor = stop
	return runs


# ---------------------------------------------------------------------------
# convex hull
# ---------------------------------------------------------------------------


def _convex_hull(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
	"""Andrew's monotone chain. Returns the hull counter-clockwise, no repeats."""
	ordered = sorted(set(points))
	if len(ordered) < 3:
		return ordered

	def cross(o, a, b) -> float:
		return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

	lower: list[tuple[float, float]] = []
	for point in ordered:
		while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0.0:
			lower.pop()
		lower.append(point)

	upper: list[tuple[float, float]] = []
	for point in reversed(ordered):
		while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0.0:
			upper.pop()
		upper.append(point)

	return lower[:-1] + upper[:-1]


def _polygon_area(polygon: list[tuple[float, float]]) -> float:
	"""Shoelace area, always positive."""
	if len(polygon) < 3:
		return 0.0
	total = 0.0
	previous = polygon[-1]
	for point in polygon:
		total += previous[0] * point[1] - point[0] * previous[1]
		previous = point
	return abs(total) * 0.5


def _hull_area(runs: list[tuple[int, int, int]]) -> float:
	"""Convex hull area of the solid pixels, in pixel-area units.

	Two shortcuts, both exact:
	  * only each row's extreme run ends can be hull vertices, so at most 2
	    points per row are fed to the hull;
	  * pixels are treated as unit SQUARES (corners at x and x+1, y and y+1)
	    rather than points. Pixel-centre coordinates would make a solid w x h
	    block hull out to (w-1)(h-1) and push fill_ratio above 1.0.
	"""
	extents: dict[int, tuple[int, int]] = {}
	for y, x_first, x_last in runs:
		current = extents.get(y)
		if current is None:
			extents[y] = (x_first, x_last)
		else:
			extents[y] = (min(current[0], x_first), max(current[1], x_last))

	corners: list[tuple[float, float]] = []
	for y, (x_first, x_last) in extents.items():
		left = float(x_first)
		right = float(x_last + 1)
		top = float(y)
		bottom = float(y + 1)
		corners.append((left, top))
		corners.append((left, bottom))
		corners.append((right, top))
		corners.append((right, bottom))
	return _polygon_area(_convex_hull(corners))


# ---------------------------------------------------------------------------
# enclosed holes
# ---------------------------------------------------------------------------


def _internal_hole_area(mask: bytearray, width: int, height: int) -> int:
	"""Background pixels the outside cannot reach, i.e. fully enclosed holes.

	Span-based flood fill from the padded corner. ``blocked`` starts as the
	solid mask and gains every background pixel the flood reaches, so the
	remainder -- total minus blocked -- is exactly the enclosed area, counted in
	C by ``bytearray.count``. Background uses 4-connectivity, which pairs with
	8-connected solid and is the strict reading of "fully enclosed".
	"""
	blocked = bytearray(mask)
	stack: list[tuple[int, int]] = [(0, 0)]
	while stack:
		x, y = stack.pop()
		row = y * width
		if blocked[row + x]:
			continue

		left_wall = blocked.rfind(1, row, row + x)
		x_first = 0 if left_wall < 0 else left_wall - row + 1
		right_wall = blocked.find(1, row + x, row + width)
		x_last = width - 1 if right_wall < 0 else right_wall - row - 1
		blocked[row + x_first:row + x_last + 1] = b"\x01" * (x_last - x_first + 1)

		for neighbour_y in (y - 1, y + 1):
			if neighbour_y < 0 or neighbour_y >= height:
				continue
			neighbour_row = neighbour_y * width
			scan = neighbour_row + x_first
			limit = neighbour_row + x_last + 1
			while scan < limit:
				gap = blocked.find(0, scan, limit)
				if gap < 0:
					break
				stack.append((gap - neighbour_row, neighbour_y))
				wall = blocked.find(1, gap, limit)
				scan = limit if wall < 0 else wall
	return width * height - blocked.count(1)


# ---------------------------------------------------------------------------
# lobe counting
# ---------------------------------------------------------------------------


def _radial_profile(
	mask: bytearray,
	width: int,
	height: int,
	centre_x: float,
	centre_y: float,
	max_radius: float,
) -> list[float]:
	"""Distance from the centroid to the FURTHEST solid pixel at each degree.

	Marching inward from max_radius and stopping at the first hit gives the
	furthest pixel directly, and skips the empty interior of concave shapes.
	"""
	profile = [0.0] * RADIAL_SAMPLES
	for index in range(RADIAL_SAMPLES):
		angle = math.radians(index)
		step_x = math.cos(angle)
		step_y = math.sin(angle)
		radius = max_radius
		while radius > 0.0:
			x = int(centre_x + step_x * radius)
			y = int(centre_y + step_y * radius)
			if 0 <= x < width and 0 <= y < height and mask[y * width + x]:
				profile[index] = radius
				break
			radius -= RADIAL_STEP_PX
	return profile


def _smooth_circular(values: list[float], window: int) -> list[float]:
	"""Boxcar mean that wraps around 0/360 -- the profile is a closed loop."""
	count = len(values)
	half = window // 2
	smoothed = [0.0] * count
	for index in range(count):
		total = 0.0
		for offset in range(-half, half + 1):
			total += values[(index + offset) % count]
		smoothed[index] = total / float(window)
	return smoothed


def _major_outer_peaks(profile: list[float]) -> tuple[int, list[int]]:
	"""Count significant lobes on the outline. HEURISTIC -- read before trusting.

	The rule, spelled out because the number is a judgement call dressed as a
	measurement:
	  1. take the 360-sample radial profile (centroid -> furthest solid pixel);
	  2. smooth it with a 9 degree circular boxcar, which erases polygon facets
	     and render aliasing but leaves a real lobe standing;
	  3. keep local maxima whose smoothed radius exceeds 1.06 x the mean radius
	     -- a lobe has to actually stick out, not merely be a local wobble;
	  4. walk the survivors strongest-first and drop any within 25 degrees of an
	     already-accepted peak, so one broad lobe counts once.

	Consequences worth knowing: a perfect disc scores 0 (nothing clears 1.06x),
	an ellipse scores 2, and the count saturates for shapes with more than a
	dozen fine spikes, which is fine because the gate only asks "<= 5".
	"""
	if not any(profile):
		return 0, []

	smoothed = _smooth_circular(profile, RADIAL_SMOOTH_WINDOW)
	count = len(smoothed)
	mean_radius = sum(smoothed) / float(count)
	if mean_radius <= 0.0:
		return 0, []
	threshold = mean_radius * PEAK_RADIUS_FACTOR

	candidates: list[int] = []
	for index in range(count):
		value = smoothed[index]
		if value < threshold:
			continue
		# ">= previous" with "> next" resolves flat tops to a single index.
		if value >= smoothed[(index - 1) % count] and value > smoothed[(index + 1) % count]:
			candidates.append(index)

	accepted: list[int] = []
	for index in sorted(candidates, key=lambda i: smoothed[i], reverse=True):
		clash = False
		for taken in accepted:
			separation = abs(index - taken)
			separation = min(separation, count - separation)
			if separation < PEAK_MIN_SEPARATION_DEG:
				clash = True
				break
		if not clash:
			accepted.append(index)
	return len(accepted), sorted(accepted)


# ---------------------------------------------------------------------------
# per-image analysis
# ---------------------------------------------------------------------------


def analyse(path: Path) -> dict:
	mask, width, height = _load_mask(path)
	runs = _solid_runs(mask, width, height)

	metrics: dict = {
		"file": path.name,
		"image_width": width - 2,
		"image_height": height - 2,
	}

	if not runs:
		metrics.update({
			"width_px": 0,
			"height_px": 0,
			"solid_area": 0,
			"hull_area": 0.0,
			"fill_ratio": 0.0,
			"internal_hole_area": 0,
			"internal_gap_ratio": 0.0,
			"central_occupancy": 0.0,
			"central_solid_share": 0.0,
			"major_outer_peaks": 0,
			"peak_angles_deg": [],
			"empty": True,
		})
		return metrics

	solid_area = 0
	sum_x = 0
	sum_y = 0
	x_min = width
	x_max = -1
	for y, x_first, x_last in runs:
		length = x_last - x_first + 1
		solid_area += length
		# Closed form for the run's x sum keeps this loop off the pixel grid.
		# (x_first + x_last) * length is always even, so // 2 is exact.
		sum_x += (x_first + x_last) * length // 2
		sum_y += y * length
		if x_first < x_min:
			x_min = x_first
		if x_last > x_max:
			x_max = x_last
	y_min = runs[0][0]
	y_max = runs[-1][0]

	box_width = x_max - x_min + 1
	box_height = y_max - y_min + 1
	centre_x = sum_x / float(solid_area) + 0.5
	centre_y = sum_y / float(solid_area) + 0.5

	hull_area = _hull_area(runs)
	fill_ratio = (solid_area / hull_area) if hull_area > 0.0 else 0.0

	hole_area = _internal_hole_area(mask, width, height)
	internal_gap_ratio = hole_area / float(solid_area + hole_area)

	# Central 45% box: a centred sub-rectangle 45% of the bbox in each axis.
	central_width = max(1, int(round(box_width * CENTRAL_BOX_FRACTION)))
	central_height = max(1, int(round(box_height * CENTRAL_BOX_FRACTION)))
	central_x = x_min + (box_width - central_width) // 2
	central_y = y_min + (box_height - central_height) // 2
	central_solid = 0
	for y in range(central_y, central_y + central_height):
		row = y * width
		central_solid += mask.count(1, row + central_x, row + central_x + central_width)
	central_area = central_width * central_height

	max_radius = 0.0
	for corner in ((x_min, y_min), (x_max + 1, y_min), (x_min, y_max + 1), (x_max + 1, y_max + 1)):
		max_radius = max(max_radius, math.hypot(corner[0] - centre_x, corner[1] - centre_y))
	profile = _radial_profile(mask, width, height, centre_x, centre_y, max_radius + 1.0)
	peaks, peak_angles = _major_outer_peaks(profile)

	metrics.update({
		"width_px": box_width,
		"height_px": box_height,
		"bbox": [x_min - 1, y_min - 1, x_max - 1, y_max - 1],
		"solid_area": solid_area,
		"hull_area": round(hull_area, 2),
		"fill_ratio": round(fill_ratio, 4),
		"internal_hole_area": hole_area,
		"internal_gap_ratio": round(internal_gap_ratio, 4),
		# Solid coverage OF the central box. See NOTE in _check() for why this,
		# and not "share of all solid pixels", is the gated number.
		"central_occupancy": round(central_solid / float(central_area), 4),
		"central_solid_share": round(central_solid / float(solid_area), 4),
		"central_box": [central_x - 1, central_y - 1, central_width, central_height],
		"centroid": [round(centre_x - 1.0, 2), round(centre_y - 1.0, 2)],
		"major_outer_peaks": peaks,
		"peak_angles_deg": peak_angles,
		"empty": False,
	})
	return metrics


def _check(metrics: dict) -> dict:
	"""Per-metric pass/fail against the art brief.

	NOTE on central_occupancy: the brief phrases it as "fraction of solid pixels
	within the central 45% of the bbox", but a box that is 45% x 45% of the bbox
	holds at most ~20% of the area, so no shape could ever reach the >= 0.95
	gate under that reading. The gated value is therefore how SOLID the central
	box is (solid pixels inside it / its area), which is the number that
	actually catches an open crown. The literal reading is still reported, as
	``central_solid_share``, for anyone who wants it.
	"""
	return {
		"fill_ratio": metrics["fill_ratio"] >= FILL_RATIO_MIN,
		"internal_gap_ratio": metrics["internal_gap_ratio"] <= INTERNAL_GAP_RATIO_MAX,
		"central_occupancy": metrics["central_occupancy"] >= CENTRAL_OCCUPANCY_MIN,
		"major_outer_peaks": metrics["major_outer_peaks"] <= MAJOR_OUTER_PEAKS_MAX,
	}


# ---------------------------------------------------------------------------
# shot discovery
# ---------------------------------------------------------------------------


def _manifest_kinds(shot_dir: Path, manifest: Path | None) -> dict[str, str]:
	"""Module id -> kind, from carpet_report.json if we can find one."""
	candidates: list[Path] = []
	if manifest is not None:
		candidates.append(manifest)
	else:
		candidates.append(shot_dir / "carpet_report.json")
		candidates.append(
			Path(__file__).resolve().parent.parent / "modules" / "grass" / "carpet_report.json"
		)
	for candidate in candidates:
		try:
			data = json.loads(candidate.read_text(encoding="utf-8"))
		except (OSError, ValueError):
			continue
		kinds = {
			str(entry.get("id", "")): str(entry.get("kind", ""))
			for entry in data.get("modules", [])
			if entry.get("id")
		}
		if kinds:
			return kinds
	return {}


def _collect(shot_dir: Path, manifest: Path | None) -> list[tuple[str, str, Path]]:
	"""Every silhouette shot as (module_id, kind, path), carpets first."""
	kinds = _manifest_kinds(shot_dir, manifest)
	found: list[tuple[str, str, Path]] = []

	for path in sorted(shot_dir.glob("sil_top_*.png")):
		module_id = path.stem[len("sil_top_"):]
		kind = kinds.get(module_id, "")
		if not kind:
			# Fall back on the naming convention when no manifest is around.
			kind = "accent" if module_id.startswith("accent") else "carpet"
		found.append((module_id, kind, path))

	sheet = shot_dir / "carpet_12_sil.png"
	if sheet.is_file():
		# Twelve scattered tufts in one frame: measuring it as a single shape
		# would fail every check by construction, so it is reference only.
		found.append(("carpet_12", "sheet", sheet))

	order = {"carpet": 0, "accent": 1, "sheet": 2}
	found.sort(key=lambda item: (order.get(item[1], 3), item[0]))
	return found


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------


COLUMNS = (
	("module", 20, "<"),
	("kind", 7, "<"),
	("w px", 6, ">"),
	("h px", 6, ">"),
	("solid", 8, ">"),
	("fill", 6, ">"),
	("gaps", 6, ">"),
	("centre", 7, ">"),
	("peaks", 6, ">"),
	("result", 8, "<"),
)


def _row(cells: list[str]) -> str:
	parts = []
	for value, (_, width, align) in zip(cells, COLUMNS):
		text = value if len(value) <= width else value[:width]
		parts.append(f"{text:{align}{width}}")
	return "| " + " | ".join(parts) + " |"


def _separator() -> str:
	parts = []
	for _, width, align in COLUMNS:
		if align == ">":
			parts.append("-" * (width - 1) + ":")
		else:
			parts.append(":" + "-" * (width - 1))
	return "| " + " | ".join(parts) + " |"


def _flag(value: str, ok: bool) -> str:
	"""A trailing ! marks the value that broke the gate -- readable in a log."""
	return value if ok else value + "!"


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(
		description="Measure carpet-tuft silhouettes against the art-brief gate.",
	)
	parser.add_argument("--shot-dir", required=True, help="directory holding sil_top_*.png")
	parser.add_argument("--out", default=None, help="JSON report path (default <shot-dir>/carpet_metrics.json)")
	parser.add_argument("--manifest", default=None, help="carpet_report.json to read module kinds from")
	args = parser.parse_args(argv)

	shot_dir = Path(args.shot_dir).expanduser().resolve()
	if not shot_dir.is_dir():
		sys.stderr.write(f"no such shot dir: {shot_dir}\n")
		return 2

	out_path = Path(args.out).expanduser().resolve() if args.out else shot_dir / "carpet_metrics.json"
	manifest = Path(args.manifest).expanduser().resolve() if args.manifest else None

	shots = _collect(shot_dir, manifest)
	if not shots:
		# An empty shot dir means the render pass never ran. Reporting "0/0 pass"
		# and exiting clean would let a broken pipeline look green.
		sys.stderr.write(f"no sil_top_*.png found in {shot_dir}\n")
		return 1

	entries: list[dict] = []
	for module_id, kind, path in shots:
		metrics = analyse(path)
		metrics["id"] = module_id
		metrics["kind"] = kind
		checks = _check(metrics)
		metrics["checks"] = checks
		metrics["gating"] = kind == "carpet"
		metrics["pass"] = all(checks.values())
		entries.append(metrics)

	gating = [entry for entry in entries if entry["gating"]]
	passed = [entry for entry in gating if entry["pass"]]

	report = {
		"shot_dir": str(shot_dir),
		"solid_luma_max": SOLID_LUMA_MAX,
		"gate": {
			"fill_ratio_min": FILL_RATIO_MIN,
			"internal_gap_ratio_max": INTERNAL_GAP_RATIO_MAX,
			"central_occupancy_min": CENTRAL_OCCUPANCY_MIN,
			"major_outer_peaks_max": MAJOR_OUTER_PEAKS_MAX,
			"central_box_fraction": CENTRAL_BOX_FRACTION,
		},
		"modules": entries,
		"summary": {
			"gating_modules": len(gating),
			"gating_passed": len(passed),
			"failed": [entry["id"] for entry in gating if not entry["pass"]],
			"reported_only": [entry["id"] for entry in entries if not entry["gating"]],
		},
	}
	out_path.parent.mkdir(parents=True, exist_ok=True)
	out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

	lines = [
		_row([name for name, _, _ in COLUMNS]),
		_separator(),
	]
	for entry in entries:
		checks = entry["checks"]
		gates = entry["gating"]
		lines.append(_row([
			entry["id"],
			entry["kind"],
			str(entry["width_px"]),
			str(entry["height_px"]),
			str(entry["solid_area"]),
			_flag(f"{entry['fill_ratio']:.3f}", checks["fill_ratio"] or not gates),
			_flag(f"{entry['internal_gap_ratio']:.3f}", checks["internal_gap_ratio"] or not gates),
			_flag(f"{entry['central_occupancy']:.3f}", checks["central_occupancy"] or not gates),
			_flag(str(entry["major_outer_peaks"]), checks["major_outer_peaks"] or not gates),
			("PASS" if entry["pass"] else "FAIL") if gates else "(info)",
		]))

	print("\n".join(lines))
	print("")
	for entry in entries:
		if not entry["gating"] or entry["pass"]:
			continue
		broken = ", ".join(name for name, ok in entry["checks"].items() if not ok)
		print(f"  {entry['id']} failed: {broken}")
	if report["summary"]["reported_only"]:
		print(
			"  reported only (never fail the run): "
			+ ", ".join(report["summary"]["reported_only"])
		)
	print(f"  report written to {out_path}")
	print("")
	print(f"CARPET SILHOUETTE GATE: {len(passed)}/{len(gating)} modules pass")
	return 0 if len(passed) == len(gating) else 1


if __name__ == "__main__":
	raise SystemExit(main())

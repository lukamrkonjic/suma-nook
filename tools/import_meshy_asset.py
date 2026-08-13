"""Guarded Meshy GLB -> clean Suma asset importer.

This is the supported front door for generated GLBs. Blender performs the
material conversion, produces a machine-readable safety report and neutral
review render, and only then is the staged GLB installed into the game.
Geometry is never remeshed, decimated, subdivided, or relaxed by this tool.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BLENDER = Path(
    r"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
)
# Broad visual families. These select the material palette and the tree/prop
# handling; they deliberately no longer carry a smoothing value.
#
# They used to (tree 0.82, shrub 0.26, wood_prop 0.42, stone_prop 0.34,
# generic 0.30), which predates the game-wide default in data/asset_edits.json.
# Once that default existed, writing any per-asset value opted every freshly
# imported asset OUT of it -- an import at wood_prop landed on 0.42 while the
# rest of the library shaded at 0.85, and arrived looking faceted next to
# everything around it. Imports now inherit the default; pass --smoothing only
# when a specific asset has been reviewed and genuinely needs its own value.
PROFILES = ("tree", "shrub", "wood_prop", "stone_prop", "generic")

# Runtime smoothing blends authored normals toward position-welded ones. That
# rescues a dense unwelded Meshy spray, where every triangle is its own shading
# island and the facets are an artifact of export. It ruins a welded low-poly
# model, where the facets ARE the design: at the 0.85 default the wheelbarrow's
# normals moved by up to 160 degrees and the fir's by 174 -- past perpendicular,
# so lit faces shade as if they pointed away from the sun and the model reads as
# melted. The assets that were never smoothed are the ones that look right
# (firepit 0.0, radio 0.42/46deg), which is the same conclusion from the other
# direction. So: measure, and leave authored shading alone.
WELDED_VERTEX_FACE_RATIO_MAX = 2.5
AUTHORED_SHADING_TRIANGLE_MAX = 2500


def derived_smoothing(geometry: dict) -> tuple[float | None, str]:
    """Pick a smoothing value from measured geometry, with the reason why."""
    faces = int(geometry.get("faces", 0) or 0)
    # Distinct positions where available. The raw vertex count triples for a
    # flat-shaded model that has been through any re-export, which would read
    # as split vertices and hand an authored-facet model the 0.85 default.
    vertices = int(
        geometry.get("welded_vertices", 0) or geometry.get("vertices", 0) or 0
    )
    triangles = int(geometry.get("triangles", 0) or 0)
    if faces <= 0 or vertices <= 0:
        return None, "geometry unavailable; inheriting the default"
    ratio = vertices / faces
    if ratio >= WELDED_VERTEX_FACE_RATIO_MAX:
        return None, (
            f"split vertices ({ratio:.2f} verts/face); "
            "inheriting the default to rescue export facets"
        )
    if triangles > AUTHORED_SHADING_TRIANGLE_MAX:
        return None, (
            f"dense ({triangles} triangles); inheriting the default"
        )
    return 0.0, (
        f"welded ({ratio:.2f} verts/face) and low-poly ({triangles} "
        "triangles); facets are authored, so shading is left alone"
    )
ASSET_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Clean and install a Meshy GLB in Suma's GG-like style."
    )
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument(
        "--profile",
        required=True,
        choices=PROFILES,
        help="Broad visual family; this is deliberately not guessed.",
    )
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--smoothing", type=float)
    parser.add_argument(
        "--color-merge-distance",
        type=float,
        help=(
            "How close two colour clusters must be to count as one paint "
            "(default 0.12). Lower it when a reference image shows more "
            "materials than the import finds."
        ),
    )
    parser.add_argument(
        "--rotate-medium-cluster",
        type=float,
        default=0.0,
        help="Rigidly turn the medium of three grounded prop forms.",
    )
    parser.add_argument("--blender", type=Path, default=DEFAULT_BLENDER)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--review-dir", type=Path)
    parser.add_argument("--no-install", action="store_true")
    parser.add_argument("--no-profile", action="store_true")
    parser.add_argument("--skip-render", action="store_true")
    parser.add_argument("--allow-untextured", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def checked_path(path: Path, description: str) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_file():
        raise SystemExit(f"Missing {description}: {resolved}")
    return resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def root_name(asset_id: str) -> str:
    return "".join(part.capitalize() for part in asset_id.split("_"))


def run_blender(blender: Path, script: Path, arguments: list[str]) -> None:
    command = [
        str(blender),
        "--background",
        "--factory-startup",
        "--python-exit-code",
        "1",
        "--python",
        str(script),
        "--",
        *arguments,
    ]
    subprocess.run(command, cwd=REPOSITORY_ROOT, check=True)


def update_asset_profile(asset_id: str, scale: float, smoothing: float | None) -> None:
    path = REPOSITORY_ROOT / "data" / "asset_edits.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    profiles = payload.setdefault("profiles", {})
    existing = profiles.get(asset_id, {})
    materials = existing.get("materials", {}) if isinstance(existing, dict) else {}
    profile: dict = {"scale": scale, "materials": materials}
    # Omitting the key is what lets the asset inherit the game-wide default.
    # derived_smoothing() decides which of the two an asset wants; a value of
    # 0.0 here is a deliberate opt-out, not an oversight.
    if smoothing is not None:
        profile["smoothing"] = smoothing
    profiles[asset_id] = profile
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(payload, indent="\t", ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def main() -> None:
    arguments = parse_args()
    if not ASSET_ID_PATTERN.fullmatch(arguments.asset_id):
        raise SystemExit("--asset-id must contain lowercase letters, digits, and underscores")
    # Generated sources arrive normalised to a longest edge of 1.0, while the
    # assets they replace were authored at their world size -- prop_shelter is
    # 1.5 across. Preserving world size across that pair legitimately needs a
    # scale near 5, so the old ceiling of 3.0 rejected a correct value. The
    # bound stays only to catch a misplaced decimal point.
    if not 0.1 <= arguments.scale <= 12.0:
        raise SystemExit("--scale must be between 0.1 and 12.0")
    smoothing = arguments.smoothing
    if smoothing is not None and not 0.0 <= smoothing <= 1.0:
        raise SystemExit("--smoothing must be between 0.0 and 1.0")

    source = checked_path(arguments.source, "source GLB")
    blender = checked_path(arguments.blender, "Blender executable")
    output = (
        arguments.output.resolve()
        if arguments.output is not None
        else REPOSITORY_ROOT
        / "assets"
        / "3d"
        / "reworked"
        / f"{arguments.asset_id}.glb"
    )
    if not arguments.no_install and output.exists() and not arguments.force:
        raise SystemExit(f"Refusing to overwrite {output}; pass --force after review")
    if source == output:
        raise SystemExit("Source and installed output must be different files")

    review_directory = (
        arguments.review_dir.resolve()
        if arguments.review_dir is not None
        else REPOSITORY_ROOT.parent
        / f"{REPOSITORY_ROOT.name}-asset-reviews"
        / arguments.asset_id
    )
    review_directory.mkdir(parents=True, exist_ok=True)
    staged = review_directory / f"{arguments.asset_id}.staged.glb"
    report_path = review_directory / "report.json"
    review_path = review_directory / "review.png"

    prepare_arguments = [
        "--source",
        str(source),
        "--output",
        str(staged),
        "--mode",
        "tree" if arguments.profile in {"tree", "shrub"} else "prop",
        "--root-name",
        root_name(arguments.asset_id),
        "--style-profile",
        arguments.profile,
        "--report",
        str(report_path),
    ]
    if arguments.color_merge_distance is not None:
        prepare_arguments.extend(
            ["--cluster-merge-distance", str(arguments.color_merge_distance)]
        )
    if not abs(arguments.rotate_medium_cluster) < 1.0e-6:
        prepare_arguments.extend(
            ["--rotate-medium-cluster", str(arguments.rotate_medium_cluster)]
        )
    run_blender(
        blender,
        REPOSITORY_ROOT / "tools" / "prepare_model_import.py",
        prepare_arguments,
    )
    report = json.loads(report_path.read_text(encoding="utf-8"))
    has_authored_adjustment = bool(report.get("authored_adjustments"))
    if not report.get("topology_preserved") or (
        not report.get("dimensions_preserved") and not has_authored_adjustment
    ):
        raise SystemExit("Safety gate rejected the staged model: geometry changed")
    if (
        not arguments.allow_untextured
        and int(report.get("source_textures", {}).get("albedo_images", 0)) == 0
    ):
        raise SystemExit("Safety gate rejected the model: no source albedo was found")
    if not report.get("semantic_face_usage"):
        raise SystemExit("Safety gate rejected the model: no semantic materials were assigned")

    smoothing_reason = "explicitly requested"
    if smoothing is None:
        smoothing, smoothing_reason = derived_smoothing(
            report.get("source_geometry", {})
        )
    print(f"smoothing: {smoothing if smoothing is not None else 'inherited'} -- {smoothing_reason}")

    if not arguments.skip_render:
        run_blender(
            blender,
            REPOSITORY_ROOT / "tools" / "render_stylized_asset.py",
            ["--source", str(staged), "--output", str(review_path)],
        )

    report.update(
        {
            "asset_id": arguments.asset_id,
            "source_sha256": sha256(source),
            "output_sha256": sha256(staged),
            "source_bytes": source.stat().st_size,
            "output_bytes": staged.stat().st_size,
            "review": str(review_path) if not arguments.skip_render else "",
            "scale": arguments.scale,
            "smoothing": smoothing if smoothing is not None else "inherited",
            "smoothing_reason": smoothing_reason,
            "status": "validated_staging" if arguments.no_install else "installed",
        }
    )

    if not arguments.no_install:
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(staged, output)
        report["installed_to"] = str(output)
        if not arguments.no_profile:
            update_asset_profile(arguments.asset_id, arguments.scale, smoothing)
    report_path.write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )

    print(f"MESHY_IMPORT_STATUS={report['status']}")
    print(f"MESHY_IMPORT_REPORT={report_path}")
    if not arguments.skip_render:
        print(f"MESHY_IMPORT_REVIEW={review_path}")
    if not arguments.no_install:
        print(f"MESHY_IMPORT_ASSET={output}")


if __name__ == "__main__":
    main()

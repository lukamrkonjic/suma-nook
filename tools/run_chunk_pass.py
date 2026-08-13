"""Drive the chunk pass over the assets listed in data/style_chunk_recipes.json.

Stages every asset to artifacts/chunk_pass/, renders a before/after contact
sheet per asset plus one combined sheet, and prints the measured fingerprint
move. Nothing touches the game until --install, which first snapshots the
current GLB to art_source/imported/<asset_id>/<asset_id>_pre_chunk.glb.

  python tools/run_chunk_pass.py                       # stage + review
  python tools/run_chunk_pass.py --assets prop_fir      # one asset
  python tools/run_chunk_pass.py --install              # ship it
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
RECIPES = REPOSITORY_ROOT / "data" / "style_chunk_recipes.json"
STAGING = REPOSITORY_ROOT / "artifacts" / "chunk_pass"
DEFAULT_BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe")
SEARCH_ORDER = ("reworked", "final", "proxies")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", nargs="*", default=[])
    parser.add_argument("--blender", type=Path, default=DEFAULT_BLENDER)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--skip-render", action="store_true")
    return parser.parse_args()


def resolve(asset_id: str) -> Path | None:
    for tier in SEARCH_ORDER:
        candidate = REPOSITORY_ROOT / "assets" / "3d" / tier / f"{asset_id}.glb"
        if candidate.is_file():
            return candidate
    return None


def run_blender(blender: Path, script: str, arguments: list[str]) -> None:
    subprocess.run(
        [
            str(blender),
            "--background",
            "--factory-startup",
            "--python-exit-code",
            "1",
            "--python",
            str(REPOSITORY_ROOT / "tools" / script),
            "--",
            *arguments,
        ],
        cwd=REPOSITORY_ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> None:
    arguments = parse_args()
    if not arguments.blender.is_file():
        raise SystemExit(f"Missing Blender: {arguments.blender}")
    payload = json.loads(RECIPES.read_text(encoding="utf-8"))
    defaults = payload["defaults"]
    recipes = payload["assets"]

    asset_ids = arguments.assets or sorted(recipes)
    unknown = [asset_id for asset_id in asset_ids if asset_id not in recipes]
    if unknown:
        raise SystemExit(f"No recipe for: {', '.join(unknown)}")

    STAGING.mkdir(parents=True, exist_ok=True)
    rows = []
    for asset_id in asset_ids:
        source = resolve(asset_id)
        if source is None:
            raise SystemExit(f"Asset not found: {asset_id}")
        settings = {**defaults, **recipes[asset_id]}
        staged = STAGING / f"{asset_id}.glb"
        report_path = STAGING / f"{asset_id}.report.json"
        pass_arguments = [
            "--source", str(source),
            "--output", str(staged),
            "--report", str(report_path),
            "--dissolve", str(settings["dissolve"]),
            "--planarize", str(settings["planarize"]),
            "--relax", str(settings["relax"]),
            "--bevel", str(settings["bevel"]),
            "--bevel-segments", str(settings["bevel_segments"]),
            "--widen", str(settings["widen"]),
            "--squash", str(settings["squash"]),
            "--thicken", str(settings["thicken"]),
            "--thicken-base", str(settings["thicken_base"]),
            "--thicken-ramp", str(settings["thicken_ramp"]),
            "--thicken-match", str(settings["thicken_match"]),
            "--stem-radius", str(settings["stem_radius"]),
            "--stem-height", str(settings["stem_height"]),
            "--tone-match", str(settings["tone_match"]),
            "--dome", str(settings["dome"]),
            "--dome-power", str(settings["dome_power"]),
            "--dome-aspect", str(settings["dome_aspect"]),
            "--dome-radius", str(settings["dome_radius"]),
        ]
        if settings["dome_material"]:
            pass_arguments.extend(["--dome-material", str(settings["dome_material"])])
        if settings["preserve_height"]:
            pass_arguments.append("--preserve-height")
        if settings["stem_material"]:
            pass_arguments.extend(["--stem-material", str(settings["stem_material"])])
        if settings["tone_ramp"]:
            pass_arguments.extend(["--tone-ramp", *settings["tone_ramp"]])
        run_blender(arguments.blender, "apply_suma_chunk_pass.py", pass_arguments)
        report = json.loads(report_path.read_text(encoding="utf-8"))
        rows.append((asset_id, source, staged, report))

        if not arguments.skip_render:
            run_blender(
                arguments.blender,
                "render_style_contact_sheet.py",
                [
                    "--sources", str(source), str(staged),
                    "--output", str(STAGING / f"{asset_id}_before_after.png"),
                    "--height", "640",
                ],
            )

    if not arguments.skip_render and len(rows) > 1:
        run_blender(
            arguments.blender,
            "render_style_contact_sheet.py",
            [
                "--sources", *[str(row[1]) for row in rows],
                "--output", str(STAGING / "_all_before.png"),
                "--height", "560",
            ],
        )
        run_blender(
            arguments.blender,
            "render_style_contact_sheet.py",
            [
                "--sources", *[str(row[2]) for row in rows],
                "--output", str(STAGING / "_all_after.png"),
                "--height", "560",
            ],
        )

    print(f"{'asset':<20}{'evenness':>20}{'tris':>18}{'recoloured':>22}")
    for asset_id, _, _, report in rows:
        before, after = report["before"], report["after"]
        recoloured = report.get("faces_recoloured", {})
        print(
            f"{asset_id:<20}"
            f"{before['facet_evenness']:>9.3f} -> {after['facet_evenness']:<8.3f}"
            f"{before['triangles']:>8} -> {after['triangles']:<8}"
            f"{'stem ' + str(recoloured.get('stem', 0)):>12}"
            f"{'  tone ' + str(recoloured.get('tone', 0)):>10}"
        )

    if not arguments.install:
        print(f"\nStaged in {STAGING}. Re-run with --install to ship.")
        return

    for asset_id, source, staged, _ in rows:
        archive = (
            REPOSITORY_ROOT
            / "art_source"
            / "imported"
            / asset_id
            / f"{asset_id}_pre_chunk.glb"
        )
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            shutil.copy2(source, archive)
        shutil.copy2(staged, source)
        print(f"installed {asset_id} -> {source.relative_to(REPOSITORY_ROOT)}")
    print("\nRun `godot --headless --path . --import` before reviewing in game.")


if __name__ == "__main__":
    main()

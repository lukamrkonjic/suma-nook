"""Measure objective shape-language metrics for shipped GLBs.

Suma's library is stitched together from several kits, so "does it clash?"
needs a number, not a vibe. This script reports, per asset, the handful of
metrics that actually separate the props Luka likes (vintage radio, table)
from the ones that read as generic low-poly (fir, pine, bushes):

  surface_ratio   mesh area / bounding-box area. A cube is ~1.0. Chunky
                  designed props stay low; spiky faceted foliage climbs.
  facet_scale     average facet edge length as a fraction of the object's
                  bounding diagonal. Scale-independent. Big designed planes
                  score high; a uniform spray of small triangles scores low.
  facet_evenness  median face area / p90 face area. HIGH means every face is
                  the same size -- the generated-remesh tell. LOW means a
                  size hierarchy: big planes carry the mass, small ones carry
                  the details. Hand-designed props sit low.
  components      welded loose parts = how many separate masses the eye must
                  parse.
  sharp_fraction  fraction of edge length whose dihedral exceeds 40 deg.
                  High = crunchy accidental faceting.
  chamfer_fraction  fraction of edge length in the 15-45 deg band, i.e.
                  deliberate bevels. The radio's charm lives here.
  welded          false when the source ships split vertices (one island per
                  triangle). Angle metrics are meaningless until welded, so
                  this script welds a working copy before measuring.

Run headless:
  blender --background --factory-startup --python tools/measure_style_fingerprint.py \
    -- --assets prop_vintage_radio prop_fir --out artifacts/style_fingerprint.json
Asset names resolve through reworked/ -> final/ -> proxies/, matching
AssetLibrary. Pass --all to sweep every reworked GLB.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SEARCH_ORDER = ("reworked", "final", "proxies")
SHARP_DEGREES = 40.0
CHAMFER_BAND = (15.0, 45.0)


def parse_args() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", nargs="*", default=[])
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args(arguments)


def resolve(asset_id: str) -> Path | None:
    for tier in SEARCH_ORDER:
        candidate = REPOSITORY_ROOT / "assets" / "3d" / tier / f"{asset_id}.glb"
        if candidate.is_file():
            return candidate
    return None


def measure(path: Path) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [item for item in bpy.context.scene.objects if item.type == "MESH"]
    if not meshes:
        return {"error": "no mesh"}

    mesh = bmesh.new()
    for item in meshes:
        copy = item.data.copy()
        copy.transform(item.matrix_world)
        mesh.from_mesh(copy)
        bpy.data.meshes.remove(copy)
    bmesh.ops.triangulate(mesh, faces=mesh.faces[:])
    mesh.faces.ensure_lookup_table()

    coordinates = [vertex.co for vertex in mesh.verts]
    minimum = Vector(tuple(min(c[axis] for c in coordinates) for axis in range(3)))
    maximum = Vector(tuple(max(c[axis] for c in coordinates) for axis in range(3)))
    size = maximum - minimum
    bbox_area = 2.0 * (size.x * size.y + size.y * size.z + size.z * size.x)
    diagonal = size.length

    # Many generated sources ship split vertices, one island per triangle.
    # Dihedral angles need shared edges, so weld a working copy first and
    # report whether the source needed it.
    vertices_before = len(mesh.verts)
    bmesh.ops.remove_doubles(mesh, verts=mesh.verts[:], dist=diagonal * 1.0e-4)
    mesh.faces.ensure_lookup_table()
    mesh.edges.ensure_lookup_table()
    # A source is "already welded" when the triangle count never implied one
    # island per face; 3 verts per triangle means fully split.
    welded = vertices_before < len(mesh.faces) * 2.5

    face_areas = [face.calc_area() for face in mesh.faces]
    total_area = sum(face_areas)
    ordered = sorted(face_areas)
    p90 = ordered[int(len(ordered) * 0.9)] if ordered else 0.0
    median = statistics.median(ordered) if ordered else 0.0

    sharp_length = 0.0
    chamfer_length = 0.0
    total_length = 0.0
    for edge in mesh.edges:
        if len(edge.link_faces) != 2:
            continue
        length = edge.calc_length()
        angle = math.degrees(edge.calc_face_angle(0.0))
        total_length += length
        if angle >= SHARP_DEGREES:
            sharp_length += length
        elif CHAMFER_BAND[0] <= angle < CHAMFER_BAND[1]:
            chamfer_length += length

    # Loose parts: flood fill across linked faces.
    seen: set[int] = set()
    components = 0
    for face in mesh.faces:
        if face.index in seen:
            continue
        components += 1
        stack = [face]
        seen.add(face.index)
        while stack:
            current = stack.pop()
            for edge in current.edges:
                for neighbour in edge.link_faces:
                    if neighbour.index not in seen:
                        seen.add(neighbour.index)
                        stack.append(neighbour)

    materials = sorted(
        {slot.material.name for item in meshes for slot in item.material_slots if slot.material}
    )
    triangles = len(mesh.faces)
    mesh.free()

    return {
        "path": str(path.relative_to(REPOSITORY_ROOT)),
        "dimensions": [round(value, 4) for value in (size.x, size.y, size.z)],
        "triangles": triangles,
        "components": components,
        "materials": materials,
        "welded": welded,
        "surface_ratio": round(total_area / bbox_area, 3) if bbox_area else 0.0,
        "facet_scale": (
            round(math.sqrt(total_area / triangles) / diagonal, 4)
            if triangles and diagonal
            else 0.0
        ),
        "sharp_fraction": round(sharp_length / total_length, 3) if total_length else 0.0,
        "chamfer_fraction": round(chamfer_length / total_length, 3) if total_length else 0.0,
        "facet_evenness": round(median / p90, 3) if p90 else 0.0,
    }


def main() -> None:
    arguments = parse_args()
    asset_ids = list(arguments.assets)
    if arguments.all:
        directory = REPOSITORY_ROOT / "assets" / "3d" / "reworked"
        asset_ids = sorted(path.stem for path in directory.glob("*.glb"))

    results = {}
    for asset_id in asset_ids:
        path = resolve(asset_id)
        if path is None:
            results[asset_id] = {"error": "not found"}
            continue
        results[asset_id] = measure(path)
        print(f"measured {asset_id}")

    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    arguments.out.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(f"FINGERPRINT_OUT={arguments.out}")


if __name__ == "__main__":
    main()

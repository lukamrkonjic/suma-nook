"""Locate the pipeline stage that introduces garment topology defects."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import bmesh


REPO = Path(r"C:\Dev\suma-nook")
PROCESSOR_PATH = REPO / "tools/clothing_lab/process_clothing.py"
CONFIG_PATH = (
    REPO / "art_source/imported/jacket_default/clothing_lab_fit.json"
)


def _load_processor():
    spec = importlib.util.spec_from_file_location(
        "clothing_lab_processor", PROCESSOR_PATH
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _summary(garment) -> dict:
    bm = bmesh.new()
    bm.from_mesh(garment.data)
    vertices_before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    boundary = [edge for edge in bm.edges if len(edge.link_faces) == 1]
    over_connected = [edge for edge in bm.edges if len(edge.link_faces) > 2]
    result = {
        "vertices_before_test_weld": vertices_before,
        "vertices_after_test_weld": len(bm.verts),
        "faces": len(bm.faces),
        "boundary_edges": len(boundary),
        "over_connected_edges": len(over_connected),
        "wire_edges": sum(not edge.link_faces for edge in bm.edges),
    }
    bm.free()
    return result


def main() -> None:
    processor = _load_processor()
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    rig, body, _immutable = processor.setup_master()
    garment, _source_report = processor.import_source(
        processor.resolved_path(config["source_file"])
    )
    stages = [
        ("import", lambda: None),
        ("fit", lambda: processor.apply_explicit_fit(garment, config)),
        (
            "weld",
            lambda: processor.weld_coincident_geometry_preserving_loops(
                garment
            ),
        ),
        ("symmetry", lambda: processor.symmetrize_sleeves(garment)),
        (
            "support_geometry",
            lambda: processor.audit_deformation_geometry(garment),
        ),
        (
            "shrinkwrap",
            lambda: processor.limited_shrinkwrap_clearance(garment, body),
        ),
        (
            "triangulate",
            lambda: processor.triangulate_for_export(garment),
        ),
        (
            "degenerate_cleanup",
            lambda: processor.remove_degenerate_faces(garment),
        ),
    ]
    for name, operation in stages:
        operation()
        print(
            "GARMENT_STAGE_AUDIT "
            + json.dumps({"stage": name, **_summary(garment)})
        )
    del rig


if __name__ == "__main__":
    main()

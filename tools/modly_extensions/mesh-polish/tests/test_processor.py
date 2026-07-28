from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import trimesh


EXTENSION_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EXTENSION_DIR))

import processor


def fixture_mesh() -> trimesh.Trimesh:
    first = trimesh.creation.icosphere(subdivisions=2, radius=0.5)
    first.apply_scale([1.4, 0.8, 0.9])
    second = trimesh.creation.cylinder(radius=0.25, height=0.8, sections=24)
    second.apply_translation([1.2, 0.15, 0.0])
    return trimesh.util.concatenate([first, second])


class MeshPolishTests(unittest.TestCase):
    def test_presets_have_requested_values(self) -> None:
        expected = {
            "soft_polish": (2.0, 0.75, 4),
            "standard_polish": (2.0, 1.0, 6),
            "strong_polish": (1.5, 1.5, 10),
            "normals_only": (False, 0, "smooth_all"),
            "preserve_hard_surface": (35.0, 2, 45.0),
        }
        loaded = {
            name: json.loads(
                (EXTENSION_DIR / "presets" / f"{name}.json").read_text()
            )
            for name in expected
        }
        self.assertEqual(
            (
                loaded["soft_polish"]["target_edge_length_percent"],
                loaded["soft_polish"]["maximum_surface_distance_percent"],
                loaded["soft_polish"]["smoothing_iterations"],
            ),
            expected["soft_polish"],
        )
        self.assertEqual(
            (
                loaded["standard_polish"]["target_edge_length_percent"],
                loaded["standard_polish"]["maximum_surface_distance_percent"],
                loaded["standard_polish"]["smoothing_iterations"],
            ),
            expected["standard_polish"],
        )
        self.assertEqual(
            (
                loaded["strong_polish"]["target_edge_length_percent"],
                loaded["strong_polish"]["maximum_surface_distance_percent"],
                loaded["strong_polish"]["smoothing_iterations"],
            ),
            expected["strong_polish"],
        )
        self.assertEqual(
            (
                loaded["normals_only"]["remesh_enabled"],
                loaded["normals_only"]["smoothing_iterations"],
                loaded["normals_only"]["normals_mode"],
            ),
            expected["normals_only"],
        )
        self.assertEqual(
            (
                loaded["preserve_hard_surface"]["feature_angle"],
                loaded["preserve_hard_surface"]["smoothing_iterations"],
                loaded["preserve_hard_surface"]["normals_angle"],
            ),
            expected["preserve_hard_surface"],
        )

    def test_safe_repair_preserves_bounds_and_components(self) -> None:
        source = fixture_mesh()
        repaired = processor.repair_mesh(source)
        np.testing.assert_allclose(repaired.bounds, source.bounds, atol=1e-12)
        self.assertEqual(processor.positional_component_count(repaired), 2)

    def test_normals_only_has_no_vertex_movement(self) -> None:
        source = fixture_mesh()
        repaired = processor.repair_mesh(source)
        params = processor.resolved_params(
            EXTENSION_DIR, {"preset": "normals_only"}
        )
        for component in processor.connected_components(repaired):
            polished, report = processor.polish_component(component, params)
            np.testing.assert_allclose(
                polished.vertices, component.vertices, atol=1e-12
            )
            self.assertEqual(report.effective_iterations, 0)
            self.assertEqual(report.displacement, 0.0)

    def test_standard_polish_respects_safety_envelope(self) -> None:
        source = fixture_mesh()
        repaired = processor.repair_mesh(source)
        params = processor.resolved_params(
            EXTENSION_DIR, {"preset": "standard_polish"}
        )
        polished = []
        for component in processor.connected_components(repaired):
            result, report = processor.polish_component(component, params)
            polished.append(result)
            self.assertLessEqual(report.displacement_percent, 1.500001)
            self.assertLessEqual(report.dimension_change_percent, 3.000001)
            self.assertLessEqual(
                report.effective_iterations,
                report.requested_iterations,
            )
            np.testing.assert_allclose(
                processor.vertex_centroid(result),
                processor.vertex_centroid(component),
                atol=processor.component_diagonal(component) * 1e-9,
            )
        combined = processor.concatenate_components(polished)
        self.assertEqual(processor.positional_component_count(combined), 2)

    def test_scene_hierarchy_and_transforms_are_preserved(self) -> None:
        scene = trimesh.Scene()
        transform = trimesh.transformations.rotation_matrix(
            np.radians(23.0), [0.0, 1.0, 0.0]
        )
        transform[:3, 3] = [2.0, -1.0, 0.5]
        scene.add_geometry(
            fixture_mesh(),
            node_name="WallNode",
            geom_name="WallGeometry",
            transform=transform,
        )
        before = processor.geometry_node_snapshot(scene)
        copied = scene.copy()
        copied.geometry["WallGeometry"] = processor.repair_mesh(
            copied.geometry["WallGeometry"]
        )
        self.assertEqual(processor.geometry_node_snapshot(copied), before)

    def test_end_to_end_exports_a_valid_glb(self) -> None:
        scene = trimesh.Scene(fixture_mesh())
        with tempfile.TemporaryDirectory() as directory:
            source_path = Path(directory) / "input.glb"
            source_path.write_bytes(scene.export(file_type="glb"))
            output_path, stats = processor.process({
                "input": {"filePath": str(source_path)},
                "params": {"preset": "normals_only"},
                "workspaceDir": directory,
                "tempDir": directory,
            })
            self.assertTrue(output_path.is_file())
            self.assertEqual(stats["connected_component_count"], 2)
            self.assertTrue(stats["transforms_preserved"])
            self.assertLessEqual(stats["maximum_bounds_change_percent"], 2.0)


if __name__ == "__main__":
    unittest.main()

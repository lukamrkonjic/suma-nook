from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

import numpy as np
import trimesh


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import processor


class ProcessorTests(unittest.TestCase):
    def test_rounded_box_is_finite_and_has_expected_triangle_count(self) -> None:
        mesh = processor.rounded_box_local(
            np.asarray([2.0, 1.0, 0.6]),
            bevel_radius=0.078,
            bevel_segments=3,
        )
        self.assertTrue(np.isfinite(mesh.vertices).all())
        self.assertEqual(len(mesh.faces), 156)
        self.assertTrue(mesh.is_winding_consistent)
        self.assertTrue(np.allclose(
            mesh.extents,
            [2.0, 1.0, 0.6],
            atol=1e-8,
        ))

    def test_reconstruction_keeps_component_center_and_extents(self) -> None:
        source = trimesh.creation.icosphere(subdivisions=2, radius=0.5)
        source.apply_scale([1.3, 0.7, 0.45])
        source.apply_translation([2.0, -3.0, 4.0])
        rebuilt = processor.reconstruct_component(
            source,
            component_index=3,
            dimension_percentile=98.0,
            bevel_ratio=0.13,
            bevel_segments=3,
            asymmetry_amount=0.025,
            dimension_floor=1e-5,
        )
        self.assertTrue(np.allclose(
            rebuilt.bounds.mean(axis=0),
            source.bounds.mean(axis=0),
            atol=1e-8,
        ))
        self.assertTrue(np.allclose(
            rebuilt.extents,
            source.extents,
            atol=1e-8,
        ))

    def test_presets_match_documented_values(self) -> None:
        soft = json.loads(
            (ROOT / "presets" / "soft_stone_wall.json").read_text()
        )
        chunky = json.loads(
            (ROOT / "presets" / "chunky_low_poly.json").read_text()
        )
        self.assertEqual(soft["bevel_ratio"], 0.13)
        self.assertEqual(soft["bevel_segments"], 3)
        self.assertEqual(soft["asymmetry_amount"], 0.025)
        self.assertEqual(chunky["bevel_ratio"], 0.08)
        self.assertEqual(chunky["bevel_segments"], 2)
        self.assertEqual(chunky["target_face_count"], 12000)

    def test_soft_wall_source_fixture_when_available(self) -> None:
        source_path = Path(r"C:\Users\Luka\Downloads\stone-wall.glb")
        if not source_path.is_file():
            self.skipTest("Local wall fixture is not available.")
        mesh, _material, raw_count = processor.load_input_mesh(source_path)
        repaired = processor.repair_mesh(mesh)
        components, welded_count = processor.semantic_components(repaired)
        kept, removed = processor.filter_fragments(
            components,
            remove_small_fragments=True,
            minimum_relative_volume=0.005,
        )
        self.assertEqual(raw_count, 193)
        self.assertEqual(welded_count, 2)
        self.assertEqual(len(components), 88)
        self.assertEqual(removed, 65)
        self.assertEqual(len(kept), 23)


if __name__ == "__main__":
    unittest.main()

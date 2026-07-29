"""Build the snow surface layer from Luka's generated snow.

The shared surface-extraction pipeline samples the original upper snow shape,
regularizes it into a tileable height field, applies a deliberately strong
low-frequency polish, compresses the relief, and exports a replaceable surface
that the runtime mounts on the shared structural tile base.

Run from the repository root with Blender 5.x:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_snow_tile.py
"""

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import process_sand_tile as processor

processor.SOURCE = (
    processor.ROOT
    / "art_source"
    / "imported"
    / "snow_tile"
    / "snow_tile_source.glb"
)
processor.OUTPUT = (
    processor.ROOT
    / "assets"
    / "3d"
    / "reworked"
    / "tile_layer_surface_snow.glb"
)
processor.EXPECTED_SOURCE_SHA256 = (
    "F200BA1D6B64B7055F00616831FAC667850E12D64D1ABF1E8E32E861BA79C2C4"
)
processor.ASSET_LABEL = "snow"
processor.MATERIAL_NAME = "snow_top"
processor.CAP_OBJECT_NAME = "snow_cap"
processor.CAP_MESH_NAME = "heavily_smoothed_source_snow_cap_mesh"
processor.REPORT_PREFIX = "SNOW_TILE_SURFACE_REPORT="
processor.PALETTE = {
    "snow_top": "F1ECE2",
}

# Snow should read as a soft blanket, not the faceted generated source.
processor.EDGE_BLEND_FRACTION = 0.18
processor.INTERIOR_BASE_HEIGHT = 0.004
processor.RELIEF_AMPLITUDE = 0.105
processor.RELIEF_EXPONENT = 0.92
processor.TAUBIN_ITERATIONS = 8
processor.GAUSSIAN_PASSES = 3
processor.CONTOUR_SMOOTHING_PASSES = 5
processor.CONTOUR_SMOOTHING_BLEND = 0.72
processor.CONTOUR_SAMPLE_SPACING = 1.50
processor.SMOOTH_ANGLE_DEG = 60.0


if __name__ == "__main__":
    processor.main()

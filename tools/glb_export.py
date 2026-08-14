"""Export a glb the way the source authored it, instead of the way Blender likes.

glTF has no per-face normals. When a mesh is flat shaded, the exporter has to
give every triangle its own three corners, so a welded model comes out with its
vertices split -- and a model that arrives welded and leaves split reads as
visibly jagged next to the file it came from.

Measured on the wardrobe: `wardrobe.glb` stores POSITION and TEXCOORD_0 and NO
NORMAL, which is what keeps it at 906 vertices over 1000 faces. Simply importing
it into Blender and exporting it straight back out returned 3000 vertices. The
asset pipeline re-exports four times (split doors, ground, merge states,
recolour), so that split compounded long before the model reached the game.

A file without normals is not missing information -- it is delegating. Godot
generates normals on import, and Suma then applies its own `model_smoothing`, so
the shading is the player's setting to make rather than something baked in here.

So: if the source authored normals, keep writing them; if it did not, do not
start. That leaves the vertex count and the shading exactly where the artist
left them, through any number of intermediate steps.
"""

from __future__ import annotations

from pathlib import Path

import bpy


def scene_authors_normals() -> bool:
    """True when the imported scene carries normals of its own.

    Blender's glTF importer only builds a custom split-normal layer when the
    file actually supplied one, so this distinguishes an authored-normals source
    from one that leaves shading to the renderer.
    """
    for item in bpy.context.scene.objects:
        if item.type == "MESH" and item.data.has_custom_normals:
            return True
    return False


def export_selected(output: Path, *, write_normals: bool) -> None:
    """Exports the current selection as a glb, matching the source's normals."""
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_normals=write_normals,
    )

"""Export a glb with the shading the game expects to receive.

Suma decides shading at runtime: `AssetEditLibrary._smoothed_mesh` blends each
surface's OWN normals toward averaged ones by the asset's `model_smoothing`, so
at 0.0 the mesh shows exactly the normals the file shipped. That makes the
authored normals the crisp end of the range the player is adjusting.

Which is why a glb must carry them. glTF has no per-face normals, so flat
shading costs a vertex split -- and skipping normals to keep a model welded like
its source backfires: Godot then generates its own, averaged across every hard
edge. Measured on the wardrobe, that produced a rounded, detail-free cabinet
whose door panels had vanished, and `model_smoothing = 0` could not bring them
back because there was nothing sharper to blend from. Every other shipped asset
carries NORMAL; the wardrobe was the exception, and it looked like it.

So: always write normals, and make the shading uniform first. Repeated passes
otherwise accumulate a custom split-normal layer and leave a scatter of faces
smoothed while their neighbours are flat -- the wardrobe reached the game with
73 such faces -- which reads as the model being subtly, unevenly wrong.
"""

from __future__ import annotations

from pathlib import Path

import bpy


def flatten_shading(meshes: list) -> None:
    """Puts every face on flat shading, clearing any custom normal layer.

    This is not a style choice applied on top of the art -- it is the zero point
    of the runtime smoothing control, and the state the source models are
    authored in. Anything softer is the player's to dial in.
    """
    for mesh_object in meshes:
        previous = bpy.context.view_layer.objects.active
        bpy.ops.object.select_all(action="DESELECT")
        mesh_object.select_set(True)
        bpy.context.view_layer.objects.active = mesh_object
        # Blender 4.5 has no free_normals_split; shade_flat clears the custom
        # split-normal layer as well as setting the faces flat.
        bpy.ops.object.shade_flat()
        bpy.context.view_layer.objects.active = previous
        for polygon in mesh_object.data.polygons:
            polygon.use_smooth = False
        mesh_object.data.update()


def export_selected(output: Path) -> None:
    """Exports the current selection as a glb, normals included."""
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_normals=True,
    )

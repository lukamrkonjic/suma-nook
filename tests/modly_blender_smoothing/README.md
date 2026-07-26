# Modly → Blender smoothing experiment

Disposable, isolated test of two user-supplied Modly GLBs:

- `source_copies/tree1_original.glb`
- `source_copies/tree2_original.glb`

The copies are used so the originals on the desktop are never modified.
Nothing in this folder is registered with the game or production asset
pipeline. Delete this entire directory to remove the experiment.

Run with Blender 5.2:

```powershell
& 'C:\Software\Blender\blender.exe' --background --factory-startup `
  --python '.\tests\modly_blender_smoothing\run_smoothing_test.py' -- `
  '.\tests\modly_blender_smoothing'
```

Generated output:

- `renders/*_before.png`, `*_after.png`, `*_comparison.png`
- `renders/*_reimport.png`
- `exports/*_smooth_test.glb`
- `blender_scenes/*_smooth_test.blend`
- `reports/inspection_report.json`
- `godot_renders/modly_trees_moss_tiles.png`
- `godot_renders/tree1_moss_tile.png`, `tree2_moss_tile.png`

`GodotPreview.tscn` direct-loads only the two experimental exports. It places
tree1 at 2.0 m and tree2 at 2.2 m on plain moss tiles, compensating at runtime
for their centered origins. It does not register them as game assets.

`ActualWorldPalettePreview.tscn` wraps the real playable `Main` scene and adds
the same trees on temporary moss-tile extensions. `palette_repaint_adapter.gd`
uses the imported atlas only to distinguish foliage from wood and preserve
surface value/detail. The shader replaces the preview hues with the same
pine/leaf/wood ramps used by Suma Nook's live material library and retains the
normal map. It does not modify the GLBs, textures, asset database, normal import
settings, game save, or production scene.

This experiment is not production content and must not be committed as final
game assets.

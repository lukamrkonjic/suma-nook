# Stylized pyramid tent source

`stylized_pyramid_tent_source.glb` is the untouched authored deliverable copied
from:

`C:\Dev\img2godot-1.4.0\deliverables\stylized_pyramid_tent\export\stylized_pyramid_tent.glb`

The production visual keeps the existing `prop_shelter` asset ID so recipes,
placements, and saves remain stable. Rebuild only this asset with:

```powershell
C:\Software\Blender\blender.exe --background --factory-startup `
  --python art_source\blender\process_stylized_pyramid_tent.py
```

The processor:

- preserves the source file and verifies its SHA-256;
- scales the full footprint to 1.50 m for a centered 1.70 m tile;
- grounds the model at zero elevation;
- maps canvas, door, trim, and wood to semantic game-palette materials;
- exports `assets/3d/reworked/prop_shelter.glb`.

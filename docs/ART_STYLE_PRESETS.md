# Art style presets

The checked-in world style is selected by `data/art_styles.json`. The current
default is `garden_galaxy_reference`. It is reconstructed from the supplied
Garden Galaxy technical audit, exported material evidence, and Suma's original
graphics-lab (`7bcb6175`) plus crisp-studio (`e1fbcb67`) passes. It does not
derive from the later pixel/olive art direction.

The preset owns these coordinated choices:

- the confirmed 15-degree perspective lens, 40-unit gameplay distance, and
  40-degree downward view;
- the serialized key light and ambient hemisphere colors;
- the old 8192 shadow atlas, point sun, crisp 0.6 filtering, tight stable
  coverage, and high-definition contact AO;
- native-resolution 8x MSAA with painterly pixels and temporal blur bypassed;
- the reference linear-to-PPv2 camera grade and bounded bloom;
- a quieter sage-led semantic palette, plus painted albedo variation standing
  in for GG's texture maps before PBR lighting;
- the reference-derived water response.

It does not copy Garden Galaxy meshes or textures into Suma. The supplied
private evidence remains outside the repository; only measured values and the
independently reconstructed semantic palette are checked in.

To run the previous look without editing the project:

```powershell
$env:SUMA_ART_STYLE='baseline'
godot --path C:\Dev\suma-nook
```

Or pass `--art-style=baseline` after Godot's `--` user-argument separator.
Changing `active` in `data/art_styles.json` changes the checked-in default.
New directions should be sibling presets so comparisons stay deterministic.

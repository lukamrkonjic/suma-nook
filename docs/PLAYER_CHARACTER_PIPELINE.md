# Player character pipeline

Superseded: the player character is now built by the modular character
system. The authoritative documentation lives at
`characters/README_CHARACTER_PIPELINE.md`.

## Summary

- Canonical Blender source: `art_source/characters/suma_character_master.blend`
  (deterministic builder `art_source/characters/build_character_master.py`).
- Runtime mannequin: `assets/3d/reworked/player_male_mannequin.glb` —
  one skinned `PlayerMaleBody`, the 34-bone Mixamo skeleton contract in a
  strict T-pose rest, and the authored `idle_relaxed` loop.
- Face and hair are rigid part GLBs under `assets/characters/parts/`,
  assembled at runtime by `CharacterAssembler` from
  `assets/characters/presets/default_male_appearance.tres`.
- The previous generated character (`assets/3d/reworked/player_male_rigged.glb`,
  `art_source/player_male/`) is preserved untouched for history.

## Rebuild and validation

```powershell
& "C:\Software\Blender\blender.exe" --background --factory-startup `
  --python "C:\Dev\suma-nook\art_source\characters\build_character_master.py"

& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "C:\Dev\suma-nook" --import

& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "C:\Dev\suma-nook" `
  --script "res://tests/player_mixamo_probe.gd"
```

`tests/player_male_capture.tscn`, `tests/character_lab_capture.tscn`, and
`tests/player_ingame_review.tscn` record review screenshots under
`artifacts/`.

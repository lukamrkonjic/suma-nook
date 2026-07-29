# Player character pipeline

The production player is generated from
`C:\Users\Luka\Downloads\player_male.glb` by
`art_source/player_male/build_player_male.py`.

## Authored sources and runtime asset

- Source SHA-256:
  `9734E3420CF456AAF68D6A4851B58ED86444B48D200B118DED2993F1B8F7B3AC`
- Animator source: `art_source/player_male/player_male_rigify.blend`
- Runtime asset: `assets/3d/reworked/player_male_rigged.glb`
- Active profile: `assets/player/current_player_profile.tres`
- Runtime size: 13,258 vertices and 26,412 triangles.

The Blender file contains a fitted Rigify metarig and generated control rig.
The exported gameplay skeleton retains the established 34 Mixamo bone names,
so the existing idle, walk, fishing, and chopping animations remain reusable.
External animation track paths are rebound to the live `Skeleton3D` at
runtime; they do not depend on a particular Blender node hierarchy.

## Modular head contract

`PlayerMaleBody` is the only deforming/skinned mesh. The following rigid
modules export in the reviewed model-space pose:

- `EyeL`, `EyeR`
- `Nose`
- `Brows`
- `Moustache`
- `Mouth`
- `Hair00` through `Hair03`

Before the first animation frame, `PlayerVisual` creates one
`BoneAttachment3D` named `PlayerHeadSocket` on `mixamorigHead`. It reparents
all ten modules while preserving their reviewed global transforms. This
produces stable head-local offsets without glTF parent-inverse ambiguity and
keeps features aligned during idle, walking, turning, scaling, and animation
blending.

The character creator tints skin, hair, brows, moustache, eyes, and mouth from
the active `CozyPalette`. Exactly one hairstyle is visible. Equipping a head
item hides all hairstyle meshes while leaving the facial features intact.

## Wardrobe compatibility

The old cowboy-vest bundle is deliberately ignored for this player. It was
fitted to the retired body and included an exposed-body clone, so attaching it
could restore obsolete character geometry. Body-slot visuals should remain
disabled until new garments are authored against `player_male_rigify.blend`.

## Rebuild and validation

```powershell
& "C:\Users\Luka\AppData\Local\Temp\codex-blender-4.5.4\blender-4.5.4-windows-x64\blender.exe" `
  --background --factory-startup `
  --python "C:\Dev\suma-nook\art_source\player_male\build_player_male.py"

& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "C:\Dev\suma-nook" `
  --script "res://tests/player_mixamo_probe.gd"
```

`tests/player_male_capture.tscn` records front, three-quarter, walk, palette,
and legacy-vest-suppression screenshots under
`artifacts/player_male_review/`.

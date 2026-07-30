# Female player body — first-pass integration

Source: `C:\Users\Luka\Downloads\player_female.glb`

Runtime output:

- `assets/3d/reworked/player_female_mannequin.glb`
- `assets/characters/body_profiles/body_female.tres`
- `assets/characters/presets/default_female_appearance.tres`

Animator source:

- `art_source/player_female/player_female_rigify.blend`

The source is normalized from its 1 m input convention to the male pipeline's
2 m authoring convention, then receives the same offline smoothing used by the
male body: Smooth factor **0.38**, **6 iterations**. The runtime GLB implements
the shared 34-bone Mixamo contract and embeds `idle_relaxed`; the `.blend`
retains the generated Rigify controls.

This is intentionally the initial rigging pass. Automatic weights, bone
placement, face sockets, and accessory sockets are ready for in-game use but
remain artist-tunable. The female body profile currently disables UV2 body
region masking, and its default preset contains no skinned clothing. Fit and
publish female clothing before enabling region masking or adding garments to
the preset.

Rebuild with Blender 4.5 LTS:

```powershell
blender --background --factory-startup --python art_source/player_female/build_player_female.py
```

Then run a Godot import pass and the focused checks:

```powershell
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/probe_female_character.gd
```

# Replaceable player asset pipeline

The moustached Mixamo character is a **testing character**, not final Suma
content. Its clothing, proportions, texture, and clips may all be replaced.
Gameplay code must not learn anything model-specific about it.

## Stable boundary

`PlayerController` and skills address semantic states (`idle`, `walk`,
`fish_cast`, and so on) through `PlayerVisual`. The authored model contract is
the single resource:

`assets/player/current_player_profile.tres`

That profile owns:

- the current GLB asset id and source paths;
- intended in-game height and model-facing correction;
- embedded idle, external walk, and semantic authored-action clips;
- locomotion/action transition durations, playback timing, and impact timing;
- required Mixamo-compatible bones and equipment mounts;
- the matte palette treatment applied only to the player.

The current profile has `testing_only = true`. Character creator colors and
clothing are intentionally not applied to this test mesh.

## Replacing the test character

1. Preserve the source model and animations in `art_source/`.
2. In Blender, inspect scale, origin, normals, skinning, pose, and deformation.
   Conservative smooth-by-angle is fine; do not smooth across intentional hard
   edges or change the silhouette just to make rigging easier.
3. Rig/animate with one consistent skeleton. An idle embedded in the model and
   separate Mixamo-compatible animation GLBs are supported.
4. Export the game model to `assets/3d/reworked/` or `assets/3d/final/`.
5. Extract locomotion and action clips to `assets/animations/`. The extractors
   and animation studio remove net hips/root X/Z travel automatically. They
   preserve vertical gait and cyclic horizontal sway, so loops close without
   looking frozen. For the current sources:

   ```powershell
   & "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
     --headless --path "C:\Dev\suma-nook" `
     --script tools/extract_player_action_animations.gd
   ```

   The action extractor keeps the reviewed cast segment, retains the complete
   fish-hold loop, and retains the chop's authored return/recovery.
6. Edit only `assets/player/current_player_profile.tres` for the model id,
   paths, dimensions, clips, bones, mounts, and material response.
7. Open `tools/player_animation_studio/`. It reads the current model and walk
   source paths from that same profile and automatically discovers
   `art_source/animation_sources/player_*.glb`, so it follows character
   replacements and exposes their action sources for inspection.
8. Run:

   ```powershell
   & "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
     --headless --path "C:\Dev\suma-nook" `
     --script tests/player_mixamo_probe.gd
   ```

9. Run unit and full-loop tests, then inspect the character under day, dusk,
   and rain lighting before approving it.

## Runtime guarantees

- Locomotion advances on the physics clock used by `CharacterBody3D`.
- Physics interpolation smooths the visible player between fixed ticks.
- State changes cross-fade once; `set_walk()` never restarts a playing clip.
- Repeating authored actions continue their active loop. Gameplay impact timing
  is mapped into the clip, so a chop completes its return stroke before the next
  swing rather than snapping or restarting at impact.
- Every embedded or externally installed rig animation is duplicated and made
  in-place at the player boundary. Future clips cannot move the gameplay body or
  snap backward when they loop.
- Imported materials are duplicated per player instance, then normalized by a
  palette shader. The GLB and its shared imported materials remain untouched.
- The player-specific treatment remains lit and shadowed; it does not use an
  unshaded overlay that would make the character look pasted into the world.
- Equipment follows profile bone mounts rather than hardcoded model nodes.

If the final character uses a non-Mixamo skeleton, update the profile and clip
retargeting/export step. Do not add skeleton-name checks to gameplay systems.

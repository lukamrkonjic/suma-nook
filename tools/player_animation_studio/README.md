# Suma Player Animation Studio

A small standalone Godot app for authoring animations on Suma's current player
profile. It is a deliberately reduced port of Imota's rig-editor animation workflow:
one player, one clip library, one bone inspector, one timeline, and Godot animation
export.

The studio is isolated from the game:

- it has its own `project.godot`;
- Suma never loads any studio script or export;
- it reads the current player, walk source, and `player_*.glb` action sources
  from the parent repository at startup;
- exports stay in this folder until explicitly reviewed and copied into the game;
- deleting `tools/player_animation_studio/` removes the entire utility.

## Run

Double-click `run.bat`, or:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" `
  --path "C:\Dev\suma-nook\tools\player_animation_studio"
```

Headless smoke test:

```powershell
.\test.bat
```

## Focused workflow

1. The model and walk source configured in
   `assets/player/current_player_profile.tres` load automatically. Action
   sources named `player_*.glb` in `art_source/animation_sources/` are
   discovered alongside them.
2. Pick `idle`, `walk`, `fish_cast`, `fish_wait`, `chop`, or import another
   Mixamo-compatible animation GLB.
3. Scrub the timeline and select a bone from either the timeline or the bone list.
4. Adjust the selected bone's local Euler rotation.
5. Insert/update a rotation key at the playhead.
6. Export the selected clip. The `.tres` is written to `exports/`.

The app edits an in-memory duplicate, never the source GLB. Imported animation GLBs
must use the same Mixamo bone names as the current player. Every loaded clip is
made in-place automatically: net hips/root X/Z travel is removed while vertical
motion and cyclic hips sway remain. **Normalize in-place** is an idempotent manual
check for a clip that was edited after import.

Preview playback runs on Godot's `AnimationPlayer` clock. The editor timeline
observes that clock; it does not repeatedly seek and reapply the pose each
frame. `walk`, `fish_wait`, and `chop` default to looping; the cast remains a
one-shot source for trimming/review.

The current character is test content. When it is replaced, update the central
profile rather than this app; the studio follows the profile paths on restart.

## What was intentionally left out

Imota's model registry, procedural pivot rig, sockets, armor fitting, equipment,
world targets, AI generation, save system, and gameplay runtime hooks were not
ported. The useful authoring ideas retained here are the shared clip preview,
single transport, bone/key selection, custom timeline, in-place cleanup, and
non-destructive export.

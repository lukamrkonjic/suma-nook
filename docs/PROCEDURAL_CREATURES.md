# Procedural Creatures — SDF Blend-Shell Character System

One JSON definition in, one seamless animated critter out. This is the
authority doc for the character tech introduced on
`codex/sdf-blend-shell-player`: the SDF blend-shell renderer, the generic
any-body-plan creature core, and the adapters that drive the playable
character and the owl mascot with it.

## Why it looks seamless (the one-paragraph version)

Characters are ordinary capsule/sphere meshes merged into **one draw call**.
The vertex shader (`assets/materials/sdf_blend_shell.gdshader`) snaps every
vertex onto the smooth-min SDF surface of all shapes combined, so where
shapes overlap their meshes converge onto the same blended surface and the
seams cease to exist. Normals come from the SDF gradient (lighting flows
continuously across joints) and colors blend by SDF proximity (soft
gradients at every join, for free). No raymarching, no skinning — cost is
per-vertex, mobile-friendly, capped at **16 shapes** per character.

The look is **flat cel**: ambient is disabled and replaced with a uniform
emission fill, specular is zero, lighting is two hard toon bands, and part
colors cross over inside a narrow band (35 % of the geometry blend) so
every part reads as a solid painted color. Face/belly decals are unshaded
stickers.

Robustness tricks living in the shader:

- **Tuck-under-skin**: overlap regions are covered by the charts of every
  shape that blends there, which z-fights as faint creases. Charts whose own
  shape is not the closest surface owner sink ~5 mm under the skin along the
  SDF normal (wide ramp so the sink wall never reads as a ledge).
- **Toon light floor**: the custom `light()` bands never drop below a 0.58
  base, so characters stay readable when backlit.
- **Specular kept at 0.05** — higher values turn small accent-colored parts
  (feet) into neon glow balls under warm keys.

## The generic core

`scripts/creatures/procedural_creature.gd` (`ProceduralCreature`) builds and
animates any of these **body plans** from JSON:

| plan | legs | animation |
|------|------|-----------|
| `legged` | 1, 2 (biped, 2-seg IK legs), 4 (diagonal trot), 6 (tripod) | reactive stepping gait |
| `hopper` | 2 (or 1 for a pogo) | crouch-launch hop cycle, counterweight tail, tucked paws |
| `flyer`  | 2 stubby | folded↔spread 2-segment wings, flap/bank/tuck, hover bob |

Plus 0–3 **arms** (third arm grows from the back), 0–2 **ears** (styles:
`up`, `side`, `tuft`; a single ear centers itself as an antenna), 0–3 chained
**tail** segments (droop 0=perky..1=dragging, ground-clamped), belly patch,
and a **face style**: `critter`, `owl`, or `pup`. Faces blink; surprise
impulses widen eyes.

**Driver contract** — the core is deliberately controller-agnostic. Owners
call, every physics tick:

```gdscript
var state := ProceduralCreature.MotionState.new()
state.local_velocity = ...   # creature-local m/s
state.grounded = ...
state.flying = ...           # flyer states only
state.yaw_rate = ...         # rad/s, drives banking
state.look_target = ...      # local-space point or null
creature.advance(delta, state)
```

plus `notify_landed(strength)`, `notify_takeoff()`, `notify_surprise()` on
transitions. Existing drivers:

- `scripts/player/procedural_critter_player.gd` — playable character
  (reads `CharacterBody3D` velocity/floor; flag
  `procedural_critter_player_enabled`).
- `scripts/characters/owl/procedural_owl_mascot.gd` — owl mascot (maps
  `PigeonMascotController.MovementState`; flag
  `procedural_owl_mascot_enabled`; the rigged pigeon stays intact for the
  Clothing Lab, hidden via `attach_procedural_visual`).
- Review stubs in `tests/` drive creatures with synthetic MotionStates.

## Definition schema (data/creatures/*.json)

~15 lines defines a creature; every key has a sensible default. The stable
starts at 36 definitions: `nook_kit.json` (the playable chibi fox),
`nook_owl.json` (the mascot flyer), ~20 real-animal critters (cat, fox,
fawn, bear, elephant, pig, sheep, cow, pony, mouse, hedgehog, turtle,
raccoon, panda, penguin, duck, chick, rabbit, frog, bee, ladybug), and a
crew of whimsical monsters (slime with no legs, one-legged pogo imp,
three-armed goblin, wisp ghost, dragonet, shroomling, cactus kid, yeti).

Key groups: `palette` (body/body_light/limb/foot/wing/face/belly/accent/ink/
ear — missing keys fall back to derived tints), `torso` (length, radius,
optional height override, optional `stance: "upright"|"horizontal"`, pitch
degrees, belly toggle), `head` (radius, offset, face style, `stabilize`
0..1 — owls use 0.62 for the level-head party trick), `legs` (count,
length, segments 1–2, stance, radius, foot_radius, `foot_balls`), `arms`,
`wings` (length, flap_hz, flap, bank, pitch, hover_bob), `ears`, `tail`,
`gait` (reference_speed, cadence, stride, step_lift, body_bob, lean,
waddle, hop_rate, hop_lift), `juice` (squash, head_lag, head_snap,
ear_spring, tail_drag, outline).

**Budget rule**: torso + head + legs×segments + feet + arms + wings(4) +
tail segments + ears ≤ 16. `build()` asserts it;
`tests/creature_core_contract_test.gd` builds every definition headless.

## Overlay (face/belly) rendering rules — learned the hard way

- Small decals (eyes, glints, beak, nose, cheeks, brows) are **unshaded**
  stickers; big patches (muzzle, facial discs, belly) keep shading plus an
  emission floor (0.38) matching the shell's toon base. Standard-lit decals
  go muddy brown whenever the key light is behind the character.
- All overlays `disable_receive_shadows`.
- Embed patches at least ~40 % into the skin and yaw side elements
  (cheeks, disc halves) so their rims hug the head sphere — flat proud
  discs read as goggles from the side.

## Clothing & equipables

`scripts/creatures/creature_outfit.gd` (`CreatureOutfit`) dresses any
creature from a tiny JSON in `data/outfits/`: slots `hat` (cap | straw |
cone), `shirt` (tee | scarf), `pants` (shorts), `shoes` (boots), `held`
(fishing_rod | stick), each with `color`/`accent`. Garments are unshaded
primitive clusters re-seated on the creature's live **pose anchors**
(head, torso, per-arm shoulder/hand, per-leg hip/knee/foot) via the
`pose_advanced` signal, so they ride squash, waddle, hops, and flight on
every body plan; slots skip gracefully when a plan lacks legs or arms.

Wear it three ways: an `"outfit"` key in the creature JSON (the player's
`nook_kit` wears `cozy_scout`), `ProceduralCreature.set_outfit(path)` at
runtime, or `ProceduralCritterPlayer.equip_outfit(path)` /
`clear_outfit()` on the player. `held_tip_world()` exposes the rod tip
for future fishing-line wiring. The contract test dresses every creature
in every outfit; `tests/creature_outfit_review.tscn` renders the fashion
show.

## Review scenes & tests

```
# structural contracts (headless)
Godot --headless --path . --script tests/sdf_blend_shell_contract_test.gd
Godot --headless --path . --script tests/creature_core_contract_test.gd

# screenshot reviews (windowed, self-quitting; pass -- --shot-dir=<dir>)
Godot --path . res://tests/sdf_blend_shell_review.tscn      # player
Godot --path . res://tests/sdf_owl_review.tscn              # owl states
Godot --path . res://tests/creature_menagerie_review.tscn   # all body plans
```

Review-stage note: characters are ~0.35 m; use
`directional_shadow_max_distance ≈ 6–8` with `shadow_blur ≈ 3` or the key
light acne-stripes / chunk-shadows them.

## Adding a creature

1. Copy the closest JSON in `data/creatures/`, tweak palette/proportions.
2. Instance a `ProceduralCreature`, `build_from_path(...)`, feed it a
   MotionState each tick (or reuse an existing driver).
3. Run the contract test; eyeball it in a review scene.

That's the whole point: a new creature is data, not code — an LLM can emit
endless valid critters that come out seamless and hand-sculpted-looking.

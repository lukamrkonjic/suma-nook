# Asset brief — character_hero (final player character)

- **Asset ID / export**: `character_hero` → `assets/3d/final/character_hero.glb`
- **Purpose**: replaces the procedural proxy in `scenes/player/` as the player's body.
- **Silhouette**: compact keeper, ~3 heads tall (~1.35 m), big round head, chunky
  mitten-ish hands, tapered stubby legs, bell-shaped tunic. Friendly, genderless base.
- **Dimensions**: height 1.35 m, shoulder width ~0.55 m (tile = 2.0 m).
- **Palette**: skin tones from palette `skin_a..d`; tunic uses `fabric` slot; boots
  `dark_wood`; hair uses `hair` slot (recolored at runtime).
- **Material slots**: `skin`, `hair`, `fabric`, `fabric_accent`, `dark_wood`, `eyes`.
  Flat colors only; eyes are two dark rounded quads, no texture.
- **Separate parts**: hair mesh per style (hair_00..hair_03 as separate objects sharing
  the rig head bone); tunic; body. Equipment attaches to sockets, not baked in.
- **Sockets**: `hand_r` (tools/weapons), `hand_l`, `head` (hats), `back` (cape/rod
  stowed), `chest_fx` (level-up glow).
- **Collision**: capsule r 0.3 h 1.2 (already configured in Godot; do not export).
- **Animations**: idle, walk, interact, fish_cast, fish_wait, fish_catch, chop, attack,
  dodge, hit, celebrate. 24 fps, loops marked. Same names as proxy states.
- **Triangle budget**: ≤ 6,000 body+hair.
- **Godot target**: `scenes/player/player.tscn` (`BodyMount` node).
- **Modly prompt**: "cute chunky low-poly fantasy keeper character, 3 heads tall, round
  head, simple face with two oval eyes, bell-shaped tunic, rounded boots, matte flat
  colors, soft bevels, cozy diorama game style, T-pose, no outlines, no texture detail"
- **Cleanup/Acceptance**: per `_TEMPLATE.md`; MUST animate the same state names the
  proxy exposes so `player_visual.gd` needs zero changes.

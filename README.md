# Suma Nook

A walkable pixel-forest worldbuilding prototype made in Godot 4.6.

You create a tiny forest keeper and wake in a square clearing made from exactly nine tiles.
Woodland wisps bring Forest Light. Each light lets you grow one new cardinal-adjacent tile,
so the world expands according to the paths and shapes you choose. Growth milestones unlock
pixel-art plants, furniture, lanterns, and landmarks for your woodland pack.

## Play loop

1. Name and customize your character's skin, hair, and outfit.
2. Walk the full 3×3 starting world with WASD, arrow keys, or by clicking a tile.
3. Click a glowing woodland wisp to gather one Forest Light. Wisps use a large invisible
   click target so the small sprite is easy to collect.
4. Press **G** or **Grow Tile**, then click an empty space sharing a full side with the world.
5. The placement creates a randomized moss, path, or stone tile and charges one light only
   after the placement succeeds.
6. At 3, 6, 10, 15, and 22 grown tiles, new forest decorations enter the pack.
7. Place, rotate, move, store, and recycle unlocked decorations as the nook becomes a large
   personal adventure space.

The old Bloomforge is retained only as a compatibility seam for early prototype tests. It is
not part of the player-facing loop.

## Pixel-art direction

- All characters, wisps, trees, bushes, flowers, props, and UI are hand-authored at runtime
  on small pixel grids with one shared woodland palette.
- Textures use nearest filtering. There is no screen-space pixelation shader.
- Ground remains a thick isometric diorama block, but its top and sides use hard-edged pixel
  patterns and square shadows.
- A deep forest frame, tiled moss floor, fireflies, hard shadows, Greenwood, Firefly Dusk,
  and Moss Rain make the starting clearing feel lush before the player expands it.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Walk one connected tile |
| Left click tile | Pathfind to that tile |
| Left click wisp | Gather Forest Light |
| G / Grow Tile | Start one adjacent tile growth |
| Left click while placing | Confirm tile or decoration |
| Right click / Escape | Cancel placement or close a panel |
| Mouse wheel | Zoom |
| Middle-drag | Pan |
| Q / E | Rotate camera |
| R | Rotate a held decoration |
| Delete / Backspace | Store held decoration |
| Cmd/Ctrl-Z | Undo |
| Cmd/Ctrl-Shift-Z | Redo |
| Cmd/Ctrl-S | Save |

## Run

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/luka/Documents/dev/suma-nook
```

## Validate

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --path /Users/luka/Documents/dev/suma-nook \
  res://tests/test_runner.tscn

/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --path /Users/luka/Documents/dev/suma-nook \
  res://tests/full_loop_runner.tscn
```

Current result: **130 deterministic assertions** and **46 full-scene assertions** pass.

## Visual captures

- [Character creator](docs/suma_creator.png)
- [Nine-tile beginning](docs/suma_initial.png)
- [Expanded pixel forest](docs/suma_expanded.png)

## Important implementation files

- `scripts/player_character.gd`: custom appearance, click pathing, cardinal movement, save state.
- `scripts/forest_progression.gd`: Forest Light cost, tile palette, growth count, milestones.
- `scripts/pixel_art.gd`: all runtime-authored pixel textures and shared palette.
- `scripts/visual_factory.gd`: pixel tiles, sprite props, shadows, placement visuals.
- `scripts/world_builder.gd`: deep forest frame, atmosphere, weather, and lighting.
- `scripts/main.gd`: character creator, walking, wisp collection, tile-growth transaction.

## Save note

This redesign intentionally uses save schema version 3 and a new
`user://suma-nook-save.json` path. It does not load the old Tilegarden prototype save.

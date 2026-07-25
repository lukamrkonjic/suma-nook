# Design pillars — Suma Nook: living world progression

**Pitch:** a cozy RPG-builder where you level skills to earn the materials and land pieces
used to physically grow and beautify your own miniature world, one handcrafted tile at a
time.

**Fantasy:** "I begin with almost nothing. Everything I do becomes part of my world."

Every feature must serve at least one player promise: expand the world, beautify it,
unlock a new interaction, visibly improve the character, discover/reclaim something
memorable, or gain creative possibilities. If it only makes a number go up, it's out.

## Pillars

1. **The player is the main character.** A visible, customizable character walks, fishes,
   chops, fights, and inhabits the world. Building mode elevates the camera; it never
   removes the character.
2. **The world starts small.** Exactly nine cells in a composed, pretty 3×3 square — a
   complete tiny home, not an unfinished level.
3. **The world grows through progression.** Land comes from skills, materials, and
   discoveries. Skills are how the world comes into existence.
4. **The player places the world.** The game curates which pieces exist; the player
   authors where everything belongs.
5. **Curated pieces, composer not CAD.** Handcrafted tiles and chunky building prefabs
   that look good together. No voxel spam, no wall-stud alignment.
6. **Beauty and productivity align.** Resource capacity lives in tile anchors with
   limited sockets; upgrades beat spam; moving is free; early tiles upgrade in place.
   The efficient world and the beautiful world are the same world.
7. **RNG creates anticipation, never softlocks.** Seeded streams, tutorial guarantees,
   pity counters, duplicate → Pattern Dust, deterministic crafting path to every
   essential. No monetized randomness, ever.
8. **Combat serves world creation.** Fights exist to reclaim ruins into peaceful,
   ownable places and to earn visible gear. Enemies never invade or destroy the home.
9. **Early work stays valuable.** The starting nine tiles can remain the heart of a
   late-game world.
10. **Low friction.** One interaction starts a skill; auto-repeat continues it. No
    click-taxes, no maintenance chores, no storage warehousing.

## Anti-pillars (hard "no" list)

Giant empty sandbox · survival crafting · farming spreadsheet · colony sim · visitor
management · NPC relationship sim · city management · MMO · auction house · live service
· daily chores · base defense · pure idle · unrestricted voxels · clone of any reference.

## Visual pillar (mandatory override)

The game looks like the supplied Garden Galaxy references: orthographic cozy low-poly
diorama, cream day background, warm upper-left key light, soft grounded shadows, chunky
beveled silhouettes, flat-color matte materials, geometry-not-texture detail, warm
emissive fire. Full analysis in `docs/STYLE_BREAKDOWN.md`; acceptance gates in
`docs/VISUAL_FIDELITY_CHECKLIST.md`. Continuous free character movement is a hard
requirement — the grid is for construction, never for locomotion.

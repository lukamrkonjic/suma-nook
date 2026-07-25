# MVP scope

The MVP proves the full identity: character → 3×3 world → fishing → parcel → tile
expansion → woodcutting → crafting/building → horizon landmark → combat reclaim →
visible gear → collection → save/load. Acceptance flow: see the 43-step list in the
brief; automated coverage in `tests/`, manual notes in `MVP_REPORT.md`.

## Content budget (locked)

- 1 customizable character (body tone, hair style ×4, hair color, eyes, outfit palette,
  name) + 1 starter outfit
- Equipment: fishing rod, basic axe, improved axe, guardian sword, explorer set
  (head+body), rare landmark cape — all visible on the character
- Skills: Fishing + Woodcutting fully playable; Mining defined as data only
- 3 terrain families (Home Meadow, Living Grove, Stonebound) × ~5 variants = 15 tiles
- 12 building/decoration pieces in one woodland kit (cottage, bench, lantern, fence,
  gate, path, planter, sign, arch, chest, dock, campfire) + reclaimed-ruin piece
- 1 landmark: the Overgrown Watchpost (silhouette → hostile → reclaimed states)
- 1 enemy family (thornlings: stalker, lobber) + 1 guardian
- 3 reward reveal sequences (skill discovery toast, parcel three-card reveal, guardian
  reward)
- Complete save/load (schema v1), collection book, generated audio, debug panel

## Explicitly deferred

Visitors/residents (metadata hooks only) · cooking economy · transmog UI (appearance
unlock data exists) · seasons · streaming/chunk unload (boundaries prepared) · additional
skills beyond Mining stub · multi-cell tiles (data supports footprints > 1×1; MVP ships
1×1 only) · gamepad polish (input map includes analog axes) · Tier C hero assets (styled
proxies + briefs ship instead).

## Tuning targets

- First catch < 30 s from gaining control; first parcel ≤ 5 catches (guaranteed);
  first placed tile < 4 min; watchpost silhouette appears at 4 placed tiles; full loop
  ≤ ~25 min relaxed play.
- 60 FPS on the dev Mac at 1920×1080 with the expanded (~20 tile) world.

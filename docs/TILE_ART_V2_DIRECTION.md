# Tile Art V2 — binding art direction (GG construction reboot)

This document is the AUTHORITY for the five prototype tiles. It records the
user's final direction (2026-08-03) and the reverse-engineering of the
Garden Galaxy reference. Every earlier V2 visual solution (rounds 1–8:
sculpt-field pudding, sparse clutter, assembly eggs, smooth-toy minimal) is
REJECTED. Do not derive from them.

## The user's rejection criteria (verbatim intent)

Rejected on sight: identical rounded soap-bar bases; inflated spheres/
domes/fondant; one primitive centred per tile; mostly-empty tiles; melted
edges; anything smoother and simpler than the reference; missing
medium-scale detail; another variation of previous output.

FORBIDDEN: spheres, ellipsoids, capsules, simple domes, central mounds,
identical base blocks, extreme smoothing, inflated SDF blobs, perfectly
rounded square corners, one primitive per material.

REQUIRED shape language: broad flat and gently curved planes; chunky
polygonal forms; controlled bevels (moderate, never melted); MEDIUM-SIZED
OVERLAPPING PIECES; asymmetrical authored compositions; multiple height
levels; distinct top and side materials; slightly irregular edges; smooth
normals over deliberately modelled geometry. Soft-edged but visibly
CONSTRUCTED.

Per-material bodies: snow forms a thick cap; moss/grass overlap the earth
edge; sand has layered ochre sides; stone a heavy darker foundation;
forest floor dark compact soil. Never one shared rounded box.

Process mandated: study reference → identify large/medium/small geometry →
manually author one composition per material → only then generalize.
Render results BESIDE cropped reference tiles, same camera and thumbnail
size. Iterate until construction, density, proportions, bevel language,
layering and material richness are visibly close.

## Reference reverse-engineering (tile by tile)

- **Forest / mulch (brown tiles)**: chocolate soil base; top ~85% covered
  by LAYERED angular bark slabs 5–12 cm, flat-topped, bevelled, stacked in
  2–3 overlapping sheets; per-piece tones alternate ochre/tan/deep brown;
  some pieces tilt 5–15° and poke past the rim; soil shows only in gaps.
- **Sand (yellow tiles)**: the top is divided into SEVERAL broad angular
  terraced planes — pressed sand shelves/wedges with soft-bevelled step
  edges (2–5 cm steps), plus an occasional swept curved ridge; multiple
  connected height levels, no single dune; sides show layered ochre bands.
- **Stone (grey tiles)**: 4–9 fitted flat-topped stones, varied sizes and
  slight rotations, DEEP clean seams, ~1 cm bevels, small height
  differences between neighbouring stones; warm grey family; chunky, firm.
- **Moss / grass (green tiles)**: DENSE fields of chunky rounded tufts —
  dozens of connected bumps (broccoli-floret clusters), grouped with
  visible earth between groups; green mass slightly overhangs the soil
  side; rich irregular top silhouette.
- **Snow (white tiles)**: thick cap of several JOINED chunky snow sections
  with uneven lobed edges; visible 5–8 cm thickness over a darker body,
  slight overhang; the top has broad soft height changes (plateau-ish
  sections), never one dome.
- **General**: moderate bevels everywhere; strong per-piece tone
  variation; dark contact shadows ground every piece; detail density is
  MEDIUM-HIGH (5–40 readable sub-forms per tile); compositions are
  authored and asymmetric.

## Rebuild plan (fresh composers; keep only neutral infrastructure)

Reusable: vertex-colour Batch/mesher plumbing, palette tokens, review
harness, validation, determinism seeding. NOT reusable: all five current
compositions, the "one dome/cushion" instinct, sparse-scatter instinct.

New piece vocabulary needed (angular, bevelled, flat-topped):
1. `slab_piece` — polygonal (5–8 gon) flat-top solid, bevelled, tiltable:
   bark slabs, stone slabs, snow sections.
2. `wedge_piece` — plan polygon with a SLOPED top plane (terraced sand
   shelves, ramped soil sections).
3. `tuft_clump` — 3–7 small fused rounded bumps as ONE mesh (moss
   florets), grouped into clusters.
4. Layering: pieces stack on pieces (bark sheet 2 sits on sheet 1;
   snow sections join with slight height offsets).
5. Bodies per material: extra side bands (sand strata), cap overhang ring
   (snow/moss), heavier foundation band (stone).

Compositions are authored piece lists (positions/rotations/sizes fixed by
hand, bounded jitter only), 10–40 pieces per tile, multiple height levels,
clusters + deliberate gaps. Render beside cropped reference at thumbnail
size for every iteration.

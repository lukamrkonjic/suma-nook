# Endless water-tile world

## Status and scope

This slice establishes the world substrate:

- every revealed ocean coordinate is a real `tile_open_water` tile;
- land replaces one addressed water tile at elevation zero;
- the player may keep building in any direction, moving the discovery envelope
  and camera/build limits outward;
- only a finite tile window is rendered, with distance haze before its edge;
- generated water is fishable now and has a sparse mutation backend for a
  future bucket;
- existing stock, placement, stacking, undo, saving, mouse, and controller
  workflows remain authoritative.

Progression, generated islands, boats, ocean encounters, and biome rules remain
separate future features.

## Authoritative model

The ocean is not a backdrop plane and is not an infinite saved array.

Three services divide responsibility:

1. **`WorldGrid` — explicit overrides.** Persisted land, authored water,
   stacked tiles, structures, landmarks, rotations, and mutable anchor state.
2. **`WorldWaterField` — infinite tile source.** When no explicit elevation-zero
   cell exists, a revealed coordinate resolves deterministically to the actual
   `tile_open_water` definition. Systems query the same tile identity for
   building, swimming, fishing, controller browsing, and future bucket use.
3. **`WorldEnvelope` — discovery and travel policy.** A derived rectangle
   around explicit constructed bounds. It controls camera/build travel and
   which part of the infinite field is revealed; it never changes tile
   identity.

An explicit grid cell always wins over the generated field. The result is a
layered map:

```text
effective tile(coord) =
    explicit WorldGrid cell
    else sparse removed-water tombstone
    else generated tile_open_water
```

Generated tiles do not inflate `WorldGrid.total_tile_count()` or ordinary save
cell arrays. This preserves sparse-world scale without pretending the water is
empty space.

## Streaming renderer

`StreamedWaterTiles` renders tile coordinates, not one ocean plane.

- A snapped, camera-centered cell window intersects the discovery envelope plus
  its fade band.
- Each open-water coordinate contributes a subdivided top tile to a combined
  `ArrayMesh`.
- Each generated coordinate contributes an individual shallow-bed tile to a
  second combined mesh. A tiny inset leaves a restrained grid seam so the sea
  still reads as buildable cells.
- Explicit authored water retains its normal per-tile bed.
- Adjacent top tiles share one material and world-space wave phase. The merged
  appearance is the existing `connection_mode: merged_surface` behavior; it
  does not erase per-coordinate tile identity.
- The shader receives `WorldEnvelope` bounds and dissolves the streamed tiles
  into distance haze. The render window includes hidden water beyond the
  logical edge so opacity reaches zero before geometry ends.
- Rebuilds occur only after an explicit grid edit, field mutation, envelope
  change, or snapped camera-window crossing.

Rendering cost depends on the configured stream window, not world dimensions
or coordinate magnitude.

## Building and replacement

`WorldWaterField.replacement_record()` distinguishes generated and explicit
water.

### Generated water

An adjacent land placement writes an explicit `WorldGrid` cell at that
coordinate. The generated water tile is thereby overridden. Removing that land
reveals the generated water again.

### Explicit water

Clear authored water can be replaced atomically when it has no upper stack,
landmark, or structure:

1. preserve its full `CellState`;
2. replace it with the incoming tile;
3. never refund water to stock;
4. retain the state in undo history;
5. restore it on undo.

Moving a tile stack follows the same transaction.

### Structures on generated water

When an object such as a dock needs mutable per-cell state, the generated water
coordinate is promoted to an explicit `tile_open_water` cell before the normal
structure transaction. It is still the same tile definition and surface type.

## Fishing, swimming, and bucket readiness

- Swimming and water interaction effects query `WorldWaterField`, so generated
  and authored ocean tiles behave identically.
- Proximity and screen-space interaction target resolution use the resolved
  tile definition. Generated water therefore exposes the same fishing anchor.
- Fishing loops remain valid while the addressed coordinate resolves to open
  water.
- Normal build-mode pickup rejects both generated and authored water with the
  bucket-specific message.
- `remove_water_tile()` and `restore_water_tile()` already provide the future
  bucket transaction. Generated removal writes one sparse coordinate
  tombstone; authored removal returns its full state.
- Tombstones are persisted under `water_field.removed_generated_cells`.

The bucket item and its player-facing input/action are intentionally not
introduced in this slice.

## Envelope, camera, and hidden generation

`WorldEnvelope` derives explicit constructed bounds and grows them by
`ocean_margin_cells`.

- Camera focus and temporary pan are clamped inside the envelope.
- The controller-native build cursor uses the same limit.
- Placing an explicit frontier tile invalidates the envelope and pushes the
  relevant side outward.
- There is no global maximum coordinate.
- `hidden_generation_bounds()` reserves a ring outside the visible envelope.
  Future island descriptors can live there without entering `WorldGrid` or
  moving the horizon before discovery.

## Tuning

- `ocean_enabled`
- `ocean_tile_id`
- `ocean_margin_cells`
- `ocean_fade_cells`
- `ocean_stream_radius_cells`
- `ocean_surface_subdivisions_per_cell`
- `ocean_bed_tile_inset`
- `ocean_snap_cells`
- `ocean_camera_inset_cells`
- `ocean_hidden_generation_ring_cells`

## Acceptance contract

- Every revealed empty coordinate resolves to `tile_open_water`.
- The visible sea is assembled from streamed water-tile tops and beds.
- Generated water is fishable and swimmable.
- A clear water tile is not normally pickable before the bucket exists.
- Land replaces water at one coordinate without granting free water stock.
- Generated water returns when its ordinary land override is removed.
- Explicit water state round-trips through undo/redo.
- Generated water can promote to mutable state for a dock or future bucket.
- Sparse water tombstones round-trip through save data.
- Camera/build bounds expand independently in all four directions.
- Streamed vertex/draw cost remains bounded at 10,000 constructed tiles.

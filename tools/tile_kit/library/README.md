# Official Tile Library

The Tile Library is the authoring source for official game tiles. It is
presented inside Asset Studio's single **Tiles** browser; there is no separate
Tile Kit category or second list of recipes. Selecting a real tile composes its
lifecycle/CRUD controls and either its procedural sculpting tools or imported
asset tools in the right inspector. Runtime code
continues to consume the compiled `data/tiles.json` catalog and baked scenes;
it never scans editor recipes or manifests.

## Content model

- A **recipe** (`recipes/<tile_id>.tres`) owns procedural appearance and seed.
- A **manifest** (`manifests/<tile_id>.tres`) owns the stable ID, lifecycle,
  catalog metadata, dependencies, and recipe/imported source.
- A **bake** (`../baked/<tile_id>_<role>[_nXX].tscn`) is generated output.
- `TileCatalogCompiler` validates manifests and compiles them into the existing
  runtime catalog and active/preview lists.

Display names, recipes, and geometry may change. A published `tile_id` must not.
That ID is the contract used by worlds, inventory, rewards, and future saves.

## Workflows

- **Save Draft** writes only to `user://tile_library/drafts`; it cannot change
  runtime content.
- **Publish New** validates, creates revision 1, bakes under the stable ID, and
  atomically compiles the runtime catalog.
- **Overwrite** keeps the stable ID and increments its revision.
- **Archive** retains the runtime definition but removes it from discovery and
  marks it unobtainable. This is the normal post-launch removal path.
- **Hard Delete** is blocked while manifests, authored JSON, or development
  saves reference the ID. It is intended for correcting development mistakes.

Imported legacy tiles have manifests too. Their catalog metadata is editable
now; their geometry remains external until a procedural recipe replaces it.

New tiles begin from the generic templates in `TileTemplateLibrary` (organic
ground, bare ground, sculpted dunes, constructed surface, or shallow basin).
Templates have no game IDs and never appear in the Tiles browser. A template
becomes content only after the designer assigns a new stable ID and publishes.

All 21 current procedural recipes are published as real preview-stage tiles.
Preview publication makes them available for live authoring and review without
silently expanding the progression-facing active tile roster.

All mutating service methods are disabled outside editor/debug builds. The UI
reflects this, but the guard is enforced in `TileLibraryService` so release
builds cannot bypass it. Released games therefore consume official content
read-only.

The pipeline deliberately has no save-migration layer during MVP development.
The stable-ID boundary is already suitable for adding new tiles after launch;
save migration can be introduced later only for intentional ID/schema changes.

## Headless checks

```text
godot --headless --path . --script tests/tile_library_test.gd
godot --headless --path . --script tests/tile_kit_connection_test.gd
```

Headless bake:

```text
godot --headless --path . --script tools/tile_kit/bake_cli.gd -- --tile-id=tile_kit_grass
```

# Suma architecture

Suma follows one rule:

> Code defines reusable behaviour and rules. Data defines content,
> configuration, and relationships.

This is deliberately smaller than a generic framework. Godot scenes remain
the presentation and input layer, `GameCore` composes gameplay services, JSON
defines authored content, and typed GDScript interprets capabilities.

## Runtime shape

- `scripts/core/game_core.gd` is the composition root for gameplay state.
- `scripts/core/game_content_catalog.gd` composes the shipped definition
  validators without teaching the base registry about features.
- `scripts/core/registries.gd` loads a candidate catalog, validates it, and
  atomically publishes it only when the complete catalog is sound.
- `scripts/main.gd` composes scene-facing controllers and presentation. It
  does not own definition data or placement/interaction rules.
- `scripts/world/world_grid.gd` owns the authoritative placed-world model.
- Systems communicate through small APIs and signals. There is no global
  gameplay event bus, service locator, ECS, or database.

Definition data, runtime state, save data, behaviour, and presentation are
separate:

| Concern | Owner | Example |
| --- | --- | --- |
| Definition | `data/*.json` + typed `Defs` resources | High Tent capacity |
| Runtime | Feature or world system | Tent durability and occupants |
| Save | `GameCore.to_save_dict()` and feature adapters | Stable ID + mutable values |
| Behaviour | Typed systems | `ShelterSystem`, `SleepSystem` |
| Presentation | Renderer, assets, UI adapters | Tent GLB and interaction label |

## Repository structure

```text
data/
  capabilities.json          # vocabulary understood by systems
  structures.json            # placeable definitions
  recipes.json               # content relationships
  tiles.json, items.json...  # other definition families
scripts/
  core/
    content/                  # snapshot, provenance, validation issues
      validators/             # generic schemas and reference checks
    defs.gd                   # typed definition resources
    game_content_catalog.gd   # application content composition
    registries.gd             # typed read API + atomic reload
    game_core.gd              # gameplay composition root
  features/
    camping/                  # definitions, validation, systems,
                              # interactions, save and presentation adapters
  systems/                    # cross-feature runtime services
  world/
    placement/                # rules, target resolver, preview, history
    interaction_target_resolver.gd
  ui/                         # state consumers and user intent
tools/
  validate_content.gd         # fast content CRUD check
tests/
  test_runner.gd              # headless core/contract suite
  full_loop_runner.gd         # real-scene acceptance loop
```

Feature folders are added when a feature owns real behaviour and state, not
merely to wrap one function. Camping qualifies; a cosmetic prop does not.

## Content catalog and schema

JSON remains the smallest useful authoring format for the current team.
Definitions are converted immediately into typed resources in `Defs`; systems
never scatter direct JSON reads.

Every definition has:

- a stable, unique string `id`;
- a typed schema appropriate to its kind;
- a source record containing file, array entry, content kind, and ID;
- stable-ID references to other definitions;
- tags for classification and capabilities for reusable behaviour.

`Registries.load_all()` creates a `ContentCatalogSnapshot`, parses every file,
runs generic and feature-owned validators, and publishes the snapshot only if
there are no errors. A bad edit therefore cannot partially replace the live
catalog. Errors identify the source file, entry/ID, field, and error code.

The catalog validates duplicate IDs, malformed shapes, unknown capabilities,
dangling recipe/asset/skill/content references, and feature-specific contracts.
Safe development hot reload is `Registries.reload_all_atomic()`.

## Global content contract and High Tent proof

The architecture is global, not a High Tent subsystem. Skills, items, tiles,
structures/objects, recipes, loot tables, parcels, anchors, capability
definitions, enemies, and landmarks all receive the same stable-ID,
provenance, common-traits, validation, atomic-publication, typed-read, and save
reference treatment. Adding a future definition family means registering its
typed parser in the catalog and it automatically becomes subject to this
lifecycle.

High Tent is the first end-to-end proof that the global contract can drive a
real stateful feature without content-ID branches:

Static definition (`data/structures.json`, abbreviated):

```json
{
  "id": "struct_high_tent",
  "name": "High Tent",
  "asset_id": "prop_shelter",
  "kind": "building",
  "socket_type": "structure",
  "preserve_instance_state": true,
  "capabilities": {
    "shelter": {"capacity": 2, "weather_resistance": 0.8},
    "sleep": {"capacity": 2, "comfort": 6},
    "storage": {"slots": 6},
    "durability": {"maximum": 100.0}
  }
}
```

A placed instance is generic world state:

```gdscript
{
  "iid": 42,
  "id": "struct_high_tent",
  "socket": 0,
  "rot": 1,
  "parent": 0,
  "support": ""
}
```

Camping owns only its mutable feature state:

```gdscript
{
  "iid": 42,
  "durability": 87.5,
  "occupants": ["player"],
  "construction_progress": 1.0
}
```

The save stores the stable definition ID and minimum mutable state. It does
not copy capacity, comfort, weather resistance, model paths, or tags.
`StockManager` preserves a stateful instance token when the tent is picked up,
so instance `42` and its camping state survive world → inventory → world.

`CampingDefinitions` interprets capability payloads into typed camping views.
`ShelterSystem` owns occupancy/durability; `SleepSystem` asks that service
whether an actor may sleep. `CampingInteractions` exposes an
`InteractionOption`, and the general interaction resolver discovers it without
an `if id == "struct_high_tent"` branch. Presentation consumes the option and
current state; it does not decide whether sleeping is legal.

## Module contracts

- A feature owns its schema adapter, validators, mutable systems,
  interactions, tests, save adapter, and presentation adapter.
- `GameCore` is the only place that wires feature dependencies.
- Cross-feature calls use capabilities, stable IDs, typed query methods, or
  signals. They do not reach into another feature's dictionaries.
- Generic world code knows structure instance IDs and placement capabilities,
  not High Tent rules.
- Rendering reads authoritative state and definitions; it never mutates
  gameplay policy.
- Data selects supported behaviour. It never embeds scripts, expressions, or
  a homemade rules language.

Placement follows the same boundary: `PlacementRules` decides legality,
`PlacementTargetResolver` finds the highest valid support,
`PlacementPreview` renders feedback, and `PlacementHistory` owns undo/redo.
The controller coordinates them. Interaction targeting has an equivalent
single service.

## Content CRUD workflow

### Create

1. Add the definition with a new stable ID and add its asset.
2. Declare existing capabilities/tags; add a new capability definition only
   when it represents genuinely reusable behaviour.
3. Add references such as recipes using stable IDs.
4. Run the content validator and focused tests.
5. If new behaviour is required, implement it in a feature module and register
   that module's validator in `GameContentCatalog`.

Generic systems use the content immediately; a cosmetic/balance variant
normally needs no code change.

### Read

Use typed registry methods (`structure(id)`, `tile(id)`, and so on) or a
feature definition adapter. Never load a data file directly from gameplay.
Use `definition_source(kind, id)` when tooling needs provenance.

### Update

Edit data for balance, labels, relationships, capability values, and assets.
Run `tools/validate_content.gd`; atomic reload either publishes the complete
candidate or retains the previous catalog. Schema changes require explicit
typed parsing, validation, and tests.

### Delete

Remove the definition only after the validator reports no remaining
references. During pre-release, reset incompatible local saves. After release,
deletion requires an explicit alias, replacement, refund, or migration before
the old ID can disappear.

## Validation and tests

Fast content validation:

```powershell
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe `
  --headless --path C:\Dev\suma-nook `
  --script tools/validate_content.gd
```

Required gates:

1. Content catalog loads with no errors.
2. Unit suite passes, including duplicate IDs, source locations, dangling
   references, failed atomic reload, feature schemas, stateful stock tokens,
   save rejection, placement rules, and camping state round trips.
3. Full real-scene loop passes for movement, interaction, placement, stacking,
   save/reload, pause UI, and runtime visuals.
4. `git diff --check` is clean and Godot reports no parser/resource errors.

When a bug crosses a boundary, add a regression test at that boundary rather
than only testing the final screen.

## Save compatibility policy

Pre-release policy is intentionally strict and cheap:

- saves contain `format: 1`;
- only the current format is accepted;
- every saved content reference is validated before any manager is hydrated;
- incompatible, missing, or retired IDs reject the load and clearly require a
  development save reset;
- no migration, alias, compatibility-placeholder, or silent repair code ships
  yet.

This is appropriate while one developer frequently resets the world. It keeps
the save path honest and avoids preserving accidental schemas.

Before the first public release, freeze the stable-ID policy and introduce a
sequential migration pipeline. Post-release deletion/renaming must use
aliases, replacements, refunds, or explicit migrations, and fixtures from
every released save format must remain in CI. Never silently drop player-owned
content.

## What Suma takes from Imota

The useful proven ideas found in `C:\Dev\imota-idle` are:

- one indexed content read surface instead of scattered file loads;
- stable IDs as save/reference contracts;
- validation that treats dangling references as hard errors;
- a fast command dedicated to validating content;
- typed definition wrappers at behaviour boundaries;
- explicit composition and focused preview/test tools.

Suma uses those ideas in a smaller form: one atomic catalog, source-aware
errors, feature validators, and one content command.

Suma deliberately does **not** copy:

- Imota's numeric-ID minting/alias machinery before release;
- the large autoload registry and name-to-ID compatibility indexes;
- OSRS skills/economy/content structures;
- broad station maps and large hard-coded dispatch tables;
- world-generation/chunking/tooling layers not required by Suma;
- a giant general-purpose framework, ECS, database, or global event bus.

## Staged implementation

1. **Global catalog foundation — complete.** Every current definition family
   uses typed definitions, common traits, provenance, atomic loading,
   references, feature validator hooks, and the content CLI.
2. **Global capability path — complete.** High Tent proves the shared path
   from capability data → feature systems → interaction → saved mutable
   instance state; the path is available to every definition family and
   future content item.
3. **Stateful inventory — complete.** Instance identity/state survives pickup,
   storage, save/load, and replacement.
4. **Placement boundary — complete.** Rules, target selection, preview, and
   history extracted from the controller.
5. **Interaction boundary — complete.** Screen targeting and capability-based
   feature interactions extracted from `Main`.
6. **Pre-release persistence cleanup — complete.** Current-format validation
   replaces speculative migration and compatibility code.
7. **Future feature modules.** Add a module only when a prototype needs
   reusable behaviour. All content still enters through the global catalog;
   prefer extending an existing capability over adding a content-ID exception.

The test for future abstraction is practical: if adding a second content item
with the same behaviour still requires editing generic code, the behaviour
boundary is incomplete. If an abstraction has only one trivial caller and no
owned state or policy, it probably should not exist yet.

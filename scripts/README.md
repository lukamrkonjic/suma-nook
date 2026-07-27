# Scripts

Typed GDScript, explicit wiring, no global event bus, no autoloads.

- `core/` — GameCore (composition root, RefCounted, fully headless-testable),
  Registries, Defs (typed definitions), RngService (named seeded streams),
  PlayerProfile.
- `systems/` — one manager per concern (skills, rewards, parcels,
  crafting, inventory, stock, equipment, collection, landmarks, combat, save,
  audio). All RefCounted except GameAudio (needs stream players).
- `world/` — WorldGrid (pure data model), WorldRenderer (state-diff scene
  reconciliation), PlacementController (ghost/undo/redo/safety), Enemy,
  LandmarkEncounter.
- `player/` — PlayerController (continuous CharacterBody3D movement + state
  machine), PlayerVisual (proxy build, customization, procedural animation,
  equipment attachments), CameraRig, SkillActions (fishing/chopping/attack
  sequencing; rewards resolve on impact frames).
- `visuals/` — MaterialLibrary, AssetLibrary (GLB by asset id + material
  rebind), LightingRig, EffectsManager.
- `ui/` — UiKit (shared look), Hud, GamePanels, ParcelReveal,
  CharacterCreator.
- `main.gd` — boots and wires everything; owns input routing and
  cross-cutting flows only.

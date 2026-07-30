# Progression v1 archive — XP levels, Land Parcels, Pattern Dust

Archived on 2026-07-30 by the progression rework
(`docs/PROGRESSION_REWORK_PLAN.md`). This folder preserves the retired
first-generation progression exactly as it last shipped, so it can be
studied or revived without repository archaeology.

The `.gdignore` file makes Godot skip this folder entirely: archived
scripts keep their original `class_name` lines and full typed source,
and nothing here is parsed, imported, or exported.

## What was retired and why

| Piece | Was | Replaced by |
|---|---|---|
| `parcel_manager.gd` | Parcel items → three-choice tile reveal, Pattern Dust on duplicates, hidden new-discovery pity | `scripts/features/progression/vision_system.gd` — well-fed Visions, honest draws, refund meter + shrine as the player-visible tools |
| `skill_manager.gd` | XP, levels 1–20, data-driven level unlocks | Flat activities (`data/skills.json`) + milestone rewards (`data/milestones.json`) |
| `data/parcels.json` | Parcel definitions (family weights per parcel kind) | `data/inspiration_domains.json` domain pools |
| `data/skills.json` | Levels/XP/unlock arrays (archived copy) | Slimmed activity definitions |
| `data/recipes_parcel_and_reroll.json` | Parcel-crafting + reroll recipes (extracted) | Retired outright |
| `data/items_retired.json` | `pattern_dust`, `parcel_*` item definitions (extracted) | Retired outright |
| Save keys `skills`, `parcels` | XP/levels, pending parcel state | Migrated on load into `progression` + preserved verbatim under `progression.archived_v1` |

## How to restore levels later

1. Copy `skill_manager.gd` back to `scripts/systems/` (its
   `class_name SkillManager` is intact).
2. Restore the level/XP fields to `data/skills.json` from the archived
   copy here, and re-add the XP fields to `Defs.SkillDefinition`.
3. Old saves still carry their levels: `progression.archived_v1.skills`
   in any save written after the rework contains the exact pre-rework
   `{xp, levels, actions}` payload.
4. Re-register whatever unlock flow levels should drive; the milestone
   system can coexist with levels.

Nothing else in the rework assumes levels are gone forever — lifetime
action counts per activity are still tracked live in
`ProgressionModule.activity_actions`.

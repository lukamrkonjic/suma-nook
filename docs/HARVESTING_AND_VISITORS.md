# Gathering and world visitors

Status: current implementation contract.

Gathering is a contribution source for Projects, not a common-currency
economy. Trees, rocks, shrubs, and future sources share
`HarvestingModule`; fishing uses the same contribution boundary at haul
commit. World visitors remain a separate optional global gift system.

## Resource promise

Every `harvest_source` follows one reusable lifecycle stored on its stable
structure instance:

1. mature;
2. become ready;
3. accept one interaction and become busy;
4. commit exactly one eligible Project contribution at the action deadline;
5. show an explicit depleted form while regrowing; and
6. return to ready without changing instance ID, placement, or visual seed.

Moving, storing, saving, reloading, or repeated input cannot refresh or
duplicate a source. If no tracked Project needs its tags, interaction mode
leaves it untouched and explains why. Edit mode can still move or remove it
as landscaping intent.

Profiles in `data/harvest_profiles.json` define contribution tags, verb,
action/maturation/regrowth timings, presentation profile/settings, and an
optional depleted structure visual. Structures opt in only through the
`harvest_source` capability. There are no structure-ID gameplay branches.

## Transaction boundary

The source asks `ContributionService` for an eligible slot before starting.
It stores that target and an action receipt in runtime state. The centralized
deadline commits the receipt once, changes the source to regrowing, and emits
presentation signals. Common Timber, Stone, and Provisions never enter
`InventoryManager` or `TokenPouchService`.

The presentation adapter owns windup/impact audio, particles, flash, recoil,
and depleted-form transitions. It cannot choose a Project or grant progress.

## Visitors

`VisitorModule` still owns one global heartbeat, persistent pre-rolled event,
selected presentation adapter, and saved gift. Visitors do not scale with
placed source count and are not required for Project progression. Their gift
uses the same `BuildRewardService` ownership path as other build pieces.

Project, Frontier, Special Find, and Falling Object details live in
`docs/PROJECT_PROGRESSION.md`.

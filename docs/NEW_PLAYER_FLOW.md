# Suma — new-player flow

Status: current implementation contract.

The first session teaches the smallest complete loop without exposing a
material inventory, XP bar, crafting tree, or economy screen.

## 1. Meet the world

The opening land arrives through the normal seeded Nook reveal. Gameplay then
starts in interaction mode, with the Build Bag closed and the keeper optional.
The tracked-Project chip says **Choose a Project** and the first toast explains:

> Choose a Project and contribute a few things from your world.

## 2. Choose one clear goal

Opening Projects presents three stable Collection offers: Forest, Cottage,
and Garden. Keyboard/mouse and controller players use the same modal, visible
focus, tooltips, accept action, and back action. Choosing one tracks it in the
compact HUD; switching later never erases progress.

## 3. Contribute from the world

The first Projects ask for one Timber, one Stone, and one Provisions. A mature
tree click starts one short automatic chop and contributes one Timber. A rock
does the same for Stone. A berry/forage source or one committed fishing haul
provides Provisions. Each result pulses the tracked Project display. Repeated
clicks during an action do nothing and never duplicate progress.

The source remains part of the diorama. Its depleted stump/remnant visual
regrows on a saved timer. If the tracked Project does not need a source, normal
interaction explains why and leaves it untouched; explicit edit mode remains
the landscaping route.

## 4. Reveal and build

Completion reveals the exact pre-rolled tile or model, grants one copy through
the existing Build Bag ownership rules, and replaces only the completed offer.
Pressing `build_mode` enters edit mode. The player places or moves the reward,
then presses it again to return to interaction mode.

## 5. Grow the frontier

Clicking a boundary glow opens that point's Frontier Project. The glow does
not generate terrain. Its small shared requirements appear in Projects; when
complete, the reserved deterministic Nook arrives through the normal reveal
wave. Reloading or reopening the point cannot reroll its requirements or land.

## 6. Notice rare opportunities

A visible crystal/relic glint may appear on an eligible object from a single
world-level schedule. Gathering it stores one Special Find in a tiny reserve
for a future rare Project. Much later, a Falling Object may offer a collection
choice. Its piece visibly lands as a golden locator and belongs to the player
only after it is found and claimed.

## Persistence contract

The selected Project, every Project's slot progress, concealed reward,
Frontier seed metadata, resource lifecycle/deadline, Special Finds reserve,
and landed Reward Drop survive save/load. No menu opening, reload, repeated
input, or interrupted presentation can reroll or grant twice.

The full system contract is in `docs/PROJECT_PROGRESSION.md`.

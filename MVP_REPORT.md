# MVP correction report

## Outcome

The prototype has been rebuilt around the actual cozy design-toy / idle loop:

- Motes bring one of three set coins.
- Coins buy randomized pieces from their matching themed set.
- Rewards appear as physical clickable objects beside the Bloomforge.
- Ground is loot and expands a connected modular diorama.
- Placed pieces can be moved, stacked, stored, retrieved, sold, undone, and redone.
- Functional curios alter the live reward table.
- Collection progress is grouped by set.
- Lighting, background, fog, and ambient effects have three persistent presets.
- Offline time produces capped waiting visitors, not automatic items.

## Visual correction

The previous 640×360 dark forest presentation was removed. The game now uses a native
1280×720 Forward+ orthographic viewport, 4× MSAA plus FXAA, ambient occlusion, soft
directional shadows, chamfered modular tiles, rounded low-poly props, restrained cream UI
cards, and environment-specific atmosphere. Tiny high-frequency surface marks were removed
so distant blocks keep clean color fields instead of collapsing into pixel noise.

The result follows the supplied reference's broad visual principles—small handcrafted
dioramas, saturated toy materials, clean negative space, readable tile sides, and gentle
weather—using wholly original procedural assets and an original Bloomforge/visitor design.

## Verification

- Data/logic suite: **123 assertions across 12 suites**.
- Full-loop scene suite: **36 assertions**.
- Parser/import pass: clean.
- Visual QA: Sunroom, visitor, physical reward, expanded, dusk, and rain captures inspected.

## Save compatibility

⚠️ Reset your save. Version 2 deliberately rejects the earlier prototype save because the
old Seed IDs and reward semantics were replaced with themed coins.

# Suma HUD design system

The player-facing interface is an editorial layer over the world, not a stack
of game-menu cards. It uses warm paper, dark ink, fine rules, generous space,
and small semantic color accents. The world remains the largest visual shape.

## Single source of truth

`scripts/ui/ui_kit.gd` owns the visual language:

- typography and font weights;
- HUD safe margins and spacing;
- paper surfaces, hairlines, focus outlines, and dividers;
- buttons, window headers, Build Bag cells, progress treatments, and chips;
- semantic collection accents.

Player-facing screens should compose these primitives. Do not add a local
`StyleBoxFlat` for a new card, button, input, or HUD prompt. Add or refine the
appropriate `UiKit` primitive instead so the whole interface can change from
one file. Local styling is reserved for content that is itself visual data,
such as a selectable skin-color swatch.

## Typography

- **Display:** Libre Baskerville. Use `display_label()` for screen titles,
  prominent object names, and editorial headings.
- **Body:** Manrope. Use `label()` and `muted_label()` for readable copy.
- **Utility:** Manrope uppercase with tracking. Use `utility_label()` or
  `eyebrow()` for state, categories, and compact HUD metadata.

Display type should be rare enough to preserve hierarchy. Controls and dense
inventories stay in the body face.

## Surfaces and spacing

- Prefer negative space and dividers over nested cards.
- Use `cloud_panel_style()` only for a primary modal sheet.
- Use `hud_chip()`, `hud_tooltip_style()`, and `hud_dock_style()` for persistent
  HUD. Edge placement goes through `place_hud_chip()` and `HUD_MARGIN`.
- Corners are nearly square. Shadows are avoided; separation comes from paper
  contrast and one-pixel hairlines.
- Repeated inventory objects may use quiet square cells so scanning stays easy.

## Color

Warm paper and dark ink carry almost the entire interface. Strong colors are
small semantic signals: the left edge of a HUD chip, a selection rule, a count
badge, a focus outline, or a progress marker. Use `collection_accent()` rather
than inventing a new panel fill per screen.

## Interaction contract

The redesign never changes the input contract. Every interactive surface must
retain deterministic focus, visible focus styling, `ui_accept`, `cancel`,
focused tooltips, and contextual prompts through `InputService`. Pointer hover
is supplementary, not the only route to information.

# Color design system

Suma has one authored color source:
[`assets/palettes/gg_material_palette.tres`](../assets/palettes/gg_material_palette.tres).
It is the only file in `assets/palettes/`. Game scripts, gameplay JSON, visual
profiles, shaders, generated meshes, and UI scenes must refer to its semantic
tokens instead of owning RGB values.

The file deliberately separates the exact approved semantic source palette
from 128 reusable reference tokens used by grouped character choices, lighting
profiles, world themes, and authoring tools. The game keeps precise names such
as `water_deep`, `ui_bad`, and `hair_primary`, and those runtime roles retain
their individually calibrated values.

The active `default` scheme is the original Suma garden-clay direction from
the first retro visual push. Its anchors are a warm ivory atmosphere,
yellow-olive grass, deep forest greens, terracotta earth, muted sage-aqua
water, warm stone, and restrained gold. Gold, coral, pink, and violet are
reserved for UI focus, flowers, fire, rewards, and other small focal details.
Later `earthwood_cozy`, `mosslight`, and `hearthfield_haze` experiments remain
available for comparison, but they must not be layered over the shipped retro
look or replace it as the default.

`PaletteDefinition` is the access layer, not another data source. Use
`PaletteDefinition.shared()` when a system does not already receive the shared
palette from `Main`.

## Contents of the canonical file

- `swatches`: shared profile, theme, character-choice, and authoring colors,
  expressed as role-neutral reference tokens and capped at 128 RGB values.
- `colors`: exact approved source values for semantic world, character, UI,
  VFX, weather, cloud, debug, and shader roles.
- `render_targets`: measured screen-space targets used by the palette solver.
  These are verification targets, not material albedos.
- `aliases`: compatibility names that resolve to a canonical semantic token.
- `environment_profiles`: every color formerly serialized in the individual
  `VisualStyleProfile` resources.
- `world_themes` and `background_presets`: sky, light, night, and time-of-day
  colors.
- `schemes`: reversible whole-game adjustments and explicit token overrides.
- `token_domains`: maps token prefixes to world, UI, VFX, character, or
  environment adjustment domains.
- `design_rules`: machine-readable authoring policy and safe adjustment bounds.
- `character_swatch_groups`: approved skin, hair, and outfit choices, expressed
  as references to the same primitive palette.

## Reference-token naming

Primitive colors use `<hue-family>_<tone>`, for example `blue_700`,
`green_500`, or `sand_200`. The supported families are `blue`, `brown`,
`green`, `neutral`, `olive`, `orange`, `pink`, `red`, `sand`, `teal`,
`violet`, and `yellow`.

Tone `050` is the lightest member of a family and `950` is its darkest. The
number expresses ordering within that hue family; it is not a semantic role or
a promise that two different families have identical measured luminance.
Reference names must never describe a consumer, asset, biome, character, or UI
state. Those meanings belong in semantic tokens:

```text
green_500 (reference token) <- grouped character/profile choice
blue_700  (reference token) <- grouped character/profile choice
sand_200  (reference token) <- grouped character/profile choice
```

Shaders keep neutral white fallbacks because Godot shader files cannot load a
Resource. Their owner pushes the canonical token into each color uniform at
runtime. A shader fallback must never become a second authored palette.

## Changing a color

Change the semantic token's source value in the canonical resource. Adjust a
reference value only when all grouped profile, theme, or character choices
sharing it should change together. Do not copy RGB into consumers. Material
instances, lighting profiles, clouds, backgrounds, and shader-bound effects
resolve the role through the shared design system.

For a complete approved named-palette delivery, use
`python tools/import_named_palette.py SOURCE.json SCREEN_TARGETS.json`. The
importer requires an exact 435-token-plus-5-alias key match, verifies alias
parity, and preserves the aliases as resolving names in the canonical file.

If a genuinely new role is needed:

1. Add a semantic token to `colors`; name the role, not its hue, and assign its
   approved source value in the canonical resource.
2. Add a primitive to `swatches` only for a genuinely reusable profile, theme,
   character-choice, or authoring color. The validator rejects any 129th
   swatch, so adding one at the cap requires deliberately merging or removing
   another.
3. Add its prefix to `token_domains` when an existing prefix does not describe
   the consumer.
4. Consume the token with `palette.color("token_name")` or a typed environment
   or world-theme accessor.
5. Run `python tools/validate_color_design_system.py`.

Do not add one-off RGB literals, duplicate palette assets, or color values to
gameplay JSON. User-created colors from the in-game asset editor are runtime
overrides and are deliberately supported; shipped defaults remain token-based.

## Whole-game schemes

`active_scheme` chooses a named entry under `schemes`. A scheme may contain:

- `global`: hue shift, saturation, value, contrast, temperature, tint, and
  alpha adjustments applied to every domain.
- `domains`: narrower adjustments for `world`, `ui`, `vfx`, `character`, or
  `environment`.
- `overrides`: a semantic token mapped to another token or to an explicit
  replacement color.

The application order is stored in `design_rules.adjustment_order`. Adjustment
bounds are guidance for art direction, not arbitrary effect limits. The
included `default`, `warm`, `cool`, `muted`, `high_contrast`, and
`deuteranopia_safe` schemes are starting points. `earthwood_cozy` and its later
derivatives are complete experimental remaps: every semantic token has an
explicit role-preserving value, so they remain useful for comparison without
weakening the original `default` production contract.

At runtime, call `set_active_scheme()`, `set_runtime_adjustments()`, or
`set_runtime_override()`. These emit `palette_changed`; long-lived world
materials, lighting, clouds, and shader bindings refresh from the source.
Authoring changes made directly in the `.tres` are picked up on the next load.

## Color practice

- Author source values in sRGB. Keep HDR environment values above 1.0 when the
  lighting contract requires them.
- Treat source albedo and rendered target as different contracts. Use the
  calibration tools instead of pasting a sampled screenshot color into a
  material.
- Prefer semantic states (`ui_bad`, `ui_info`) over hue names. Never communicate
  status by color alone; pair it with text, icon, or shape.
- Derive hover, pressed, disabled, and alpha-only variants from a token when the
  relationship is mechanical. Alpha changes do not consume another primitive
  swatch. Give art-directed variants their own semantic token, then reuse the
  closest reference token.
- Apply palette adjustment before display color grading. Avoid stacking local
  color correction to compensate for global grading.
- Keep archived visual-review fixtures and offline Blender preview swatches out
  of runtime contracts. They are evidence or working previews, not palette
  authorities.

## Enforcement

`tools/validate_color_design_system.py` checks the 128-swatch ceiling, that the
canonical file is the only palette asset, required sections exist, token and
swatch references resolve, shipped JSON uses `color_token`, active resources do
not serialize colors, and runtime shader color uniforms have neutral fallbacks
that are bound by their owner.

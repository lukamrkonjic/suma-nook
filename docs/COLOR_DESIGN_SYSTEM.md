# Color design system

Suma has one authored color source:
[`assets/palettes/gg_material_palette.tres`](../assets/palettes/gg_material_palette.tres).
It is the only file in `assets/palettes/`. Game scripts, gameplay JSON, visual
profiles, shaders, generated meshes, and UI scenes must refer to its semantic
tokens instead of owning RGB values.

The file deliberately separates 128 reusable reference tokens from the larger
semantic vocabulary. The game can keep precise names such as `water_deep`,
`ui_bad`, and `hair_primary` without each name introducing another RGB value.

`PaletteDefinition` is the access layer, not another data source. Use
`PaletteDefinition.shared()` when a system does not already receive the shared
palette from `Main`.

## Contents of the canonical file

- `swatches`: the complete primitive source palette, expressed as role-neutral
  reference tokens and capped at 128 RGB colors for the whole game.
- `colors`: semantic world, character, UI, VFX, weather, cloud, debug, and
  shader roles. Each role points to a reference token rather than owning RGB.
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
green_500 (reference token) <- grass_primary (semantic token)
blue_700  (reference token) <- night_pupil (semantic token)
sand_200  (reference token) <- cloud_crown (semantic token)
```

Shaders keep neutral white fallbacks because Godot shader files cannot load a
Resource. Their owner pushes the canonical token into each color uniform at
runtime. A shader fallback must never become a second authored palette.

## Changing a color

Change the reference token used by an existing semantic token, or adjust the
reference value itself when all roles sharing it should change together. Do
not copy RGB into consumers. Material instances, lighting profiles, clouds,
backgrounds, and shader-bound effects resolve the role through the shared
design system.

If a genuinely new role is needed:

1. Add a semantic token to `colors`; name the role, not its hue, and point it
   to the nearest suitable existing reference token.
2. Add a primitive to `swatches` only when none of the existing 128 can serve
   the role. The validator rejects any 129th swatch, so adding one at the cap
   requires deliberately merging or removing another.
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
`deuteranopia_safe` schemes are starting points.

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

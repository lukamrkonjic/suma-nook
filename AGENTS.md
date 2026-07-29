# Suma development rules

## Controller support is part of definition of done

Every player-facing feature must be fully usable with a controller in the same
change that introduces it. Controller support is not a later accessibility
pass.

- Express player intent as a named `InputMap` action. Do not branch gameplay
  logic on raw keycodes, mouse buttons, or controller brands.
- Give every player-facing action both keyboard/mouse and controller access,
  except an inherently device-specific alternative such as click-to-walk.
- Publish contextual prompts through `InputService`; never hardcode `E`, `A`,
  Xbox-only names, or mouse-only instructions in player-facing copy.
- Every modal or interactive UI flow must have deterministic focus, a visible
  focus state, `ui_accept` activation, `cancel`/back behavior, and focused
  tooltips. It must be completable without a pointer.
- World interactions that need a position must expose a deterministic
  controller-native target (for example, the build grid cursor), not warp or
  emulate the mouse.
- Add the action to
  `InputDeviceService.REQUIRED_CONTROLLER_ACTIONS` and extend the headless
  input-contract tests. A feature is incomplete if those tests do not cover
  its controller path.

See `docs/CONTROLLER_SUPPORT.md` for architecture, mappings, and the feature
checklist.

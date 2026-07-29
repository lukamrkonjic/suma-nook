# Controller support

Controller support is a project-wide contract. Suma may be played from boot
through character creation, gameplay, building, parcel selection, journals,
settings, and exit without reaching for a mouse or keyboard.

## Architecture

`project.godot` contains semantic actions such as `interact`, `build_confirm`,
and `panel_next`. Systems consume those actions and stay device-agnostic.

`InputService` (`scripts/input/input_device_service.gd`) is the only owner of:

- active-device detection and hot-plug state;
- switching between keyboard/mouse and controller presentation;
- controller-family-aware prompt names;
- cursor visibility;
- focus hand-off helpers; and
- the enforced list of player-facing controller actions.

`InputHintOverlay` presents the actions valid in the current context. When a
control has focus, its `tooltip_text` is shown above Select/Back prompts. The
HUD uses the same prompt service for world interactions and tutorial copy.

Context owners resolve intentional overlaps. For example, the triggers zoom
during exploration and become undo/redo while building; the shoulders rotate
the camera in the world and change journal pages while a journal is open.

Build mode uses a camera-relative grid cursor. It never moves the OS pointer,
so switching back to mouse input resumes at the player's real pointer
position.

## Default controller layout

Face-button names below describe Xbox/generic labels. Prompts automatically
use PlayStation names and Nintendo physical-button labels when detected.

| Input | Exploration | Build context |
| --- | --- | --- |
| Left stick / L3 | Move / sprint | Move keeper / sprint |
| A / south | Jump, UI select | Place or pick up |
| B / east | Back; dodge if combat is active | Cancel held piece / exit |
| X / west | Interact | Store a moved piece |
| Y / north | Enter build mode | Toggle library / world cursor |
| D-pad | Open journal pages | Navigate UI or move grid cursor |
| LB / RB | Rotate camera | Rotate camera; change open journal page |
| LT / RT | Zoom | Undo / redo |
| R3 | Return home | Rotate held piece |
| View/Create | Open map | Open map |
| Menu/Options | Pause | Pause |
| Right stick | — | Orbit in the debug asset viewer |

## Adding a player-facing feature

1. Add or reuse a semantic action in `project.godot`.
2. Bind keyboard/mouse and controller inputs. Contextual reuse is encouraged
   when the active owner is unambiguous.
3. Consume the action in the system that owns the context. Mark it handled
   when it must not propagate.
4. Add its prompt to the current context with `InputHintOverlay.set_context()`
   or `Hud.set_prompt()`.
5. For UI, use `UiKit`, set useful `tooltip_text`, call
   `InputService.focus_first()` when opening, and release focus when closing.
6. For world-space targeting, provide a stable controller-native cursor or
   selection model.
7. Add the action to
   `InputDeviceService.REQUIRED_CONTROLLER_ACTIONS` and cover its expected
   binding/behavior in `tests/test_runner.gd`.
8. Verify hot switching in both directions: controller input hides the mouse
   and updates prompts/focus; meaningful mouse or keyboard input restores the
   pointer and keyboard/mouse prompts.

Debug-only interactive tools follow the same rule. The asset viewer, for
example, supports focused catalog navigation, right-stick orbit, trigger zoom,
and controller back.

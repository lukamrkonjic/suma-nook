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

Interaction and edit modes share a camera-relative grid cursor. It never moves
the OS pointer, so switching back to mouse input resumes at the player's real
pointer position. In interaction mode X/West or A/South executes the one
highest-priority action at the cursor. In edit mode A/South places, while
X/West moves or stores according to the focused context. Y/North is the
explicit mode boundary; one press can never reach both routers.

Projects use the `project_menu` action (Guide) and the tracked HUD chip. The
modal assigns the first actionable control focus, exposes focused tooltips,
uses `ui_accept`, and closes with `cancel`. Special Find spending uses ordinary
focused buttons. Frontier glows are selected by the same deterministic world
cursor and open their Project instead of generating land immediately.

Harvest sources reuse `interact`: one press starts the complete authored
action and commits one eligible Project contribution. Repeated input while the
source is busy is rejected. No common token or inventory UI enters the path.

## Default controller layout

Face-button names below describe Xbox/generic labels. Prompts automatically
use PlayStation names and Nintendo physical-button labels when detected.

| Input | Exploration | Build context |
| --- | --- | --- |
| Left stick / L3 | Optional keeper movement | Optional keeper movement |
| A / south | Interact cursor / UI select | Place / UI select |
| B / east | Back; dodge if combat is active | Cancel held piece / close library |
| X / west | Interact | Move/store a piece |
| Y / north | Enter edit mode | Return to interaction mode |
| D-pad | Move interaction cursor / navigate UI | Move edit cursor / navigate UI |
| LB / RB | Rotate camera | Rotate camera; change open journal page |
| LT / RT | Zoom | Undo / redo |
| R3 | Return home | Rotate held piece |
| View/Create | Open map | Open map |
| Guide | Open Projects | Open Projects |
| Menu/Options | Pause | Pause |
| Right stick | Pan camera | Pan camera; orbit in the debug asset viewer |

Keyboard WASD is reserved for persistent camera panning. Land placement
targets any empty grid coordinate, including detached islands. The D-pad
cursor can therefore travel through the void without requiring an existing
neighbour. F activates the interaction under the pointer when the optional
keeper is docked.

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

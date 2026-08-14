extends Node
## Puts the window into the player's saved mode at the earliest moment there is.
##
## project.godot creates the window borderless-fullscreen, which is the right
## default for a fresh install but wrong for anyone who chose windowed. Applying
## the saved mode from Main._ready was still too late to be invisible: _ready
## does not run until main.tscn has finished instantiating, so the game showed a
## black fullscreen window for the whole of that load and then shrank.
##
## Autoloads are created before the main scene is instantiated, so this runs
## while the window is the only thing that exists. Settings live in their own
## file precisely so they can be read this early -- nothing here needs the core,
## the registries or a viewport.

const GamePreferencesScript := preload("res://scripts/ui/game_preferences.gd")
## Kept in step with the SaveManager default; only consulted when migrating a
## save that predates settings moving out of it.
const LEGACY_SAVE_PATH := "user://suma_nook_world.json"


func _init() -> void:
	var preferences: GamePreferences = GamePreferencesScript.new()
	preferences.load_from_disk({}, LEGACY_SAVE_PATH)
	preferences.apply_window_mode()

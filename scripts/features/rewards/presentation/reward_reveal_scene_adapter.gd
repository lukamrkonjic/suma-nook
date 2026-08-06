class_name RewardRevealSceneAdapter
extends Node3D
## Resolves a data profile to a registered reveal presenter. Multiple reward
## sources use this same port; adding/removing a presentation type never
## changes reward transactions or source modules.

signal reveal_started(reward: Dictionary)
signal reward_shown(reward: Dictionary)
signal reveal_finished(reward: Dictionary)

var registries: Registries
var factories: RewardRevealPresenterRegistry
var assets: AssetLibrary
var grid: WorldGrid
var camera: Camera3D
var audio: GameAudio
var _presenters: Dictionary = {}


func setup(
	content: Registries,
	presenter_factories: RewardRevealPresenterRegistry,
	asset_library: AssetLibrary,
	world_grid: WorldGrid,
	view_camera: Camera3D,
	game_audio: GameAudio
) -> void:
	registries = content
	factories = presenter_factories
	assets = asset_library
	grid = world_grid
	camera = view_camera
	audio = game_audio


func enqueue(
	reward: Dictionary,
	source_position: Vector3,
	reveal_profile_id: String
) -> void:
	var profile := registries.reward_reveal_profile(reveal_profile_id)
	if profile == null:
		return
	var presenter := _presenter(profile.presenter_type)
	if presenter == null:
		push_warning(
			"No reward reveal presenter registered for '%s'"
			% profile.presenter_type
		)
		return
	presenter.call("enqueue", reward, source_position, reveal_profile_id)


func pending_count() -> int:
	var count := 0
	for presenter: Node3D in _presenters.values():
		count += int(presenter.call("pending_count"))
	return count


func is_revealing() -> bool:
	for presenter: Node3D in _presenters.values():
		if bool(presenter.call("is_revealing")):
			return true
	return false


func accelerate() -> void:
	for presenter: Node3D in _presenters.values():
		if bool(presenter.call("is_revealing")):
			presenter.call("accelerate")


func _presenter(presenter_type: String) -> Node3D:
	if _presenters.has(presenter_type):
		return _presenters[presenter_type]
	var presenter := factories.create(presenter_type)
	if presenter == null:
		return null
	presenter.name = "%sRewardReveal" % presenter_type.to_pascal_case()
	add_child(presenter)
	presenter.call("setup", registries, assets, grid, camera, audio)
	presenter.connect("reveal_started", func(reward):
		reveal_started.emit((reward as Dictionary).duplicate(true))
	)
	presenter.connect("reward_shown", func(reward):
		reward_shown.emit((reward as Dictionary).duplicate(true))
	)
	presenter.connect("reveal_finished", func(reward):
		reveal_finished.emit((reward as Dictionary).duplicate(true))
	)
	_presenters[presenter_type] = presenter
	return presenter

extends Node
## Production-path interaction and transition review for fire structures.
##
## Captures unlit, ignited, and extinguishing states while exercising the same
## screen-space resolver and shared interaction registry used by Main.

const InteractionTargetResolverScript := preload(
	"res://scripts/world/interaction_target_resolver.gd"
)

var _core: GameCore
var _renderer: WorldRenderer
var _effects: EffectsManager
var _camera: Camera3D
var _resolver
var _fire_ids: Array[int] = []
var _failures: PackedStringArray = []
var _output_dir := "user://fire_interaction_review"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_review()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("fire_unlit.png")

	for instance_id in _fire_ids:
		var interaction := _interaction_for(instance_id)
		_check(
			interaction.get("kind", "") == "feature_interaction",
			"screen resolver finds fire %d" % instance_id
		)
		var option = interaction.get("option")
		_check(
			option != null and option.label == "Light fire",
			"unlit fire offers Light fire"
		)
		_check(
			_core.interactions.execute(option, "reviewer"),
			"click interaction lights fire"
		)
	await get_tree().create_timer(0.42).timeout
	await _capture("fire_ignited.png")
	for instance_id in _fire_ids:
		_check(
			_core.fire.is_burning(instance_id),
			"fire state is lit after interaction"
		)
		var visual := _renderer.structure_node(instance_id)
		var effect := (
			visual.find_child("BurningEffect", true, false)
			if visual != null
			else null
		)
		_check(
			effect != null and effect.visible,
			"renderer reveals the burning effect"
		)

	for instance_id in _fire_ids:
		var interaction := _interaction_for(instance_id)
		var option = interaction.get("option")
		_check(
			option != null and option.label == "Extinguish fire",
			"lit fire offers Extinguish fire"
		)
		_core.interactions.execute(option, "reviewer")
	await get_tree().create_timer(0.36).timeout
	await _capture("fire_extinguishing.png")
	_check(
		not _effects.find_children(
			"ExtinguishSmoke",
			"MeshInstance3D",
			true,
			false
		).is_empty(),
		"extinguishing produces smoke puffs"
	)

	if _failures.is_empty():
		print("FIRE INTERACTION REVIEW PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _build_review() -> void:
	var palette: CozyPalette = load(
		"res://assets/palettes/gg_material_palette.tres"
	)
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	_core = GameCore.new()
	if not _core.setup():
		_failures.append("Could not load production content.")
		return
	var entries := [
		{
			"coord": Vector2i(-1, 0),
			"structure": "struct_campfire",
		},
		{
			"coord": Vector2i(1, 0),
			"structure": "struct_firepit_polished",
		},
	]
	for entry: Dictionary in entries:
		_core.grid.place_tile(entry["coord"], "tile_grass")
		var fire := _core.grid.add_structure(
			entry["coord"],
			entry["structure"],
			0
		)
		if fire != null:
			_fire_ids.append(fire.instance_id)

	add_child(
		(load(
			"res://scenes/visual/SumaSoftDaylight.tscn"
		) as PackedScene).instantiate()
	)
	_renderer = WorldRenderer.new()
	_renderer.name = "WorldRenderer"
	add_child(_renderer)
	_renderer.setup(_core, assets)
	_effects = EffectsManager.new()
	_effects.name = "Effects"
	add_child(_effects)
	_effects.setup(assets)
	_core.fire.burning_changed.connect(
		func(instance_id: int, active: bool):
			var point := _renderer.structure_fire_world_position(instance_id)
			_renderer.set_structure_burning(instance_id, active)
			if active:
				_effects.fire_ignition(point)
			else:
				_effects.fire_extinguish(point)
	)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.2
	_camera.position = Vector3(4.8, 4.0, 5.8)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.25, 0.0), Vector3.UP)
	_camera.current = true
	_resolver = InteractionTargetResolverScript.new(
		self,
		_core,
		_camera,
		null
	)


func _interaction_for(instance_id: int) -> Dictionary:
	var found := _core.grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var visual_point := (
		_core.grid.cell_to_world(
			found["coord"],
			int(found["elevation"])
		)
		+ Vector3.UP * 0.65
	)
	return _resolver.interaction_at(
		_camera.unproject_position(visual_point)
	)


func _capture(filename: String) -> void:
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var result := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
	_check(result == OK, "capture writes %s" % filename)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

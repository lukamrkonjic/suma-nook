class_name SoftTerrainDeformation
extends Node
## Fixed-budget contact deformation for authored sand and snow relief.
##
## Two live slots follow the animated feet and ten trail slots retain fading
## impressions. The data is uploaded to the already-shared terrain materials;
## this node creates no geometry, textures, or per-tile state.

const IMPRINT_COUNT := 12
const LIVE_FOOT_COUNT := 2
const TRAIL_START := LIVE_FOOT_COUNT
const TRAIL_STEP_DISTANCE := 0.34
const PROFILE_MATERIAL_KEYS := {
	"sand": "sand_top",
	"snow": "snow_top",
}

var _core: GameCore
var _player: PlayerController
var _materials: Dictionary = {}
var _imprints: Dictionary = {}
var _directions: Dictionary = {}
var _effect_time := 0.0
var _active_profile := ""
var _last_player_position := Vector3.ZERO
var _history_valid := false
var _trail_distance := 0.0
var _trail_cursor := TRAIL_START
var _trail_foot := 0
var _emitted_trail_count := 0


func _init() -> void:
	for profile: String in PROFILE_MATERIAL_KEYS:
		var profile_imprints := PackedVector4Array()
		var profile_directions := PackedVector4Array()
		for _index in IMPRINT_COUNT:
			profile_imprints.append(Vector4(0.0, 0.0, -100.0, 0.0))
			profile_directions.append(Vector4(0.0, 0.0, -1.0, 0.0))
		_imprints[profile] = profile_imprints
		_directions[profile] = profile_directions


func _ready() -> void:
	process_physics_priority = 60
	set_physics_process(false)


func setup(
	material_library: MaterialLibrary,
	game_core: GameCore,
	player_controller: PlayerController
) -> void:
	_core = game_core
	_player = player_controller
	for profile: String in PROFILE_MATERIAL_KEYS:
		var material_key: String = PROFILE_MATERIAL_KEYS[profile]
		var material := material_library.material(material_key) as ShaderMaterial
		_materials[profile] = material
		_upload_profile(profile)
	_last_player_position = _player.global_position
	_history_valid = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _core == null or not is_instance_valid(_player):
		return
	_effect_time += delta
	for profile: String in PROFILE_MATERIAL_KEYS:
		var material: ShaderMaterial = _materials.get(profile)
		if material != null:
			material.set_shader_parameter("terrain_time", _effect_time)
		_clear_live_contacts(profile)

	var profile := _surface_profile_under_player()
	var actor_position := _player.global_position
	var travel := actor_position - _last_player_position
	travel.y = 0.0
	if not _history_valid:
		travel = Vector3.ZERO
		_history_valid = true

	if profile == "":
		_active_profile = ""
		_trail_distance = 0.0
		_last_player_position = actor_position
		_upload_all_profiles()
		return

	if profile != _active_profile:
		_active_profile = profile
		_trail_distance = 0.0
		travel = Vector3.ZERO

	var feet := _player.visual.foot_world_positions()
	var direction := _contact_direction(travel)
	var contact_strength := (
		1.0
		if _player.is_on_floor()
		else 0.0
	)
	for foot_index in mini(feet.size(), LIVE_FOOT_COUNT):
		_write_imprint(
			profile,
			foot_index,
			feet[foot_index],
			direction,
			contact_strength
		)

	var traveled := travel.length()
	_trail_distance += traveled
	if (
		contact_strength > 0.0
		and traveled > 0.001
		and _trail_distance >= TRAIL_STEP_DISTANCE
		and feet.size() >= LIVE_FOOT_COUNT
	):
		_write_imprint(
			profile,
			_trail_cursor,
			feet[_trail_foot],
			direction,
			0.92
		)
		_trail_cursor += 1
		if _trail_cursor >= IMPRINT_COUNT:
			_trail_cursor = TRAIL_START
		_trail_foot = 1 - _trail_foot
		_emitted_trail_count += 1
		_trail_distance = fmod(_trail_distance, TRAIL_STEP_DISTANCE)

	_last_player_position = actor_position
	_upload_all_profiles()


func _surface_profile_under_player() -> String:
	if (
		not _player.is_on_floor()
		or _player.state in [
			PlayerController.State.SWIMMING,
			PlayerController.State.RESCUED,
			PlayerController.State.ARRIVING,
		]
	):
		return ""
	var coord := _player.current_cell()
	if _core.grid.has_walkable_structure_surface(coord):
		return ""
	var definition := _core.grid.top_tile_def(coord)
	if definition == null:
		return ""
	return definition.soft_surface_profile


func _contact_direction(travel: Vector3) -> Vector2:
	if travel.length_squared() > 0.0001:
		return Vector2(travel.x, travel.z).normalized()
	var forward := -_player.global_basis.z
	return Vector2(forward.x, forward.z).normalized()


func _clear_live_contacts(profile: String) -> void:
	var profile_imprints: PackedVector4Array = _imprints[profile]
	for index in LIVE_FOOT_COUNT:
		var old := profile_imprints[index]
		profile_imprints[index] = Vector4(old.x, old.y, old.z, 0.0)
	_imprints[profile] = profile_imprints


func _write_imprint(
	profile: String,
	slot: int,
	world_position: Vector3,
	direction: Vector2,
	strength: float
) -> void:
	var profile_imprints: PackedVector4Array = _imprints[profile]
	var profile_directions: PackedVector4Array = _directions[profile]
	profile_imprints[slot] = Vector4(
		world_position.x,
		world_position.z,
		_effect_time,
		strength
	)
	profile_directions[slot] = Vector4(
		direction.x,
		0.0,
		direction.y,
		0.0
	)
	_imprints[profile] = profile_imprints
	_directions[profile] = profile_directions


func _upload_all_profiles() -> void:
	for profile: String in PROFILE_MATERIAL_KEYS:
		_upload_profile(profile)


func _upload_profile(profile: String) -> void:
	var material: ShaderMaterial = _materials.get(profile)
	if material == null:
		return
	material.set_shader_parameter("terrain_time", _effect_time)
	material.set_shader_parameter("terrain_imprints", _imprints[profile])
	material.set_shader_parameter("terrain_directions", _directions[profile])


func runtime_manifest() -> Dictionary:
	var active_imprints := {}
	for profile: String in PROFILE_MATERIAL_KEYS:
		var count := 0
		var profile_imprints: PackedVector4Array = _imprints[profile]
		for imprint: Vector4 in profile_imprints:
			if imprint.w > 0.001:
				count += 1
		active_imprints[profile] = count
	return {
		"architecture": "shared_material_fixed_imprint_field",
		"draw_calls": 0,
		"material_count": PROFILE_MATERIAL_KEYS.size(),
		"imprint_capacity_per_material": IMPRINT_COUNT,
		"live_foot_slots": LIVE_FOOT_COUNT,
		"trail_slots": IMPRINT_COUNT - LIVE_FOOT_COUNT,
		"active_profile": _active_profile,
		"active_imprints": active_imprints,
		"emitted_trails": _emitted_trail_count,
	}

class_name GroundImpactEffects
extends Node3D
## Constant-budget takeoff and landing feedback for solid ground.
##
## Two reusable event slots each own one soft-puff and one fleck emitter.
## Nothing is created per tile or per jump, and surface identity only changes
## the palette, particle motion, and audio of those four fixed draw calls.

const EVENT_SLOT_COUNT := 2
const DUST_PARTICLE_BUDGET := 8
const FLECK_PARTICLE_BUDGET := 7

var _core: GameCore
var _player: PlayerController
var _audio: GameAudio
var _palette: CozyPalette
var _dust_emitters: Array[GPUParticles3D] = []
var _fleck_emitters: Array[GPUParticles3D] = []
var _slot_cursor := 0
var _takeoff_count := 0
var _landing_count := 0
var _last_surface_profile := ""
var _last_impact_speed := 0.0
var _visual_punch: Tween
var _visual_rest_scale := Vector3.ONE


func setup(
	game_core: GameCore,
	player_controller: PlayerController,
	game_audio: GameAudio,
	palette: CozyPalette
) -> void:
	_core = game_core
	_player = player_controller
	_audio = game_audio
	_palette = palette
	if _dust_emitters.is_empty():
		_build_emitter_pool()
	if not _player.ground_jump_started.is_connected(_on_ground_jump_started):
		_player.ground_jump_started.connect(_on_ground_jump_started)
	if not _player.ground_landed.is_connected(_on_ground_landed):
		_player.ground_landed.connect(_on_ground_landed)
	if _player.visual != null:
		_visual_rest_scale = _player.visual.scale


func _on_ground_jump_started(
	surface_position: Vector3,
	coord: Vector2i
) -> void:
	var profile := surface_profile_at(coord)
	if profile == "water":
		return
	_takeoff_count += 1
	_last_surface_profile = profile
	_emit(profile, surface_position, 0.58, false)
	_play_surface_audio(profile, false, 0.58)
	_punch_takeoff()


func _on_ground_landed(
	surface_position: Vector3,
	coord: Vector2i,
	impact_speed: float
) -> void:
	var profile := surface_profile_at(coord)
	if profile == "water":
		return
	var strength := clampf(
		0.68 + (impact_speed - 2.0) / 7.0,
		0.68,
		1.0
	)
	_landing_count += 1
	_last_surface_profile = profile
	_last_impact_speed = impact_speed
	_emit(profile, surface_position, strength, true)
	_play_surface_audio(profile, true, strength)
	_punch_landing(strength)


func surface_profile_at(coord: Vector2i) -> String:
	if _core == null:
		return "grass"
	# A dock or future bridge visually owns the foot contact even though its
	# supporting grid cell is water.
	if _core.grid.has_walkable_structure_surface(coord):
		var state := _core.grid.cell(coord)
		if state != null:
			for structure: WorldGrid.StructureState in state.structures:
				if structure.parent_instance_id != 0:
					continue
				var structure_def := _core.registries.structure(
					structure.structure_id
				)
				if (
					structure_def != null
					and structure_def.collision_profile == "walkable_surface"
				):
					return _profile_from_sound(
						structure_def.placement_sound
					)
	return surface_profile_for_definition(
		_core.grid.top_tile_def(coord)
	)


static func surface_profile_for_definition(
	definition: Defs.TileDefinition
) -> String:
	if definition == null:
		return "grass"
	var tile_id := definition.id.to_lower()
	if (
		definition.surface_kind == "water"
		or definition.water_cells.has("open_water")
	):
		return "water"
	if "mud" in tile_id or "pond" in tile_id:
		return "mud"
	if "sand" in tile_id:
		return "sand"
	if "snow" in tile_id or "frost" in tile_id:
		return "snow"
	if "wood" in tile_id or "plank" in tile_id:
		return "wood"
	if (
		"dirt" in tile_id
		or "garden" in tile_id
		or "clay" in tile_id
	):
		return "earth"
	return _profile_from_sound(definition.placement_sound)


static func _profile_from_sound(sound: String) -> String:
	match sound:
		"stone":
			return "stone"
		"wood":
			return "wood"
		"water":
			return "mud"
		_:
			return "grass"


func _emit(
	profile: String,
	surface_position: Vector3,
	strength: float,
	landing: bool
) -> void:
	var slot := _slot_cursor
	_slot_cursor = (_slot_cursor + 1) % EVENT_SLOT_COUNT
	var dust := _dust_emitters[slot]
	var flecks := _fleck_emitters[slot]
	var tuning := _surface_tuning(profile)
	var colors := _surface_colors(profile)
	var event_scale := strength if landing else strength * 0.82

	_configure_dust(
		dust,
		colors["dust"],
		tuning,
		event_scale,
		landing
	)
	_configure_flecks(
		flecks,
		colors["fleck"],
		tuning,
		event_scale,
		landing
	)
	var at := surface_position + Vector3.UP * 0.025
	dust.global_position = at
	flecks.global_position = at
	dust.emitting = true
	flecks.emitting = true
	dust.restart()
	flecks.restart()


func _configure_dust(
	emitter: GPUParticles3D,
	color: Color,
	tuning: Dictionary,
	event_scale: float,
	landing: bool
) -> void:
	var process := emitter.process_material as ParticleProcessMaterial
	process.color = color
	process.emission_sphere_radius = 0.16 if landing else 0.11
	process.spread = float(tuning["dust_spread"])
	process.initial_velocity_min = (
		float(tuning["dust_velocity"]) * 0.55
	)
	process.initial_velocity_max = (
		float(tuning["dust_velocity"]) * (1.15 if landing else 0.8)
	)
	process.gravity = Vector3(
		0.0,
		-float(tuning["dust_gravity"]),
		0.0
	)
	process.scale_min = float(tuning["dust_scale"]) * 0.65
	process.scale_max = float(tuning["dust_scale"]) * 1.15
	emitter.amount_ratio = clampf(
		float(tuning["dust_amount"]) * event_scale,
		0.12,
		1.0
	)


func _configure_flecks(
	emitter: GPUParticles3D,
	color: Color,
	tuning: Dictionary,
	event_scale: float,
	landing: bool
) -> void:
	var process := emitter.process_material as ParticleProcessMaterial
	process.color = color
	process.emission_sphere_radius = 0.14 if landing else 0.09
	process.spread = float(tuning["fleck_spread"])
	process.initial_velocity_min = (
		float(tuning["fleck_velocity"]) * 0.62
	)
	process.initial_velocity_max = (
		float(tuning["fleck_velocity"]) * (1.18 if landing else 0.82)
	)
	process.gravity = Vector3(
		0.0,
		-float(tuning["fleck_gravity"]),
		0.0
	)
	process.scale_min = float(tuning["fleck_scale"]) * 0.72
	process.scale_max = float(tuning["fleck_scale"]) * 1.2
	emitter.amount_ratio = clampf(
		float(tuning["fleck_amount"]) * event_scale,
		0.12,
		1.0
	)


func _surface_tuning(profile: String) -> Dictionary:
	match profile:
		"sand":
			return {
				"dust_amount": 1.0,
				"dust_velocity": 0.72,
				"dust_gravity": 1.4,
				"dust_scale": 1.15,
				"dust_spread": 82.0,
				"fleck_amount": 0.72,
				"fleck_velocity": 1.12,
				"fleck_gravity": 5.0,
				"fleck_scale": 0.72,
				"fleck_spread": 74.0,
			}
		"snow":
			return {
				"dust_amount": 1.0,
				"dust_velocity": 0.62,
				"dust_gravity": 0.85,
				"dust_scale": 1.28,
				"dust_spread": 88.0,
				"fleck_amount": 0.82,
				"fleck_velocity": 0.82,
				"fleck_gravity": 2.6,
				"fleck_scale": 0.82,
				"fleck_spread": 82.0,
			}
		"stone":
			return {
				"dust_amount": 0.52,
				"dust_velocity": 0.58,
				"dust_gravity": 2.2,
				"dust_scale": 0.8,
				"dust_spread": 72.0,
				"fleck_amount": 0.9,
				"fleck_velocity": 1.28,
				"fleck_gravity": 7.2,
				"fleck_scale": 0.7,
				"fleck_spread": 66.0,
			}
		"wood":
			return {
				"dust_amount": 0.34,
				"dust_velocity": 0.52,
				"dust_gravity": 2.0,
				"dust_scale": 0.72,
				"dust_spread": 68.0,
				"fleck_amount": 0.86,
				"fleck_velocity": 1.18,
				"fleck_gravity": 6.0,
				"fleck_scale": 0.82,
				"fleck_spread": 70.0,
			}
		"earth", "mud":
			return {
				"dust_amount": 0.86,
				"dust_velocity": 0.66,
				"dust_gravity": 1.6,
				"dust_scale": 1.02,
				"dust_spread": 80.0,
				"fleck_amount": 0.66,
				"fleck_velocity": 0.94,
				"fleck_gravity": 4.8,
				"fleck_scale": 0.78,
				"fleck_spread": 76.0,
			}
		_:
			return {
				"dust_amount": 0.62,
				"dust_velocity": 0.62,
				"dust_gravity": 1.8,
				"dust_scale": 0.86,
				"dust_spread": 76.0,
				"fleck_amount": 0.88,
				"fleck_velocity": 1.02,
				"fleck_gravity": 5.2,
				"fleck_scale": 0.82,
				"fleck_spread": 74.0,
			}


func _surface_colors(profile: String) -> Dictionary:
	match profile:
		"sand":
			return {
				"dust": _color("sand_top", 0.5).lightened(0.12),
				"fleck": _color("sand_top", 0.94).darkened(0.12),
			}
		"snow":
			return {
				"dust": _color("warm_white", 0.5).lightened(0.12),
				"fleck": _color("snow_side", 0.9).lightened(0.1),
			}
		"stone":
			return {
				"dust": _color("concrete_top", 0.34).lightened(0.08),
				"fleck": _color("stone_mid", 0.94).darkened(0.08),
			}
		"wood":
			return {
				"dust": _color("wood_light", 0.3),
				"fleck": _color("wood_primary", 0.96),
			}
		"earth":
			return {
				"dust": _color("earth_light", 0.42),
				"fleck": _color("earth_mid", 0.94),
			}
		"mud":
			return {
				"dust": _color("earth_shadow", 0.4),
				"fleck": _color("earth_deep", 0.94),
			}
		_:
			return {
				"dust": _color("earth_light", 0.3),
				"fleck": _color("grass_highlight", 0.94),
			}


func _color(key: String, alpha: float) -> Color:
	var result := _palette.color(key, _palette.color("neutral_white"))
	result.a = alpha
	return result


func _play_surface_audio(
	profile: String,
	landing: bool,
	strength: float
) -> void:
	if _audio == null:
		return
	var event := "footstep_grass"
	var pitch := 1.0
	var volume_offset := -3.5 if landing else -6.5
	match profile:
		"sand":
			pitch = 0.84
		"snow":
			pitch = 0.72
			volume_offset -= 1.0
		"stone":
			event = "footstep_stone"
			pitch = 0.9
		"wood":
			event = "place_wood"
			pitch = 1.08
			volume_offset -= 5.0
		"mud":
			event = "place_water"
			pitch = 0.82
			volume_offset -= 6.0
		"earth":
			pitch = 0.92
	_audio.play_event(
		event,
		volume_offset + lerpf(-1.2, 0.8, strength),
		pitch
	)


func _punch_takeoff() -> void:
	if _player == null or _player.visual == null:
		return
	_kill_visual_punch()
	var target := _player.visual
	target.scale = _visual_rest_scale * Vector3(1.055, 0.91, 1.055)
	_visual_punch = target.create_tween()
	_visual_punch.tween_property(
		target,
		"scale",
		_visual_rest_scale * Vector3(0.965, 1.075, 0.965),
		0.075
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_visual_punch.tween_property(
		target,
		"scale",
		_visual_rest_scale,
		0.11
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _punch_landing(strength: float) -> void:
	if _player == null or _player.visual == null:
		return
	_kill_visual_punch()
	var target := _player.visual
	target.scale = _visual_rest_scale * Vector3(
		1.0 + 0.09 * strength,
		1.0 - 0.14 * strength,
		1.0 + 0.09 * strength
	)
	_visual_punch = target.create_tween()
	_visual_punch.tween_property(
		target,
		"scale",
		_visual_rest_scale * Vector3(0.98, 1.035, 0.98),
		0.07
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_visual_punch.tween_property(
		target,
		"scale",
		_visual_rest_scale,
		0.1
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _kill_visual_punch() -> void:
	if _visual_punch != null and _visual_punch.is_valid():
		_visual_punch.kill()


func _build_emitter_pool() -> void:
	for slot in EVENT_SLOT_COUNT:
		var dust := _particle_emitter(
			"GroundImpactDust%d" % slot,
			DUST_PARTICLE_BUDGET,
			0.34,
			_puff_mesh()
		)
		var flecks := _particle_emitter(
			"GroundImpactFlecks%d" % slot,
			FLECK_PARTICLE_BUDGET,
			0.42,
			_fleck_mesh()
		)
		_dust_emitters.append(dust)
		_fleck_emitters.append(flecks)
		add_child(dust)
		add_child(flecks)


func _particle_emitter(
	emitter_name: String,
	particle_count: int,
	particle_lifetime: float,
	draw_mesh: Mesh
) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = emitter_name
	emitter.amount = particle_count
	emitter.lifetime = particle_lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.96
	emitter.randomness = 0.72
	# Each pooled slot remains fixed for the complete burst. Local simulation
	# avoids applying the world-space emitter transform twice on some Vulkan
	# drivers while still leaving no player-following particles.
	emitter.local_coords = true
	emitter.fixed_fps = 45
	emitter.interpolate = true
	emitter.fract_delta = true
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(
		Vector3(-1.5, -0.35, -1.5),
		Vector3(3.0, 2.5, 3.0)
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.direction = Vector3.UP
	process.angular_velocity_min = -180.0
	process.angular_velocity_max = 180.0
	process.damping_min = 0.25
	process.damping_max = 0.9
	process.color_ramp = _particle_fade_ramp()
	emitter.process_material = process
	emitter.draw_pass_1 = draw_mesh
	emitter.emitting = false
	return emitter


func _puff_mesh() -> SphereMesh:
	var puff := SphereMesh.new()
	puff.radius = 0.05
	puff.height = 0.09
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = _particle_material()
	return puff


func _fleck_mesh() -> BoxMesh:
	var fleck := BoxMesh.new()
	fleck.size = Vector3(0.044, 0.018, 0.03)
	fleck.material = _particle_material()
	return fleck


func _particle_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _palette.color("ui_white")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	return material


func _particle_fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(_palette.color("ui_white"), 0.0),
		_palette.color("ui_white"),
		Color(_palette.color("ui_white"), 0.72),
		Color(_palette.color("ui_white"), 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func runtime_manifest() -> Dictionary:
	return {
		"renderer": "pooled_gpu_particles",
		"event_slots": EVENT_SLOT_COUNT,
		"particle_draw_call_budget": EVENT_SLOT_COUNT * 2,
		"dust_particle_budget": DUST_PARTICLE_BUDGET * EVENT_SLOT_COUNT,
		"fleck_particle_budget": FLECK_PARTICLE_BUDGET * EVENT_SLOT_COUNT,
		"takeoff_count": _takeoff_count,
		"landing_count": _landing_count,
		"last_surface_profile": _last_surface_profile,
		"last_impact_speed": _last_impact_speed,
		"per_tile_nodes": 0,
		"world_size_dependent": false,
	}

class_name LandmarkEncounter
extends Node3D

var _color_system := PaletteDefinition.shared()
## Scene-side lifecycle of one revealed landmark: spawns surviving enemies +
## guardian from saved state, resets them when the player falls, and plants
## the reclaim prompt marker once the site turns peaceful.

var core: GameCore
var assets: AssetLibrary
var state: LandmarkManager.LandmarkState
var player: PlayerController
var _prompt: Node3D


func setup(game_core: GameCore, asset_library: AssetLibrary, landmark_state: LandmarkManager.LandmarkState, player_controller: PlayerController) -> void:
	core = game_core
	assets = asset_library
	state = landmark_state
	player = player_controller
	core.combat.player_defeated.connect(_on_player_defeated)
	core.landmarks.landmark_reclaimed.connect(_on_reclaimed)
	core.landmarks.landmark_resolved.connect(_on_resolved)
	if state.phase == LandmarkManager.PHASE_REVEALED:
		_spawn_all()
	elif state.phase == LandmarkManager.PHASE_RECLAIMED:
		_plant_prompt()


func _spawn_all() -> void:
	var def := core.registries.landmark(state.landmark_id)
	var cells := core.landmarks.footprint_cells(state)
	var index := 0
	for slot in state.enemies_alive.duplicate():
		var enemy_id: String = slot.get_slice(":", 0)
		var enemy_def := core.registries.enemy(enemy_id)
		if enemy_def == null:
			continue
		var cell: Vector2i = cells[index % cells.size()]
		var offset := Vector3(0.6 if index % 2 == 0 else -0.6, 0, 0.5 if index < 2 else -0.5)
		_spawn(enemy_def, slot, core.grid.cell_to_world(cell) + offset)
		index += 1
	if state.guardian_alive and def.guardian_id != "":
		var guardian_def := core.registries.enemy(def.guardian_id)
		var guardian_cell: Vector2i = cells[cells.size() - 1]
		_spawn(guardian_def, def.guardian_id + ":g", core.grid.cell_to_world(guardian_cell))


func _spawn(enemy_def: Defs.EnemyDefinition, slot: String, point: Vector3) -> void:
	var enemy := Enemy.new()
	add_child(enemy)
	enemy.setup(core, assets, enemy_def, state.landmark_id, slot, point, player)


func _on_player_defeated() -> void:
	for enemy in get_children():
		if enemy is Enemy and enemy.phase != Enemy.Phase.DEAD:
			enemy.reset_to_home()


func _on_reclaimed(reclaimed_state: LandmarkManager.LandmarkState) -> void:
	if reclaimed_state != state:
		return
	_plant_prompt()


func _plant_prompt() -> void:
	if _prompt != null:
		return
	_prompt = Node3D.new()
	_prompt.name = "ReclaimPrompt"
	_prompt.add_to_group("landmark_prompts")
	_prompt.set_meta("landmark_id", state.landmark_id)
	var cells := core.landmarks.footprint_cells(state)
	_prompt.position = core.grid.cell_to_world(cells[0])
	var glow := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.14
	orb.height = 0.28
	glow.mesh = orb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_system.color("vfx_landmark_glow")
	mat.emission_enabled = true
	mat.emission = _color_system.color("vfx_landmark_glow")
	mat.emission_energy_multiplier = 2.5
	glow.material_override = mat
	glow.position.y = 1.1
	_prompt.add_child(glow)
	var tween := glow.create_tween().set_loops()
	tween.tween_property(glow, "position:y", 1.3, 1.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "position:y", 1.1, 1.1).set_trans(Tween.TRANS_SINE)
	add_child(_prompt)


func _on_resolved(resolved_state: LandmarkManager.LandmarkState, _resolution: String) -> void:
	if resolved_state == state and _prompt != null:
		_prompt.queue_free()
		_prompt = null

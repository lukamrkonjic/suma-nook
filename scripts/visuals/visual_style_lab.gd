class_name VisualStyleLab
extends Node3D
## Calibration scene: one of each core asset under the shared lighting rig with
## the fixed comparison camera. Space toggles day/rain. Run headless captures:
##   godot --path . scenes/debug/VisualStyleLab.tscn -- --shot=docs/style_comparisons/lab_day.png
##   godot --path . scenes/debug/VisualStyleLab.tscn -- --shot=docs/style_comparisons/lab_rain.png --rain

const ROSTER := [
	["tile_grass", Vector3(0, 0, 0)], ["tile_garden", Vector3(2.2, 0, 0)],
	["tile_path", Vector3(4.4, 0, 0)], ["tile_grass_pond_edge", Vector3(6.6, 0, 0)],
	["tile_grove_mature", Vector3(0, 0, 2.4)], ["tile_stone_clearing", Vector3(2.2, 0, 2.4)],
	["tile_stone_crystal", Vector3(4.4, 0, 2.4)], ["tile_stone_ruin", Vector3(6.6, 0, 2.4)],
	["prop_pine_b", Vector3(-2.2, 0, 0.6)], ["prop_bush_a", Vector3(-2.0, 0, 2.2)],
	["prop_rock_cluster", Vector3(-2.2, 0, 3.4)], ["prop_pot", Vector3(-1.4, 0, 4.0)],
	["prop_flowers_pink", Vector3(-2.0, 0, 4.6)], ["prop_bench", Vector3(0, 0, 4.6)],
	["prop_fence", Vector3(2.2, 0, 4.6)], ["prop_lantern", Vector3(3.6, 0, 4.6)],
	["prop_campfire", Vector3(5.0, 0, 4.6)], ["prop_shelter", Vector3(7.6, 0, 4.6)],
	["prop_stump", Vector3(-1.2, 0, 0.2)], ["character_proxy", Vector3(3.3, 0.02, 1.2)],
]

var lighting: LightingRig


func _ready() -> void:
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)

	lighting = (load("res://scenes/visual/GGDayLightingRig.tscn") as PackedScene).instantiate()
	add_child(lighting)

	for entry in ROSTER:
		var node := assets.instantiate(entry[0])
		node.position = entry[1]
		add_child(node)
		if entry[0].begins_with("tile_"):
			continue

	# Fixed comparison camera — same yaw/pitch family as gameplay.
	var pivot := Node3D.new()
	pivot.position = Vector3(2.6, 0, 2.2)
	pivot.rotation_degrees.y = 45.0
	add_child(pivot)
	var pitch := Node3D.new()
	pitch.rotation_degrees.x = -34.0
	pivot.add_child(pitch)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.0
	camera.position = Vector3(0, 0, 40)
	pitch.add_child(camera)
	camera.current = true

	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--rain"):
		lighting.apply_profile(lighting.rain_profile)
	for arg in user_args:
		if arg.begins_with("--shot="):
			var shot_path := arg.trim_prefix("--shot=")
			get_tree().create_timer(1.8).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(shot_path)
				print("SHOT SAVED: " + shot_path)
				get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dodge"):
		lighting.toggle_profile()

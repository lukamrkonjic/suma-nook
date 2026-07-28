extends Node
## Loads a copy of the player's real save, captures the settled frame, and
## dumps the live lighting manifest — for diagnosing "my game looks different".

const SAVE_PATH := "user://gg_user_world_probe.json"

var _main: Main
var _output_dir := "res://artifacts/gg_exact"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	# Probe runs on a copy so the real save is never touched.
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("user://suma_nook_world.json"),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(1.5).timeout
	if not _main._gameplay_started:
		push_error("User-world probe did not reach gameplay (no save loaded?)")
		get_tree().quit(1)
		return
	for frame in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join("user_world_noon.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("  [probe shot] %s" % path)
	var manifest := _main.lighting.runtime_manifest()
	var env_info := {
		"profile": manifest["runtime_state"],
		"tonemap_mode": manifest["post_processing"]["tonemap_mode"],
		"grade": manifest["gg_grade_pass"],
		"glow": {
			"enabled": manifest["post_processing"]["bloom_enabled"],
			"threshold": manifest["post_processing"]["bloom_hdr_threshold"],
		},
		"ssao": manifest["post_processing"]["ssao_enabled"],
		"hdr_2d": ProjectSettings.get_setting("rendering/viewport/hdr_2d"),
		"sun_rotation": manifest["directional_light"]["rotation_degrees"],
	}
	print("PROBE_MANIFEST ", JSON.stringify(env_info))
	get_tree().quit(0)

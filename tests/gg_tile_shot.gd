extends Node
## One-shot capture of the opening world, for closed-loop colour matching
## against the Garden Galaxy screen targets. Deliberately minimal: the tile
## being matched fills the frame, so a single render carries every one of its
## materials -- top, side, lower and scatter -- at once.

const OUTPUT := "res://artifacts/gg_match/world.png"

var main: Main


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://artifacts/gg_match")
	)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = "user://gg_tile_shot_save.json"
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.4).timeout
	main.camera_rig.set_zoom_immediate(9.0)
	await get_tree().create_timer(0.7).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	# The 2D buffer is linear; the display blit applies the sRGB encode. A
	# capture judged without it reads far darker and more saturated.
	GGCaptureEncode.encode_srgb(image)
	var path := ProjectSettings.globalize_path(OUTPUT)
	if image.save_png(path) == OK:
		print("GG TILE SHOT: %s" % path)
	else:
		push_error("could not save GG tile shot")
	get_tree().quit()

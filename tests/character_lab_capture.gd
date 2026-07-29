extends Node3D
## Captures the character lab from its three cameras plus a socket-marker
## debug view, validating the standalone assembler path (no AssetLibrary).

const OUTPUT_DIR := "res://artifacts/character_lab"
const LAB_SCENE := preload("res://characters/lab/character_lab.tscn")

# Typed as Node3D: the lab's class_name may not be in the global class cache
# yet when this scene is launched directly from the command line.
var _lab: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_lab = LAB_SCENE.instantiate() as Node3D
	add_child(_lab)
	await _settle(14)
	for camera_name in ["front", "three_quarter", "game"]:
		_lab._activate_camera(camera_name)
		await _settle(4)
		await _capture("lab_%s.png" % camera_name)
	_lab.set("show_sockets", true)
	_lab._activate_camera("three_quarter")
	await _settle(4)
	await _capture("lab_sockets.png")
	_lab.set("show_sockets", false)
	var assembler: CharacterAssembler = _lab.get("assembler")
	assembler.set_slot_visible(CharacterSlots.HAIR, false)
	await _settle(4)
	await _capture("lab_no_hair.png")
	assembler.set_slot_visible(CharacterSlots.HAIR, true)
	assembler.set_slot_visible(CharacterSlots.MOUSTACHE, false)
	await _settle(4)
	await _capture("lab_no_moustache.png")
	get_tree().quit(0)


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var path := OUTPUT_DIR.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s (error %d)" % [path, error])
		get_tree().quit(1)
	else:
		print("LAB_CAPTURE ", path)

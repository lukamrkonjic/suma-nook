extends SceneTree
## Packs an already audited Clothing Lab GLB into the binary PackedScene used
## by CharacterPartDefinition. This is intentionally geometry-neutral: the
## Blender processor owns all repair, topology validation, fitting and skinning.
##
## Run:
##   godot --headless --path . --script \
##     res://tools/clothing_lab/finalize_runtime_scene.gd -- \
##     --source=res://assets/characters/parts/top_jacket_cozy.glb \
##     --destination=res://assets/characters/parts/generated/top_jacket_cozy.scn

const DEFAULT_SOURCE := (
	"res://assets/characters/parts/top_jacket_cozy.glb"
)
const DEFAULT_DESTINATION := (
	"res://assets/characters/parts/generated/top_jacket_cozy.scn"
)


func _initialize() -> void:
	var options := _parse_options()
	var source := String(options.get("source", DEFAULT_SOURCE))
	var destination := String(
		options.get("destination", DEFAULT_DESTINATION)
	)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(
		ProjectSettings.globalize_path(source),
		state,
	)
	if error != OK:
		printerr("Could not load audited garment GLB: ", source)
		quit(1)
		return
	var root := document.generate_scene(state)
	if root == null:
		printerr("Audited garment GLB generated an empty scene: ", source)
		quit(1)
		return
	var packed := PackedScene.new()
	error = packed.pack(root)
	root.free()
	if error != OK:
		printerr("Could not pack garment runtime scene: ", error)
		quit(1)
		return
	var absolute_destination := ProjectSettings.globalize_path(destination)
	DirAccess.make_dir_recursive_absolute(
		absolute_destination.get_base_dir()
	)
	error = ResourceSaver.save(packed, destination)
	if error != OK:
		printerr("Could not save garment runtime scene: ", error)
		quit(1)
		return
	print(
		"CLOTHING_RUNTIME_SCENE_FINALIZED source=",
		source,
		" destination=",
		destination,
	)
	quit(0)


func _parse_options() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or "=" not in argument:
			continue
		var parts := argument.trim_prefix("--").split("=", true, 1)
		result[String(parts[0])] = String(parts[1])
	return result

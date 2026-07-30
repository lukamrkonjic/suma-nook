extends SceneTree
## Focused regression for the published footwear asset, its default runtime
## equipment, and Clothing Lab catalog exposure.

const PART_PATH := (
	"res://assets/characters/parts/defs/shoes_sneakers.tres"
)
const PRESET_PATH := (
	"res://assets/characters/presets/default_male_appearance.tres"
)
const LAB_SCENE := preload("res://characters/lab/clothing_lab.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var part := load(PART_PATH) as CharacterPartDefinition
	if (
		part == null
		or part.slot != CharacterSlots.SHOES
		or part.scene == null
		or part.clothing_fit == null
		or part.clothing_fit.garment_class != "footwear"
		or not part.validation_errors().is_empty()
	):
		_fail("Published sneakers definition is not runtime-ready.")
		return

	var preset := load(PRESET_PATH) as CharacterAppearancePreset
	if (
		preset == null
		or preset.part_in_slot(CharacterSlots.SHOES) != part
	):
		_fail("Default appearance does not equip the published sneakers.")
		return

	var assembler := CharacterAssembler.new()
	var body := assembler.assemble(preset)
	if (
		body == null
		or assembler.equipped_part(CharacterSlots.SHOES) != part
		or assembler.equipped_node(CharacterSlots.SHOES) == null
		or not assembler.last_warnings.is_empty()
	):
		if body != null:
			body.free()
		_fail("Runtime character could not assemble the sneakers.")
		return
	body.free()

	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	for _frame in 6:
		await process_frame
	var slot_options: Dictionary = lab.get("_slot_options")
	var shoes_option := slot_options.get(CharacterSlots.SHOES) as OptionButton
	if shoes_option == null or not _option_has_part(
		shoes_option, part.part_id
	):
		lab.free()
		_fail("Clothing Lab does not expose Sneakers in its Shoes selector.")
		return
	var clothing_list := lab.get("_clothing_list") as ItemList
	if clothing_list == null or not _list_has_part(
		clothing_list, part.part_id
	):
		lab.free()
		_fail("Clothing Lab does not expose Sneakers as an editable asset.")
		return
	var lab_assembler := lab.get("assembler") as CharacterAssembler
	if (
		lab_assembler == null
		or lab_assembler.equipped_part(CharacterSlots.SHOES) != part
		or lab_assembler.equipped_node(CharacterSlots.SHOES) == null
	):
		lab.free()
		_fail("Clothing Lab preview did not equip the default sneakers.")
		return
	lab.call("_select_clothing_part", part)
	for _frame in 2:
		await process_frame
	var original_position := part.clothing_fit.position
	var centers_before := _shoe_centers(lab)
	part.clothing_fit.position = Vector3(0.01, 0.02, 0.0)
	lab.call("_preview_fit")
	await process_frame
	var centers_after := _shoe_centers(lab)
	part.clothing_fit.position = original_position
	if not (
		is_equal_approx(
			centers_after[0].x - centers_before[0].x,
			0.01,
		)
		and is_equal_approx(
			centers_after[1].x - centers_before[1].x,
			-0.01,
		)
		and is_equal_approx(
			centers_after[0].z - centers_before[0].z,
			-0.02,
		)
		and is_equal_approx(
			centers_after[1].z - centers_before[1].z,
			0.02,
		)
	):
		lab.free()
		_fail("Footwear X/Y offsets did not move the shoes as mirrors.")
		return
	lab.free()
	print("SHOES_INTEGRATION_TEST PASSED")
	quit(0)


func _option_has_part(option: OptionButton, part_id: String) -> bool:
	for index in option.item_count:
		if String(option.get_item_metadata(index)) == part_id:
			return true
	return false


func _list_has_part(list: ItemList, part_id: String) -> bool:
	for index in list.item_count:
		if String(list.get_item_metadata(index)) == part_id:
			return true
	return false


func _shoe_centers(lab: Node) -> Array[Vector3]:
	var surfaces: Array = lab.get("_raw_deformed_vertices")
	var totals := [Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0]
	for surface in surfaces:
		for point: Vector3 in surface:
			var side_index := 0 if point.x >= 0.0 else 1
			totals[side_index] += point
			counts[side_index] += 1
	return [
		totals[0] / maxf(counts[0], 1),
		totals[1] / maxf(counts[1], 1),
	]


func _fail(message: String) -> void:
	printerr(message)
	quit(1)

extends Node
## Regression: an Appearance clothing choice must become the garment being
## edited and rendered in Rest/T-pose as well as the bound animated preview.

const LAB := preload("res://characters/lab/clothing_lab.tscn")
const TOP_OUTER := "TOP_OUTER"
const VEST_ID := "top_tweed_vest"
const JACKET_ID := "top_jacket_cozy"


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)


func _option_index(option: OptionButton, part_id: String) -> int:
	for index in option.item_count:
		if String(option.get_item_metadata(index)) == part_id:
			return index
	return -1


func _selected_list_id(list: ItemList) -> String:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return ""
	return String(list.get_item_metadata(selected[0]))


func _ready() -> void:
	var lab := LAB.instantiate()
	add_child(lab)
	for _frame in 8:
		await get_tree().process_frame

	var slot_options: Dictionary = lab.get("_slot_options")
	var top_outer := slot_options.get(TOP_OUTER) as OptionButton
	var clothing_list := lab.get("_clothing_list") as ItemList
	if top_outer == null or clothing_list == null:
		_fail("Clothing selection controls are unavailable.")
		return
	var vest_index := _option_index(top_outer, VEST_ID)
	var jacket_index := _option_index(top_outer, JACKET_ID)
	if vest_index < 0 or jacket_index < 0:
		_fail("Clothing selection regression assets are unavailable.")
		return

	top_outer.select(vest_index)
	lab.call("_on_appearance_selected", TOP_OUTER, vest_index)
	for _frame in 4:
		await get_tree().process_frame
	var selected_part := lab.get("_selected_part") as CharacterPartDefinition
	var raw_preview := lab.get("_raw_preview") as MeshInstance3D
	var assembler: CharacterAssembler = lab.get("assembler")
	var equipped := assembler.equipped_part(TOP_OUTER)
	var equipped_node := assembler.equipped_node(TOP_OUTER)
	if (
		selected_part == null
		or selected_part.part_id != VEST_ID
		or _selected_list_id(clothing_list) != VEST_ID
		or equipped == null
		or equipped.part_id != VEST_ID
		or raw_preview == null
		or not raw_preview.name.contains(VEST_ID)
		or not raw_preview.visible
		or equipped_node == null
		or equipped_node.visible
	):
		_fail(
			"Rest/T-pose did not synchronize the Tweed Vest across "
			+ "Appearance, editing selection, raw preview, and equipped slot."
		)
		return

	var pose_option := lab.get("_preview_pose_option") as OptionButton
	var walk_index := _option_index(pose_option, "walk")
	if walk_index < 0:
		_fail("Walk preview is unavailable.")
		return
	pose_option.select(walk_index)
	lab.call("_on_preview_pose_selected", walk_index)
	for _frame in 4:
		await get_tree().process_frame
	if raw_preview.visible or not equipped_node.visible:
		_fail("Animated preview did not switch to the bound Tweed Vest.")
		return

	pose_option.select(0)
	lab.call("_on_preview_pose_selected", 0)
	for _frame in 4:
		await get_tree().process_frame
	if not raw_preview.visible or equipped_node.visible:
		_fail("Returning to Rest/T-pose restored the wrong garment layer.")
		return

	top_outer.select(jacket_index)
	lab.call("_on_appearance_selected", TOP_OUTER, jacket_index)
	for _frame in 4:
		await get_tree().process_frame
	selected_part = lab.get("_selected_part") as CharacterPartDefinition
	raw_preview = lab.get("_raw_preview") as MeshInstance3D
	if (
		selected_part == null
		or selected_part.part_id != JACKET_ID
		or _selected_list_id(clothing_list) != JACKET_ID
		or raw_preview == null
		or not raw_preview.name.contains(JACKET_ID)
		or not raw_preview.visible
	):
		_fail("Switching back to the jacket did not update Rest/T-pose.")
		return

	print("CLOTHING SELECTION SYNC TEST PASSED")
	get_tree().quit(0)

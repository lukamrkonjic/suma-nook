class_name ProjectPanel
extends CanvasLayer
## Compact tracked-Project HUD plus a controller-complete modal for choosing,
## inspecting, and contributing reserved Special Finds.

signal panel_toggled(open: bool)

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _root: Control
var _chip: Button
var _modal: Control
var _card: PanelContainer
var _content: VBoxContainer
var _first_button: Button


func setup(game_core: GameCore, ui_kit: UiKit) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()
	layer = 3
	_build_root()
	core.projects.tracked_project_changed.connect(func(_project): refresh())
	core.projects.project_progressed.connect(func(_project, _slot):
		refresh()
		_pulse_chip()
	)
	core.projects.project_completed.connect(func(_project): refresh())
	core.projects.offers_changed.connect(func(_offers): refresh())
	core.finds.reserve_changed.connect(refresh)
	if _input_service != null:
		_input_service.input_method_changed.connect(func(_method): refresh())
	refresh()


func _build_root() -> void:
	_root = Control.new()
	_root.name = "ProjectRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)

	_chip = kit.button("Choose a Project", true)
	_chip.name = "TrackedProject"
	_chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chip.offset_left = 16.0
	_chip.offset_right = 390.0
	_chip.offset_top = 16.0
	_chip.offset_bottom = 66.0
	_chip.focus_mode = Control.FOCUS_ALL
	_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chip.pressed.connect(toggle)
	_root.add_child(_chip)


func refresh() -> void:
	if _chip == null:
		return
	var project: Dictionary = core.projects.tracked_project()
	if project.is_empty():
		_chip.text = "Choose a Project"
		_chip.tooltip_text = _open_prompt("Choose a Project and contribute a few things from your world.")
	else:
		_chip.text = "%s  %s" % [
			String(project.get("name", "Project")),
			_progress_text(project),
		]
		_chip.tooltip_text = _open_prompt("Inspect the tracked Project.")
	if is_open():
		_rebuild_content()


func is_open() -> bool:
	return _modal != null and is_instance_valid(_modal)


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open(project_id := "") -> void:
	if not project_id.is_empty():
		core.projects.track(project_id)
	if is_open():
		_rebuild_content()
		focus_default()
		return
	_modal = Control.new()
	_modal.name = "ProjectModal"
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.theme = kit.theme
	_root.add_child(_modal)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.08, 0.07, 0.1, 0.64)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 18.0
	center.offset_right = -18.0
	center.offset_top = 18.0
	center.offset_bottom = -18.0
	_modal.add_child(center)

	_card = kit.card()
	_card.custom_minimum_size = Vector2(620.0, 420.0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_card.add_child(_content)
	_rebuild_content()
	panel_toggled.emit(true)
	focus_default()


func open_frontier(coord: Vector2i) -> bool:
	var project: Dictionary = core.frontiers.open(coord)
	if project.is_empty():
		return false
	open(String(project.get("id", "")))
	core.save()
	return true


func close() -> void:
	if not is_open():
		return
	if _input_service != null:
		_input_service.release_focus_in(_modal)
	var old := _modal
	_modal = null
	_card = null
	_content = null
	_first_button = null
	old.queue_free()
	panel_toggled.emit(false)


func focus_default() -> void:
	if is_open() and _input_service != null:
		_input_service.focus_first(_modal, _first_button)


func blocks_world_pointer(screen_position: Vector2) -> bool:
	if is_open():
		return true
	return _chip != null and _chip.visible and _chip.get_global_rect().has_point(screen_position)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild_content() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_first_button = null
	_content.add_child(kit.eyebrow("PROJECTS", kit.palette.color("ui_accent")))
	_content.add_child(kit.label("Choose one clear goal", 28, false, true))
	_content.add_child(kit.muted_label(
		"Common gathering goes straight to the tracked Project. Progress stays when you switch.",
		13
	))

	var tracked: Dictionary = core.projects.tracked_project()
	if not tracked.is_empty():
		_add_project_detail(tracked)
	else:
		_content.add_child(kit.muted_label("Nothing tracked yet — choose an offer below.", 14))

	var reserve := core.finds.entries()
	if not reserve.is_empty():
		var reserve_words: Array[String] = []
		for entry: Dictionary in reserve:
			reserve_words.append("%s ×%d" % [entry.get("name", "Find"), entry.get("amount", 0)])
		_content.add_child(kit.muted_label("Special Finds: %s" % ", ".join(reserve_words), 13))

	_content.add_child(kit.eyebrow("COLLECTION OFFERS", kit.palette.color("ui_good")))
	var offers := HFlowContainer.new()
	offers.alignment = FlowContainer.ALIGNMENT_CENTER
	offers.add_theme_constant_override("h_separation", 8)
	offers.add_theme_constant_override("v_separation", 8)
	_content.add_child(offers)
	for project: Dictionary in core.projects.collection_offers():
		var button := kit.button("%s\n%s" % [
			String(project.get("name", "Collection Project")).trim_suffix(" Project"),
			_progress_text(project),
		], String(project.get("id", "")) == core.projects.tracked_project_id)
		button.custom_minimum_size = Vector2(180.0, 64.0)
		button.tooltip_text = "Track this Project. Its exact reward is already reserved and cannot reroll."
		var project_id := String(project.get("id", ""))
		button.pressed.connect(func(): _track(project_id))
		offers.add_child(button)
		if _first_button == null:
			_first_button = button

	var close_button := kit.button("Back to the world")
	close_button.tooltip_text = "Close Projects."
	close_button.pressed.connect(close)
	_content.add_child(close_button)
	if _first_button == null:
		_first_button = close_button


func _add_project_detail(project: Dictionary) -> void:
	var heading := kit.label(String(project.get("name", "Project")), 20, false, true)
	_content.add_child(heading)
	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 7)
	slots.add_theme_constant_override("v_separation", 7)
	_content.add_child(slots)
	var project_id := String(project.get("id", ""))
	var raw_slots: Array = project.get("slots", [])
	for index in raw_slots.size():
		var slot: Dictionary = raw_slots[index]
		var current := int(slot.get("current", 0))
		var required := int(slot.get("required", 1))
		var complete := current >= required
		var label := "%s %s" % ["✓" if complete else "○", slot.get("name", "Contribution")]
		if bool(slot.get("consumes_find", false)) and not complete:
			var find_id := _find_id(slot)
			var spend := kit.button("%s — use reserved Find" % label, core.finds.amount(find_id) > 0)
			spend.disabled = core.finds.amount(find_id) <= 0
			spend.tooltip_text = (
				"Contribute one reserved %s." % String(slot.get("name", "Find"))
				if not spend.disabled else "Discover this Special Find in the world first."
			)
			spend.pressed.connect(func(): _spend_find(project_id, index))
			slots.add_child(spend)
			if _first_button == null and not spend.disabled:
				_first_button = spend
		else:
			var pill := kit.button(label, complete)
			pill.disabled = true
			pill.tooltip_text = "%d of %d contributed" % [current, required]
			slots.add_child(pill)
	if bool(project.get("complete", false)):
		var complete_copy := (
			"Ready — click its frontier dot to unfold the land."
			if String(project.get("type", "")) == ProjectService.TYPE_FRONTIER
			else "Complete — the reward is on its way."
		)
		_content.add_child(kit.label(complete_copy, 14, false, true))
	elif String(project.get("type", "")) == ProjectService.TYPE_FRONTIER:
		var metadata: Dictionary = project.get("frontier_metadata", {})
		_content.add_child(kit.muted_label(
			String(metadata.get("preview", "A new place waits beyond the boundary.")), 13
		))


func _track(project_id: String) -> void:
	core.projects.track(project_id)
	core.autosave_soon()
	refresh()
	focus_default()


func _spend_find(project_id: String, slot_index: int) -> void:
	core.projects.spend_find(project_id, slot_index)
	core.save()
	refresh()
	focus_default()


func _progress_text(project: Dictionary) -> String:
	var words: Array[String] = []
	for slot: Dictionary in project.get("slots", []):
		var current := int(slot.get("current", 0))
		var required := int(slot.get("required", 1))
		words.append("%s %s" % ["✓" if current >= required else "○", slot.get("name", "")])
	return "  ".join(words)


func _find_id(slot: Dictionary) -> String:
	for raw_tag: Variant in slot.get("accepted_tags", []):
		var tag := String(raw_tag)
		if tag.begins_with("find:"):
			return tag.trim_prefix("find:")
	return ""


func _open_prompt(base: String) -> String:
	if _input_service == null:
		return base
	return "%s %s" % [base, _input_service.format_action(&"project_menu", "Open Projects")]


func _pulse_chip() -> void:
	if _chip == null or not is_inside_tree():
		return
	_chip.pivot_offset = _chip.size * 0.5
	var tween := _chip.create_tween()
	tween.tween_property(_chip, "scale", Vector2(1.045, 1.045), 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_chip, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

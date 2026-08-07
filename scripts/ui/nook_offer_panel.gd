class_name NookOfferPanel
extends CanvasLayer
## Opening-only seed ritual. Later expansion happens directly at world-space
## frontier glows; the non-opening methods remain solely to hydrate
## old pending offers without breaking older saves and test fixtures.

signal offer_accepted(coord: Vector2i)
## First boot only: the chosen seed card, before any world exists.
signal first_seed_chosen(card: Dictionary)

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _root: Control
var _chip: Button
var _first_button: Button
## While true the panel is the opening ritual: no dismissal, no chip, and
## accepting hands the raw card to Main instead of revealing directly.
var first_boot := false

const DENSITY_WORDS := {
	"open": "Open — airy ground, few features",
	"seeded": "Seeded — scattered young growth",
	"grown": "Grown — thick, old, and full of secrets",
}


func setup(game_core: GameCore, ui_kit: UiKit) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()
	# Calm HUD: a small quiet sprout in the corner, words only on hover.
	# Controller players reach the same offer through the Atlas (panel_map).
	_chip = kit.button("🌱")
	_chip.name = "NookOfferChip"
	_chip.visible = false
	_chip.anchor_left = 1.0
	_chip.anchor_right = 1.0
	_chip.offset_left = -62.0
	_chip.offset_right = -16.0
	_chip.offset_top = 16.0
	_chip.offset_bottom = 62.0
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.add_theme_font_size_override("font_size", 22)
	_chip.modulate.a = 0.75
	_chip.mouse_entered.connect(func(): _chip.modulate.a = 1.0)
	_chip.mouse_exited.connect(func(): _chip.modulate.a = 0.75)
	_chip.pressed.connect(open)
	add_child(_chip)


func _process(_delta: float) -> void:
	# The modal is now opening-only. Later Nooks are grown directly from
	# world-space frontier glows, so no earned offer chip appears.
	_chip.visible = false


func is_open() -> bool:
	return _root != null


func open() -> void:
	if is_open() or core == null:
		return
	var offers: NookOffers = core.nooks.offers
	if not offers.has_pending():
		if offers.make_offer().is_empty():
			return
	_build_modal()


## The opening ritual: choosing the first Nook's seed IS starting the game.
func open_for_first_boot() -> void:
	if is_open() or core == null:
		return
	first_boot = true
	var offers: NookOffers = core.nooks.offers
	if not offers.has_pending():
		offers.make_offer(Vector2i.ZERO)
	_build_modal()


func close() -> void:
	if _root == null:
		return
	_input_service.release_focus_in(_root)
	var old := _root
	_root = null
	old.queue_free()


func focus_default() -> void:
	if _root != null and _first_button != null:
		_input_service.focus_first(_root, _first_button)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or first_boot:
		return
	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_modal() -> void:
	var offers: NookOffers = core.nooks.offers
	_root = Control.new()
	_root.name = "NookOfferChoice"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = kit.theme
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = kit.palette.color("ui_arrival_scrim")
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var shell := VBoxContainer.new()
	shell.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_theme_constant_override("separation", 13)
	center.add_child(shell)

	var eyebrow := kit.eyebrow(
		"Your first ground" if first_boot else "The world is ready to grow",
		kit.palette.color("ui_arrival_border")
	)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(eyebrow)
	var title := kit.label(
		"Choose where the world begins" if first_boot
		else "Choose the next Nook's seed",
		34, true, true
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(title)
	var subtitle := kit.label(
		"Only nature arrives. Everything else will be yours to make.",
		15,
		true
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_arrival_subtitle")
	)
	shell.add_child(subtitle)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	shell.add_child(row)
	_first_button = null
	var cards := offers.pending_cards()
	for index in cards.size():
		row.add_child(_seed_card(cards[index] as Dictionary, index))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	shell.add_child(actions)
	var surprise := kit.button("Surprise Me")
	surprise.tooltip_text = "Let the land decide."
	surprise.pressed.connect(func(): _accept(-1))
	actions.add_child(surprise)
	var rerolls_left := int(offers.pending.get("rerolls_left", 0))
	if rerolls_left > 0:
		var reroll := kit.button("New seeds (%d)" % rerolls_left)
		reroll.tooltip_text = "Draw three different seeds."
		reroll.pressed.connect(_on_reroll)
		actions.add_child(reroll)
	if not first_boot:
		var later := kit.button("Not yet")
		later.tooltip_text = "The offer keeps. Come back any time."
		later.pressed.connect(close)
		actions.add_child(later)

	var prompt := kit.label(
		"%s  ·  The Nook is permanent; what you do with it is up to you."
		% _input_service.format_action(&"ui_accept", "Choose"),
		13,
		true
	)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_arrival_prompt")
	)
	shell.add_child(prompt)
	focus_default()


func _seed_card(card: Dictionary, index: int) -> Control:
	var biome := core.registries.nook_biome(String(card.get("biome", "")))
	var accent := kit.palette.color("ui_good")
	if biome != null and biome.traits.has_tag("rocky"):
		accent = kit.palette.color("ui_arrival_cool")
	elif biome != null and biome.traits.has_tag("meadow"):
		accent = kit.palette.color("ui_arrival_warm")
	var panel := kit.progression_card(Vector2(250, 300), accent)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	panel.add_child(col)

	var density := String(card.get("density", "seeded"))
	col.add_child(_centered(kit.pill(density.to_upper(), accent)))
	var name_label := kit.label(
		String(card.get("biome_name", "Unknown")), 21, false, true
	)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var mood_label := kit.muted_label(
		"under %s" % String(card.get("mood_name", "clear skies")), 14
	)
	mood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(mood_label)
	var description := kit.muted_label(
		String(DENSITY_WORDS.get(density, "")), 13
	)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 210
	col.add_child(description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var choose := kit.button("Let it unfold", true)
	choose.tooltip_text = "%s, %s. Permanent, and yours." % [
		String(card.get("biome_name", "")), density,
	]
	choose.pressed.connect(func(): _accept(index))
	col.add_child(choose)
	if _first_button == null:
		_first_button = choose
	return panel


func _on_reroll() -> void:
	if core.nooks.offers.reroll().is_empty():
		return
	close()
	_build_modal()


func _accept(index: int) -> void:
	if first_boot:
		var offers: NookOffers = core.nooks.offers
		var choice := (
			offers.choose_surprise() if index < 0 else offers.choose(index)
		)
		first_boot = false
		close()
		if not choice.is_empty():
			first_seed_chosen.emit(choice.get("card", {}))
		return
	var plan := core.nooks.accept_offer(maxi(index, 0), index < 0)
	close()
	if plan != null:
		offer_accepted.emit(plan.coord)


func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(control)
	return center

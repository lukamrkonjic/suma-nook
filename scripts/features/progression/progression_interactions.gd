class_name ProgressionInteractions
extends RefCounted
## World-side verbs for the wishing well and the shrine. Claiming happens AT
## the well — the walk back is the ritual — and coins release there too. The
## state work happens here; panel-opening intents are resolved by main.gd on
## the option id, matching the storage-access pattern.

const InteractionOptionScript := preload(
	"res://scripts/core/interaction_option.gd"
)

var registries: Registries
var grid: WorldGrid
var module: ProgressionModule


func _init(regs: Registries, world_grid: WorldGrid, progression_module: ProgressionModule) -> void:
	registries = regs
	grid = world_grid
	module = progression_module


func options_for(_actor_id: String, instance_id: int) -> Array:
	var definition := _structure_definition(instance_id)
	if definition == null:
		return []
	var options: Array = []
	if definition.has_capability("banks_visions"):
		options.append_array(_well_options(instance_id))
	if definition.has_capability("focus_shrine"):
		options.append_array(_shrine_options(instance_id))
	return options


func execute(option_id: String, _actor_id: String, instance_id: int) -> bool:
	var definition := _structure_definition(instance_id)
	if definition == null:
		return false
	match option_id:
		"claim_vision":
			if not definition.has_capability("banks_visions"):
				return false
			if module.visions.has_pending():
				return true   # resume: the reveal UI reopens on the pending state
			return not module.visions.claim_from_well(module.inspiration).is_empty()
		"release_coin_prompt", "offer_refund", "focus_shrine":
			# Pure UI intents; main.gd opens the matching picker panel.
			return true
		"clear_shrine_focus":
			if not definition.has_capability("focus_shrine"):
				return false
			module.shrine.clear_focus()
			return true
	return false


func _well_options(instance_id: int) -> Array:
	var options: Array = []
	var banked := module.inspiration.banked.size()
	if module.visions.has_pending():
		options.append(InteractionOptionScript.new(
			"claim_vision", "Resume the Vision reveal", "progression", instance_id
		))
	elif banked > 0:
		options.append(InteractionOptionScript.new(
			"claim_vision", "Claim a Vision (%d waiting)" % banked,
			"progression", instance_id
		))
	else:
		options.append(InteractionOptionScript.new(
			"claim_vision", "Claim a Vision", "progression", instance_id,
			false, "The well is quiet. Bring it inspiration."
		))
	var coin_total := 0
	for domain_id: String in registries.inspiration_domains:
		coin_total += module.refunds.coin_count(domain_id)
	if coin_total > 0:
		options.append(InteractionOptionScript.new(
			"release_coin_prompt", "Release a promised coin (%d)" % coin_total,
			"progression", instance_id
		))
	options.append(InteractionOptionScript.new(
		"offer_refund", "Offer a duplicate to the well", "progression", instance_id
	))
	return options


func _shrine_options(instance_id: int) -> Array:
	var options: Array = []
	options.append(InteractionOptionScript.new(
		"focus_shrine", "Set the shrine's focus", "progression", instance_id
	))
	if module.shrine.has_focus():
		var focus := module.shrine.focus()
		var display_name := _display_name(String(focus["kind"]), String(focus["id"]))
		options.append(InteractionOptionScript.new(
			"clear_shrine_focus", "Clear the focus (%s)" % display_name,
			"progression", instance_id
		))
	return options


func _display_name(kind: String, content_id: String) -> String:
	match kind:
		VisionSystem.KIND_TILE:
			var tile := registries.tile(content_id)
			return tile.display_name if tile != null else content_id
		VisionSystem.KIND_STRUCTURE:
			var structure := registries.structure(content_id)
			return structure.display_name if structure != null else content_id
	return content_id


func _structure_definition(instance_id: int) -> Defs.StructureDefinition:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return null
	var structure: WorldGrid.StructureState = found["structure"]
	return registries.structure(structure.structure_id)

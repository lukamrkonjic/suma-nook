class_name ProjectDefinitions
extends RefCounted
## Data-only definitions for the shared Project language. Runtime progress is
## deliberately stored by ProjectService, never on these reusable templates.


class ContributionSlotDefinition:
	extends Resource
	var id: String
	var display_name: String
	var accepted_tags: Array[String] = []
	var required_amount := 1
	var consumes_find := false
	var icon: String

	static func from_dict(data: Dictionary) -> ContributionSlotDefinition:
		var slot := ContributionSlotDefinition.new()
		slot.id = String(data.get("id", ""))
		slot.display_name = String(data.get("name", slot.id.capitalize()))
		for raw_tag: Variant in data.get("accepts", []):
			var tag := String(raw_tag).to_lower()
			if not tag.is_empty() and not slot.accepted_tags.has(tag):
				slot.accepted_tags.append(tag)
		slot.required_amount = maxi(1, int(data.get("amount", 1)))
		slot.consumes_find = bool(data.get("consumes_find", false))
		slot.icon = String(data.get("icon", ""))
		return slot

	func to_state() -> Dictionary:
		return {
			"id": id,
			"name": display_name,
			"accepted_tags": accepted_tags.duplicate(),
			"required": required_amount,
			"current": 0,
			"consumes_find": consumes_find,
			"icon": icon,
		}


class ProjectDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	var project_type := "collection"
	var collection_id: String
	var contribution_slots: Array[ContributionSlotDefinition] = []
	var reward: Dictionary = {}
	var unlock_conditions: Dictionary = {}
	var rarity := "common"
	var special := false
	var presentation: Dictionary = {}
	var modifier_tags: Array[String] = []
	var offer_weight := 1.0

	static func from_dict(data: Dictionary) -> ProjectDefinition:
		var definition := ProjectDefinition.new()
		definition.id = String(data.get("id", ""))
		definition.display_name = String(data.get(
			"name", definition.id.capitalize()
		))
		definition.traits = Defs.DefinitionTraits.from_dict(data)
		definition.project_type = String(data.get("type", "collection"))
		definition.collection_id = String(data.get("collection", ""))
		for raw_slot: Variant in data.get("contributions", []):
			if raw_slot is Dictionary:
				definition.contribution_slots.append(
					ContributionSlotDefinition.from_dict(raw_slot)
				)
		definition.reward = (
			data.get("reward", {}) as Dictionary
		).duplicate(true)
		definition.unlock_conditions = (
			data.get("unlocks", {}) as Dictionary
		).duplicate(true)
		definition.rarity = String(data.get("rarity", "common"))
		definition.special = bool(data.get("special", false))
		definition.presentation = (
			data.get("presentation", {}) as Dictionary
		).duplicate(true)
		for raw_tag: Variant in data.get("modifier_tags", []):
			definition.modifier_tags.append(String(raw_tag))
		definition.offer_weight = maxf(0.0, float(data.get("weight", 1.0)))
		return definition


class SpecialFindDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	var contribution_tag: String
	var icon: String
	var presentation := "crystal"
	var eligible_source_tags: Array[String] = []
	var weight := 1.0

	static func from_dict(data: Dictionary) -> SpecialFindDefinition:
		var definition := SpecialFindDefinition.new()
		definition.id = String(data.get("id", ""))
		definition.display_name = String(data.get(
			"name", definition.id.capitalize()
		))
		definition.traits = Defs.DefinitionTraits.from_dict(data)
		definition.contribution_tag = String(data.get(
			"contribution_tag", "find:%s" % definition.id
		)).to_lower()
		definition.icon = String(data.get("icon", ""))
		definition.presentation = String(data.get("presentation", "crystal"))
		for raw_tag: Variant in data.get("eligible_source_tags", []):
			definition.eligible_source_tags.append(String(raw_tag))
		definition.weight = maxf(0.0, float(data.get("weight", 1.0)))
		return definition

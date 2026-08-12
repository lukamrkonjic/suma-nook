class_name DioramaDefinitions
extends RefCounted
## Typed definitions for the endless diorama progression loop. Build Bag
## categories remain a separate, functional organization axis.


class CreativeCollectionDefinition:
	extends Resource
	var id: String = ""
	var display_name: String = ""
	var traits := Defs.DefinitionTraits.new()
	var description: String = ""
	var color_token: String = "ui_accent"
	var members: Array[Dictionary] = []
	var milestones: Array[Dictionary] = []

	static func from_dict(data: Dictionary) -> CreativeCollectionDefinition:
		var definition := CreativeCollectionDefinition.new()
		definition.id = String(data.get("id", ""))
		definition.display_name = String(data.get(
			"name", definition.id.capitalize()
		))
		definition.traits = Defs.DefinitionTraits.from_dict(data)
		definition.description = String(data.get("description", ""))
		definition.color_token = String(data.get("color_token", "ui_accent"))
		for raw_member: Variant in data.get("members", []):
			if not raw_member is Dictionary:
				continue
			definition.members.append({
				"kind": String(raw_member.get("kind", "")),
				"id": String(raw_member.get("id", "")),
				"tier": maxi(0, int(raw_member.get("tier", 0))),
				"family": String(raw_member.get("family", "")),
			})
		for raw_milestone: Variant in data.get("milestones", []):
			if not raw_milestone is Dictionary:
				continue
			definition.milestones.append({
				"id": String(raw_milestone.get("id", "")),
				"discoveries": maxi(1, int(raw_milestone.get("discoveries", 1))),
				"unlock_tier": maxi(0, int(raw_milestone.get("unlock_tier", 0))),
				"gift_id": String(raw_milestone.get("gift_id", "")),
				"gift_amount": maxi(1, int(raw_milestone.get("gift_amount", 1))),
				"note": String(raw_milestone.get("note", "")),
			})
		return definition


class WorldGiftDefinition:
	extends Resource
	var id: String = ""
	var display_name: String = ""
	var traits := Defs.DefinitionTraits.new()
	var description: String = ""
	var kind: String = ""
	var icon_path: String = ""
	var max_stack: int = 9

	static func from_dict(data: Dictionary) -> WorldGiftDefinition:
		var definition := WorldGiftDefinition.new()
		definition.id = String(data.get("id", ""))
		definition.display_name = String(data.get(
			"name", definition.id.capitalize()
		))
		definition.traits = Defs.DefinitionTraits.from_dict(data)
		definition.description = String(data.get("description", ""))
		definition.kind = String(data.get("kind", ""))
		definition.icon_path = String(data.get("icon", ""))
		definition.max_stack = maxi(1, int(data.get("max_stack", 9)))
		return definition


class WorldCuriosityDefinition:
	extends Resource
	var id: String = ""
	var display_name: String = ""
	var traits := Defs.DefinitionTraits.new()
	var collection_id: String = ""
	var category: String = "meadow"
	var family: String = "home_meadow"
	var weight: float = 1.0
	var loot_min: int = 1
	var loot_max: int = 2
	var rare_chance: float = 0.08
	var gift_chance: float = 0.08
	var reveal_profile_id: String = "reveal_visitor_vase"

	static func from_dict(data: Dictionary) -> WorldCuriosityDefinition:
		var definition := WorldCuriosityDefinition.new()
		definition.id = String(data.get("id", ""))
		definition.display_name = String(data.get(
			"name", definition.id.capitalize()
		))
		definition.traits = Defs.DefinitionTraits.from_dict(data)
		definition.collection_id = String(data.get("collection", ""))
		definition.category = String(data.get("category", "meadow"))
		definition.family = String(data.get("family", "home_meadow"))
		definition.weight = maxf(0.0001, float(data.get("weight", 1.0)))
		definition.loot_min = maxi(1, int(data.get("loot_min", 1)))
		definition.loot_max = maxi(
			definition.loot_min, int(data.get("loot_max", definition.loot_min))
		)
		definition.rare_chance = clampf(float(data.get("rare_chance", 0.08)), 0.0, 1.0)
		definition.gift_chance = clampf(float(data.get("gift_chance", 0.08)), 0.0, 1.0)
		definition.reveal_profile_id = String(data.get(
			"reveal_profile", "reveal_visitor_vase"
		))
		return definition

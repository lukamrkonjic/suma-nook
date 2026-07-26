class_name Defs
extends RefCounted
## Strongly typed definition resources, populated from data/*.json.
## Stable string ids are the only cross-reference currency: never hard-code
## behavior on display names, and never reuse a shipped id for something else.


class SkillDefinition:
	extends Resource
	var id: String
	var display_name: String
	var description: String
	var icon_glyph: String
	var max_level: int = 20
	var xp_curve: String = "gentle"
	var future: bool = false          # defined but not yet playable (Mining)
	var tool_type: String = ""        # tool item tool_type required to perform
	var action_seconds: float = 2.0   # one action cycle
	var action_xp: int = 12
	var loot_table: String = ""
	var rare_table: String = ""
	var parcel_families: Array[String] = []
	var direct_tile_reward_chance: float = -1.0
	var direct_tile_reward_pool: Array[String] = []
	var collection_category: String = ""
	var collection_entries: Array[String] = []
	var animation_tag: String = ""
	var audio_tag: String = ""
	var unlocks: Array = []           # [{level:int, kind:String, id:String, note:String}]

	static func from_dict(d: Dictionary) -> SkillDefinition:
		var s := SkillDefinition.new()
		s.id = d.get("id", "")
		s.display_name = d.get("name", s.id.capitalize())
		s.description = d.get("description", "")
		s.icon_glyph = d.get("icon", "?")
		s.max_level = int(d.get("max_level", 20))
		s.xp_curve = d.get("xp_curve", "gentle")
		s.future = bool(d.get("future", false))
		s.tool_type = d.get("tool_type", "")
		s.action_seconds = float(d.get("action_seconds", 2.0))
		s.action_xp = int(d.get("action_xp", 12))
		s.loot_table = d.get("loot_table", "")
		s.rare_table = d.get("rare_table", "")
		for family in d.get("parcel_families", []):
			s.parcel_families.append(String(family))
		s.direct_tile_reward_chance = float(d.get("direct_tile_reward_chance", -1.0))
		for tile_id in d.get("direct_tile_reward_pool", []):
			s.direct_tile_reward_pool.append(String(tile_id))
		s.collection_category = String(d.get("collection_category", ""))
		for entry_id in d.get("collection_entries", []):
			s.collection_entries.append(String(entry_id))
		s.animation_tag = d.get("animation_tag", s.id)
		s.audio_tag = d.get("audio_tag", s.id)
		s.unlocks = d.get("unlocks", [])
		return s

	## Original curve (not any reference game's): cost to advance FROM level.
	func xp_to_next(level: int) -> int:
		match xp_curve:
			"gentle":
				return int(round((22 + 15 * level + 4.2 * level * level) / 5.0) * 5)
			_:
				return 50 * level


class ItemDefinition:
	extends Resource
	var id: String
	var display_name: String
	var description: String
	var category: String = "material"  # material|tool|equipment|parcel|structure_kit|relic
	var tags: Array[String] = []
	var rarity: String = "common"
	var stack: bool = true
	# equipment/tool fields
	var slot: String = ""              # tool|weapon|head|body|back
	var tool_type: String = ""         # rod|axe|pick|sword
	var tier: int = 1
	var asset_id: String = ""          # visual attachment scene
	var appearance_unlock: bool = false
	var stats: Dictionary = {}         # speed, yield_bonus, rare_bonus, damage, defense

	static func from_dict(d: Dictionary) -> ItemDefinition:
		var it := ItemDefinition.new()
		it.id = d.get("id", "")
		it.display_name = d.get("name", it.id.capitalize())
		it.description = d.get("description", "")
		it.category = d.get("category", "material")
		for tag in d.get("tags", []):
			it.tags.append(String(tag))
		it.rarity = d.get("rarity", "common")
		it.stack = bool(d.get("stack", it.category == "material" or it.category == "parcel"))
		it.slot = d.get("slot", "")
		it.tool_type = d.get("tool_type", "")
		it.tier = int(d.get("tier", 1))
		it.asset_id = d.get("asset_id", "")
		it.appearance_unlock = bool(d.get("appearance_unlock", it.slot != ""))
		it.stats = d.get("stats", {})
		return it


class AnchorDefinition:
	extends Resource
	var id: String
	var skill_id: String
	var display_name: String
	var loot_table: String = ""
	var cycle_actions: int = 4         # actions before the anchor rests
	var regen_seconds: float = 45.0
	var upgrade_levels: int = 3

	static func from_dict(d: Dictionary) -> AnchorDefinition:
		var a := AnchorDefinition.new()
		a.id = d.get("id", "")
		a.skill_id = d.get("skill", "")
		a.display_name = d.get("name", a.id.capitalize())
		a.loot_table = d.get("loot_table", "")
		a.cycle_actions = int(d.get("cycle_actions", 4))
		a.regen_seconds = float(d.get("regen_seconds", 45.0))
		a.upgrade_levels = int(d.get("upgrade_levels", 3))
		return a


class TileDefinition:
	extends Resource
	var id: String
	var display_name: String
	var family: String                 # home_meadow|living_grove|stonebound
	var biome_tags: Array[String] = []
	var asset_id: String
	var rarity: String = "common"
	var weight: float = 1.0
	var unlock_level: Dictionary = {}  # {skill_id: level}
	var walkable := true
	var water_cells: Array[String] = []  # feature tags e.g. ["pond"]
	var anchor_id: String = ""         # resource anchor hosted by this tile
	var decor_sockets: int = 3
	var structure_sockets: int = 1
	var landmark_tags: Array[String] = []
	var ambience_tag: String = ""
	var placement_sound: String = "grass"
	var special_trait: String = ""
	var collection_hint: String = ""
	var obtainable := true
	# Elevation contract. A tile may be a valid upper block without being a
	# valid support for another tile (stairs are the canonical example).
	var stackable := false
	var supports_tiles := false
	var supports_decor := true
	var surface_kind: String = "flat"  # flat|stairs|uneven|water
	var render_profile: String = "standard"       # standard|continuous_water
	var collision_profile: String = "flat"        # flat|pond_basin|none

	static func from_dict(d: Dictionary) -> TileDefinition:
		var t := TileDefinition.new()
		t.id = d.get("id", "")
		t.display_name = d.get("name", t.id.capitalize())
		t.family = d.get("family", "home_meadow")
		for tag in d.get("biome_tags", []):
			t.biome_tags.append(String(tag))
		t.asset_id = d.get("asset_id", "tile_grass")
		t.rarity = d.get("rarity", "common")
		t.weight = float(d.get("weight", 1.0))
		t.unlock_level = d.get("unlock_level", {})
		t.walkable = bool(d.get("walkable", true))
		for w in d.get("water_cells", []):
			t.water_cells.append(String(w))
		t.anchor_id = d.get("anchor", "")
		t.decor_sockets = int(d.get("decor_sockets", 3))
		t.structure_sockets = int(d.get("structure_sockets", 1))
		for tag in d.get("landmark_tags", []):
			t.landmark_tags.append(String(tag))
		t.ambience_tag = d.get("ambience_tag", "")
		t.placement_sound = d.get("placement_sound", "grass")
		t.special_trait = d.get("special_trait", "")
		t.collection_hint = d.get("collection_hint", "")
		t.obtainable = bool(d.get("obtainable", true))
		t.surface_kind = d.get(
			"surface_kind",
			"water" if not t.water_cells.is_empty() else "flat"
		)
		# Ordinary flat land is modular by default: it may be moved into a
		# column and may support another land tile. Special surfaces opt out
		# explicitly (water, stairs, basins, and other uneven pieces).
		var flat_land := t.walkable and t.surface_kind == "flat"
		t.stackable = bool(d.get("stackable", flat_land))
		t.supports_tiles = bool(d.get("supports_tiles", flat_land))
		t.supports_decor = bool(d.get("supports_decor", t.walkable))
		t.render_profile = d.get(
			"render_profile",
			"continuous_water" if t.water_cells.has("open_water") else "standard"
		)
		t.collision_profile = d.get(
			"collision_profile",
			"pond_basin" if t.water_cells.has("pond") else ("flat" if t.walkable else "none")
		)
		return t


class SupportSlotDefinition:
	extends RefCounted
	var id: String
	var offset := Vector3.ZERO
	var accepts: Array[String] = []

	static func from_dict(d: Dictionary) -> SupportSlotDefinition:
		var slot := SupportSlotDefinition.new()
		slot.id = String(d.get("id", "top"))
		var raw_offset: Array = d.get("offset", [0.0, 0.5, 0.0])
		if raw_offset.size() >= 3:
			slot.offset = Vector3(
				float(raw_offset[0]),
				float(raw_offset[1]),
				float(raw_offset[2])
			)
		for tag in d.get("accepts", []):
			slot.accepts.append(String(tag))
		return slot

	func accepts_definition(candidate: StructureDefinition) -> bool:
		if candidate == null or not candidate.can_be_stacked:
			return false
		if accepts.has("*"):
			return true
		for tag: String in candidate.placement_tags:
			if accepts.has(tag):
				return true
		return false


class StructureDefinition:
	extends Resource
	var id: String
	var display_name: String
	var asset_id: String
	var anchor_id: String = ""         # optional resource interaction owned by this object
	var kind: String = "decoration"    # building|decoration|path|utility
	var socket_type: String = "decor"  # decor (up to tile.decor_sockets) | structure (major)
	var blocks_movement := false
	# Physical interaction profile. Ordinary placeables are solid obstacles;
	# deck-like structures expose a tile-height walking surface instead.
	var collision_profile: String = "blocker"  # blocker|walkable_surface|none
	var light_height := 0.7
	var light_flicker := false
	var placement_sound: String = "wood"
	var visitor_tags: Array[String] = []  # future-visitor metadata (seating, viewing...)
	var provides: Array[String] = []   # capability tags: storage_access, light, rest
	var allow_elevated := true
	# Direct tile placement is surface-typed. Ordinary objects stay on solid
	# terrain; water-only pieces such as docks opt into "water" explicitly.
	var allowed_surface_kinds: Array[String] = ["flat", "stairs", "uneven"]
	# Object-support contract. These are deliberately separate axes:
	# - can_be_stacked: this object may be a child of another object's support.
	# - support_slots: typed local surfaces this object offers to children.
	# A stool can provide a slot without itself being allowed on another stool;
	# a small ornament can be stackable while providing no further support.
	var placement_tags: Array[String] = []
	var can_be_stacked := false
	var support_slots: Array[SupportSlotDefinition] = []
	var placement_policy_explicit := false

	static func from_dict(d: Dictionary) -> StructureDefinition:
		var s := StructureDefinition.new()
		s.id = d.get("id", "")
		s.display_name = d.get("name", s.id.capitalize())
		s.asset_id = d.get("asset_id", "")
		s.anchor_id = d.get("anchor", "")
		s.kind = d.get("kind", "decoration")
		s.socket_type = d.get("socket_type", "decor")
		s.blocks_movement = bool(d.get("blocks_movement", false))
		s.collision_profile = String(d.get("collision_profile", "blocker"))
		s.light_height = float(d.get("light_height", 0.7))
		s.light_flicker = bool(d.get("light_flicker", false))
		s.placement_sound = d.get("placement_sound", "wood")
		s.allow_elevated = bool(d.get("allow_elevated", s.socket_type == "decor"))
		s.allowed_surface_kinds.clear()
		for surface in d.get("allowed_surfaces", ["flat", "stairs", "uneven"]):
			s.allowed_surface_kinds.append(String(surface))
		for tag in d.get("visitor_tags", []):
			s.visitor_tags.append(String(tag))
		for cap in d.get("provides", []):
			s.provides.append(String(cap))
		s.placement_policy_explicit = (
			d.has("placement_tags")
			and d.has("can_be_stacked")
			and d.has("support_slots")
		)
		for tag in d.get("placement_tags", []):
			s.placement_tags.append(String(tag))
		s.can_be_stacked = bool(d.get("can_be_stacked", false))
		for raw_slot: Dictionary in d.get("support_slots", []):
			s.support_slots.append(SupportSlotDefinition.from_dict(raw_slot))
		return s

	func support_slot(slot_id: String) -> SupportSlotDefinition:
		for slot: SupportSlotDefinition in support_slots:
			if slot.id == slot_id:
				return slot
		return null

	func supports_objects() -> bool:
		return not support_slots.is_empty()

	func supports_surface(surface_kind: String) -> bool:
		return allowed_surface_kinds.has(surface_kind)


class RecipeDefinition:
	extends Resource
	var id: String
	var display_name: String
	var category: String = "decorations"  # land|buildings|decorations|tools|equipment
	var inputs: Dictionary = {}           # item_id -> count
	var output_id: String
	var output_kind: String = "structure" # structure|item|parcel
	var output_count: int = 1
	var unlock: Dictionary = {}           # {skill_id: level} — deterministic unlock
	var batchable := false

	static func from_dict(d: Dictionary) -> RecipeDefinition:
		var r := RecipeDefinition.new()
		r.id = d.get("id", "")
		r.display_name = d.get("name", r.id.capitalize())
		r.category = d.get("category", "decorations")
		r.inputs = d.get("inputs", {})
		r.output_id = d.get("output", "")
		r.output_kind = d.get("output_kind", "structure")
		r.output_count = int(d.get("output_count", 1))
		r.unlock = d.get("unlock", {})
		r.batchable = bool(d.get("batchable", false))
		return r


class LootTableDefinition:
	extends Resource
	var id: String
	var entries: Array[Dictionary] = []  # {item, weight, min, max, rare}

	static func from_dict(d: Dictionary) -> LootTableDefinition:
		var l := LootTableDefinition.new()
		l.id = d.get("id", "")
		for raw in d.get("entries", []):
			l.entries.append({
				"item": raw.get("item", ""),
				"weight": float(raw.get("weight", 1.0)),
				"min": int(raw.get("min", 1)),
				"max": int(raw.get("max", 1)),
				"rare": bool(raw.get("rare", false)),
			})
		return l


class ParcelDefinition:
	extends Resource
	var id: String
	var display_name: String
	var families: Dictionary = {}      # family -> weight when rolling options
	var option_count: int = 3

	static func from_dict(d: Dictionary) -> ParcelDefinition:
		var p := ParcelDefinition.new()
		p.id = d.get("id", "")
		p.display_name = d.get("name", p.id.capitalize())
		p.families = d.get("families", {})
		p.option_count = int(d.get("option_count", 3))
		return p


class EnemyDefinition:
	extends Resource
	var id: String
	var display_name: String
	var asset_id: String
	var max_health: int = 3
	var damage: int = 1
	var move_speed: float = 1.6
	var attack_range: float = 0.9
	var telegraph_seconds: float = 0.7
	var recover_seconds: float = 0.9
	var ranged := false
	var guardian := false
	var loot_table: String = ""

	static func from_dict(d: Dictionary) -> EnemyDefinition:
		var e := EnemyDefinition.new()
		e.id = d.get("id", "")
		e.display_name = d.get("name", e.id.capitalize())
		e.asset_id = d.get("asset_id", "")
		e.max_health = int(d.get("health", 3))
		e.damage = int(d.get("damage", 1))
		e.move_speed = float(d.get("speed", 1.6))
		e.attack_range = float(d.get("range", 0.9))
		e.telegraph_seconds = float(d.get("telegraph", 0.7))
		e.recover_seconds = float(d.get("recover", 0.9))
		e.ranged = bool(d.get("ranged", false))
		e.guardian = bool(d.get("guardian", false))
		e.loot_table = d.get("loot_table", "")
		return e


class LandmarkDefinition:
	extends Resource
	var id: String
	var display_name: String
	var asset_id: String
	var reclaimed_dressing_asset: String = ""
	var footprint: Array[Vector2i] = []   # occupied cells relative to origin
	var valid_terrain_tags: Array[String] = []
	var min_progress_tiles: int = 4       # placed tiles before it can appear
	var min_distance: int = 3             # tiles beyond world edge
	var max_distance: int = 5
	var horizon_weight: float = 1.0
	var rarity: String = "uncommon"
	var enemies: Array[Dictionary] = []   # {enemy, count}
	var guardian_id: String = ""
	var guardian_reward: String = ""      # equipment item id (idempotent grant)
	var reward_table: String = ""
	var salvage: Dictionary = {}          # item_id -> count when salvaged
	var narrative_tag: String = ""

	static func from_dict(d: Dictionary) -> LandmarkDefinition:
		var m := LandmarkDefinition.new()
		m.id = d.get("id", "")
		m.display_name = d.get("name", m.id.capitalize())
		m.asset_id = d.get("asset_id", "")
		m.reclaimed_dressing_asset = d.get("reclaimed_dressing_asset", "")
		for cell in d.get("footprint", [[0, 0]]):
			m.footprint.append(Vector2i(int(cell[0]), int(cell[1])))
		for tag in d.get("valid_terrain_tags", []):
			m.valid_terrain_tags.append(String(tag))
		m.min_progress_tiles = int(d.get("min_progress_tiles", 4))
		m.min_distance = int(d.get("min_distance", 3))
		m.max_distance = int(d.get("max_distance", 5))
		m.horizon_weight = float(d.get("horizon_weight", 1.0))
		m.rarity = d.get("rarity", "uncommon")
		for spawn in d.get("enemies", []):
			m.enemies.append(spawn)
		m.guardian_id = d.get("guardian", "")
		m.guardian_reward = d.get("guardian_reward", "")
		m.reward_table = d.get("reward_table", "")
		m.salvage = d.get("salvage", {})
		m.narrative_tag = d.get("narrative_tag", "")
		return m

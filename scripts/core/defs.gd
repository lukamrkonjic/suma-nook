class_name Defs
extends RefCounted
## Strongly typed definition resources, populated from data/*.json.
## Stable string ids are the only cross-reference currency: never hard-code
## behavior on display names, and never reuse a shipped id for something else.


class DefinitionTraits:
	extends RefCounted
	## Uniform metadata available on every definition family. Feature systems
	## may interpret registered capability payloads; tags remain classification.
	var tags: Array[String] = []
	var capabilities: Dictionary = {}
	var parse_errors: Array[String] = []

	static func from_dict(data: Dictionary) -> DefinitionTraits:
		var traits := DefinitionTraits.new()
		var raw_tags: Variant = data.get("tags", [])
		if not raw_tags is Array:
			traits.parse_errors.append("tags must be an array")
		else:
			for tag in raw_tags:
				if not tag is String:
					traits.parse_errors.append("every tag must be a string")
					continue
				traits.tags.append(String(tag))
		var raw_capabilities: Variant = data.get("capabilities", {})
		if not raw_capabilities is Dictionary:
			traits.parse_errors.append("capabilities must be an object")
		else:
			for capability_id: String in raw_capabilities:
				var payload: Variant = raw_capabilities[capability_id]
				if not payload is Dictionary:
					traits.parse_errors.append(
						"capability '%s' payload must be an object" % capability_id
					)
					continue
				traits.capabilities[capability_id] = payload.duplicate(true)
		return traits

	func has_tag(tag: String) -> bool:
		return tags.has(tag)

	func has_capability(capability_id: String) -> bool:
		return capabilities.has(capability_id)

	func capability(capability_id: String) -> Dictionary:
		return (capabilities.get(capability_id, {}) as Dictionary).duplicate(true)


class SkillDefinition:
	extends Resource
	## An activity the character can perform. Activities advance lifetime
	## milestones and may resolve a context-sensitive discovery pool.
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var description: String
	var icon_glyph: String
	var future: bool = false          # defined but not yet playable (Mining)
	var tool_type: String = ""        # tool item tool_type required to perform
	var action_seconds: float = 2.0   # one action cycle
	var collection_category: String = ""
	var collection_entries: Array[String] = []
	var animation_tag: String = ""
	var audio_tag: String = ""

	static func from_dict(d: Dictionary) -> SkillDefinition:
		var s := SkillDefinition.new()
		s.id = d.get("id", "")
		s.display_name = d.get("name", s.id.capitalize())
		s.traits = DefinitionTraits.from_dict(d)
		s.description = d.get("description", "")
		s.icon_glyph = d.get("icon", "?")
		s.future = bool(d.get("future", false))
		s.tool_type = d.get("tool_type", "")
		s.action_seconds = float(d.get("action_seconds", 2.0))
		s.collection_category = String(d.get("collection_category", ""))
		for entry_id in d.get("collection_entries", []):
			s.collection_entries.append(String(entry_id))
		s.animation_tag = d.get("animation_tag", s.id)
		s.audio_tag = d.get("audio_tag", s.id)
		return s


class DiscoveryPoolDefinition:
	extends Resource
	## A data-authored gacha pool. The source separates broad void discoveries
	## from local skills; context tags make player-built biomes meaningful.
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var description: String
	var icon_glyph: String
	var color := PaletteDefinition.shared().color("ui_neutral")
	var source: String = "local"      # void|local
	var skill_id: String = ""
	var context_tags: Array[String] = []
	var priority: int = 0
	var actions_per_reward: int = 1
	var fallback: bool = false
	var rewards: Array[Dictionary] = [] # [{kind: tile|structure, id, weight}]

	static func from_dict(d: Dictionary) -> DiscoveryPoolDefinition:
		var pool := DiscoveryPoolDefinition.new()
		pool.id = d.get("id", "")
		pool.display_name = d.get("name", pool.id.capitalize())
		pool.traits = DefinitionTraits.from_dict(d)
		pool.description = d.get("description", "")
		pool.icon_glyph = d.get("icon", "✦")
		pool.color = PaletteDefinition.shared().color(
			String(d.get("color_token", "ui_neutral")),
			pool.color
		)
		pool.source = String(d.get("source", "local"))
		pool.skill_id = String(d.get("skill", ""))
		for tag in d.get("context_tags", []):
			pool.context_tags.append(String(tag))
		pool.priority = int(d.get("priority", 0))
		pool.actions_per_reward = maxi(1, int(d.get("actions_per_reward", 1)))
		pool.fallback = bool(d.get("fallback", false))
		for raw_reward in d.get("rewards", []):
			if raw_reward is Dictionary:
				pool.rewards.append({
					"kind": String(raw_reward.get("kind", "")),
					"id": String(raw_reward.get("id", "")),
					"weight": maxf(0.0, float(raw_reward.get("weight", 1.0))),
				})
		return pool


class FishingLootDefinition:
	extends Resource
	## One reward the void can return from edge fishing. References existing
	## building content by stable id; fishing never duplicates tile/model/
	## keepsake definitions and never knows how a piece renders or places.
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var reward_kind: String = "tile_bundle"   # tile_bundle|model|keepsake
	var building_definition_id: String = ""   # tile/structure/keepsake stable id
	var theme_tags: Array[String] = []        # broad habitat themes (grove, stone…)
	var pool_tags: Array[String] = []         # local|global|wildcard
	var rarity: String = "common"             # common|uncommon|rare
	var base_weight: float = 1.0
	var bundle_min: int = 0                   # 0 falls back to rarity defaults
	var bundle_max: int = 0
	var unique: bool = false                  # granted at most once (keepsakes)
	var unlock_group: String = "core"         # future content activation hook
	var presentation_profile: String = ""     # optional reveal flourish id

	static func from_dict(d: Dictionary) -> FishingLootDefinition:
		var loot := FishingLootDefinition.new()
		loot.id = d.get("id", "")
		loot.display_name = d.get("name", loot.id.capitalize())
		loot.traits = DefinitionTraits.from_dict(d)
		loot.reward_kind = String(d.get("reward_kind", "tile_bundle"))
		loot.building_definition_id = String(d.get("building_definition_id", loot.id))
		for tag in d.get("theme_tags", []):
			loot.theme_tags.append(String(tag))
		for tag in d.get("pool_tags", []):
			loot.pool_tags.append(String(tag))
		loot.rarity = String(d.get("rarity", "common"))
		loot.base_weight = float(d.get("base_weight", 1.0))
		loot.bundle_min = int(d.get("bundle_min", 0))
		loot.bundle_max = int(d.get("bundle_max", 0))
		loot.unique = bool(d.get("unique", loot.reward_kind == "keepsake"))
		loot.unlock_group = String(d.get("unlock_group", "core"))
		loot.presentation_profile = String(d.get("presentation_profile", ""))
		return loot

	func has_theme(theme: String) -> bool:
		return theme_tags.has(theme)

	func in_pool(pool: String) -> bool:
		return pool_tags.has(pool)


class SpiritDefinition:
	extends Resource
	## A physical charm earned by completing an ordinary activity cycle. One
	## armed Spirit strongly weights one catch toward its broad theme; Spirits
	## never change rarity, haul size, quantities, or Keepsake odds.
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var description: String
	var icon_glyph: String
	var color := PaletteDefinition.shared().color("spirit_grove")
	var theme_tag: String = ""                # theme this charm targets
	var source_skill: String = ""             # activity whose cycle creates it

	static func from_dict(d: Dictionary) -> SpiritDefinition:
		var s := SpiritDefinition.new()
		s.id = d.get("id", "")
		s.display_name = d.get("name", s.id.capitalize())
		s.traits = DefinitionTraits.from_dict(d)
		s.description = d.get("description", "")
		s.icon_glyph = d.get("icon", "✧")
		s.color = PaletteDefinition.shared().color(
			String(d.get("color_token", "spirit_grove")),
			s.color
		)
		s.theme_tag = String(d.get("theme_tag", ""))
		s.source_skill = String(d.get("source_skill", ""))
		return s


class KeepsakeDefinition:
	extends Resource
	## A rare bonus reward with one small behavior. The reward generator only
	## grants a Keepsake id; a narrow service applies its effect.
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var description: String
	var icon_glyph: String
	var effect_id: String = ""                # interpreted by the keepsake service

	static func from_dict(d: Dictionary) -> KeepsakeDefinition:
		var k := KeepsakeDefinition.new()
		k.id = d.get("id", "")
		k.display_name = d.get("name", k.id.capitalize())
		k.traits = DefinitionTraits.from_dict(d)
		k.description = d.get("description", "")
		k.icon_glyph = d.get("icon", "❖")
		k.effect_id = String(d.get("effect", ""))
		return k


class MilestoneDefinition:
	extends Resource
	## A one-time reward moment. Practice milestones fire on lifetime action
	## counts; journal milestones fire when a set of collection entries is
	## complete. Rewards are granted exactly once and recorded in the save.
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var kind: String = "practice"       # practice|journal_page
	var activity_id: String = ""        # practice: which activity
	var action_count: int = 0           # practice: lifetime actions required
	var category: String = ""           # journal_page: collection category
	var entries: Array[String] = []     # journal_page: required entry ids
	var rewards: Array[Dictionary] = [] # [{kind: tile|structure|recipe|gear|note, id, note}]

	static func from_dict(d: Dictionary) -> MilestoneDefinition:
		var m := MilestoneDefinition.new()
		m.id = d.get("id", "")
		m.display_name = d.get("name", m.id.capitalize())
		m.traits = DefinitionTraits.from_dict(d)
		m.kind = String(d.get("kind", "practice"))
		m.activity_id = String(d.get("activity", ""))
		m.action_count = int(d.get("action_count", 0))
		m.category = String(d.get("category", ""))
		for entry_id in d.get("entries", []):
			m.entries.append(String(entry_id))
		for raw_reward in d.get("rewards", []):
			if raw_reward is Dictionary:
				m.rewards.append({
					"kind": String(raw_reward.get("kind", "note")),
					"id": String(raw_reward.get("id", "")),
					"note": String(raw_reward.get("note", "")),
				})
		return m


class ItemDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
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
	var hide_regions: Array[String] = [] # body regions replaced by worn armor
	var appearance_unlock: bool = false
	var stats: Dictionary = {}         # speed, yield_bonus, rare_bonus, damage, defense

	static func from_dict(d: Dictionary) -> ItemDefinition:
		var it := ItemDefinition.new()
		it.id = d.get("id", "")
		it.display_name = d.get("name", it.id.capitalize())
		it.traits = DefinitionTraits.from_dict(d)
		it.description = d.get("description", "")
		it.category = d.get("category", "material")
		it.tags.assign(it.traits.tags)
		it.rarity = d.get("rarity", "common")
		it.stack = bool(d.get("stack", it.category == "material" or it.category == "parcel"))
		it.slot = d.get("slot", "")
		it.tool_type = d.get("tool_type", "")
		it.tier = int(d.get("tier", 1))
		it.asset_id = d.get("asset_id", "")
		it.hide_regions.assign(d.get("hide_regions", []))
		it.appearance_unlock = bool(d.get("appearance_unlock", it.slot != ""))
		it.stats = d.get("stats", {})
		return it


class AnchorDefinition:
	extends Resource
	var id: String
	var skill_id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var loot_table: String = ""
	var cycle_actions: int = 4         # actions before the anchor rests
	var regen_seconds: float = 45.0
	var upgrade_levels: int = 3

	static func from_dict(d: Dictionary) -> AnchorDefinition:
		var a := AnchorDefinition.new()
		a.id = d.get("id", "")
		a.skill_id = d.get("skill", "")
		a.display_name = d.get("name", a.id.capitalize())
		a.traits = DefinitionTraits.from_dict(d)
		a.loot_table = d.get("loot_table", "")
		a.cycle_actions = int(d.get("cycle_actions", 4))
		a.regen_seconds = float(d.get("regen_seconds", 45.0))
		a.upgrade_levels = int(d.get("upgrade_levels", 3))
		return a


class TileVisualLayerDefinition:
	extends RefCounted
	## One render-only component of a logical tile. Gameplay, collision, save
	## identity, and placement remain owned by TileDefinition.
	var role: String = "surface"          # base|surface|detail|edge
	var asset_id: String = ""
	var material_key: String = ""         # optional semantic palette override
	var cover_behavior: String = "hide"   # persist|hide
	var scale_mode: String = "tile_xz"    # tile_xz|none
	var offset := Vector3.ZERO

	static func from_dict(d: Dictionary) -> TileVisualLayerDefinition:
		var layer := TileVisualLayerDefinition.new()
		layer.role = String(d.get("role", "surface"))
		layer.asset_id = String(d.get("asset_id", ""))
		layer.material_key = String(d.get("material", ""))
		layer.cover_behavior = String(
			d.get("cover_behavior", "persist" if layer.role == "base" else "hide")
		)
		layer.scale_mode = String(d.get("scale_mode", "tile_xz"))
		var raw_offset: Variant = d.get("offset", [0.0, 0.0, 0.0])
		if raw_offset is Array and raw_offset.size() >= 3:
			layer.offset = Vector3(
				float(raw_offset[0]),
				float(raw_offset[1]),
				float(raw_offset[2])
			)
		return layer


class TileDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var family: String                 # gameplay family used by rules/progression
	var catalog_category: String       # presentation-only scenery category
	var catalog_order: int = 1000      # curated order inside that category
	var biome_tags: Array[String] = []
	var asset_id: String
	var rarity: String = "common"
	var weight: float = 1.0
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
	var render_profile: String = "standard"       # standard|layered|continuous_water
	# Layered tiles assemble shared structural shells, replaceable surface
	# treatments, and optional dressing without destructively joining meshes.
	# Legacy fused asset_id tiles remain supported for shipped saves/content.
	var visual_layers: Array[TileVisualLayerDefinition] = []
	var collision_profile: String = "flat"        # flat|pond_basin|none
	# Optional low-relief geometry authored by the tile presentation layer.
	# It may rise above y=0, but is hidden (along with the authored top cap)
	# whenever another tile covers this elevation.
	var surface_detail_profile: String = ""       # ""|grass_speckles
	# Authored detail may opt into deterministic per-cell rotations to break
	# visible repetition without rotating its structural shell or topology.
	var detail_rotation_variants := 1             # 1|2|4
	# Soft raised terrain can opt into bounded world-space deformation and an
	# authored walk plane. The latter aligns physics with the median visual
	# surface; the shader then compresses the relief locally beneath each foot.
	var soft_surface_profile: String = ""         # ""|sand|snow
	var walk_surface_height: float = 0.0
	# TileGeometryProfile contract (art_source/blender/tile_profiles.py):
	# which shell silhouette this tile's authored mesh uses and how it meets
	# its neighbours. Declared explicitly per tile, validated by test_runner.
	var geometry_profile: String = "micro_bevel_square"
	var connection_mode: String = "full_flush"
	# Visual seam compatibility is narrower than gameplay family. Two tiles may
	# both be meadow content yet use different height fields; only an identical
	# connection group is allowed to consume their shared rim.
	var connection_group: String = ""
	# Two-form tiles: the EXPOSED top may sit flush with the walkable plane
	# ("flush"), dip below it ("recessed" plank beds, carved tops) or rise
	# above it ("raised" debris piles, mounds). The COVERED form is always the
	# exact full slot: when a tile is stacked on, the runtime hides the whole
	# exposed top layer and completes the body with a flush infill lid.
	var exposed_top: String = "flush"

	static func from_dict(d: Dictionary) -> TileDefinition:
		var t := TileDefinition.new()
		t.id = d.get("id", "")
		t.display_name = d.get("name", t.id.capitalize())
		t.traits = DefinitionTraits.from_dict(d)
		t.family = d.get("family", "home_meadow")
		t.catalog_category = d.get("catalog_category", t.family)
		t.catalog_order = int(d.get("catalog_order", 1000))
		for tag in d.get("biome_tags", []):
			t.biome_tags.append(String(tag))
		t.asset_id = d.get("asset_id", "tile_grass")
		t.rarity = d.get("rarity", "common")
		t.weight = float(d.get("weight", 1.0))
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
		t.geometry_profile = d.get("geometry_profile", "micro_bevel_square")
		t.connection_mode = d.get("connection_mode", "full_flush")
		t.connection_group = d.get("connection_group", t.family)
		t.exposed_top = d.get("exposed_top", "flush")
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
		for raw_layer: Variant in d.get("layers", []):
			if raw_layer is Dictionary:
				t.visual_layers.append(TileVisualLayerDefinition.from_dict(raw_layer))
		t.collision_profile = d.get(
			"collision_profile",
			"pond_basin" if t.water_cells.has("pond") else ("flat" if t.walkable else "none")
		)
		t.surface_detail_profile = d.get("surface_detail_profile", "")
		t.detail_rotation_variants = clampi(
			int(d.get("detail_rotation_variants", 1)), 1, 4
		)
		t.soft_surface_profile = d.get("soft_surface_profile", "")
		t.walk_surface_height = float(d.get("walk_surface_height", 0.0))
		return t

	func uses_layered_visual() -> bool:
		return render_profile == "layered"

	func visual_layer(role: String) -> TileVisualLayerDefinition:
		for layer: TileVisualLayerDefinition in visual_layers:
			if layer.role == role:
				return layer
		return null


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


class CapabilityDefinition:
	extends Resource
	var id: String
	var traits := DefinitionTraits.new()
	var owner: String
	var description: String

	static func from_dict(d: Dictionary) -> CapabilityDefinition:
		var capability := CapabilityDefinition.new()
		capability.id = String(d.get("id", ""))
		capability.traits = DefinitionTraits.from_dict(d)
		capability.owner = String(d.get("owner", "core"))
		capability.description = String(d.get("description", ""))
		return capability


class StructureDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var asset_id: String
	var anchor_id: String = ""         # optional resource interaction owned by this object
	var kind: String = "decoration"    # building|decoration|path|utility
	var socket_type: String = "decor"  # decor (up to tile.decor_sockets) | structure (major)
	var blocks_movement := false
	# Physical interaction profile. Ordinary placeables are solid obstacles;
	# deck-like structures expose a tile-height walking surface instead.
	var collision_profile: String = "blocker"  # blocker|walkable_surface|none
	# Optional presentation fit for structures whose footprint is defined by
	# the live grid rather than by an absolute authored size.
	var grid_fit_profile: String = ""  # ""|tile_span
	var light_height := 0.7
	var light_flicker := false
	var placement_sound: String = "wood"
	var visitor_tags: Array[String] = []  # future-visitor metadata (seating, viewing...)
	# Declarative behavior configuration. Capability ids are registered content;
	# their typed payloads are parsed and owned by the corresponding feature.
	var capabilities: Dictionary = {}
	var capability_parse_errors: Array[String] = []
	# Stateful instances keep their stable iid and mutable feature state when
	# moved into stock. Most decorations remain anonymous counted pieces.
	var preserve_instance_state := false
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
		s.traits = DefinitionTraits.from_dict(d)
		s.asset_id = d.get("asset_id", "")
		s.anchor_id = d.get("anchor", "")
		s.kind = d.get("kind", "decoration")
		s.socket_type = d.get("socket_type", "decor")
		s.blocks_movement = bool(d.get("blocks_movement", false))
		s.collision_profile = String(d.get("collision_profile", "blocker"))
		s.grid_fit_profile = String(d.get("grid_fit_profile", ""))
		s.light_height = float(d.get("light_height", 0.7))
		s.light_flicker = bool(d.get("light_flicker", false))
		s.placement_sound = d.get("placement_sound", "wood")
		s.preserve_instance_state = bool(d.get("preserve_instance_state", false))
		s.allow_elevated = bool(d.get("allow_elevated", s.socket_type == "decor"))
		s.allowed_surface_kinds.clear()
		for surface in d.get("allowed_surfaces", ["flat", "stairs", "uneven"]):
			s.allowed_surface_kinds.append(String(surface))
		for tag in d.get("visitor_tags", []):
			s.visitor_tags.append(String(tag))
		s.capabilities = s.traits.capabilities.duplicate(true)
		s.capability_parse_errors.assign(s.traits.parse_errors)
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

	func has_capability(capability_id: String) -> bool:
		return capabilities.has(capability_id)

	func capability(capability_id: String) -> Dictionary:
		return (capabilities.get(capability_id, {}) as Dictionary).duplicate(true)


class RecipeDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
	var category: String = "decorations"  # land|buildings|decorations|tools|equipment
	var inputs: Dictionary = {}           # item_id -> count
	var output_id: String
	var output_kind: String = "structure" # structure|item
	var output_count: int = 1
	var unlock_milestone: String = ""     # milestone id; "" is always available
	var batchable := false

	static func from_dict(d: Dictionary) -> RecipeDefinition:
		var r := RecipeDefinition.new()
		r.id = d.get("id", "")
		r.display_name = d.get("name", r.id.capitalize())
		r.traits = DefinitionTraits.from_dict(d)
		r.category = d.get("category", "decorations")
		r.inputs = d.get("inputs", {})
		r.output_id = d.get("output", "")
		r.output_kind = d.get("output_kind", "structure")
		r.output_count = int(d.get("output_count", 1))
		r.unlock_milestone = String(d.get("unlock_milestone", ""))
		r.batchable = bool(d.get("batchable", false))
		return r


class LootTableDefinition:
	extends Resource
	var id: String
	var traits := DefinitionTraits.new()
	var entries: Array[Dictionary] = []  # {item, weight, min, max, rare}

	static func from_dict(d: Dictionary) -> LootTableDefinition:
		var l := LootTableDefinition.new()
		l.id = d.get("id", "")
		l.traits = DefinitionTraits.from_dict(d)
		for raw in d.get("entries", []):
			l.entries.append({
				"item": raw.get("item", ""),
				"weight": float(raw.get("weight", 1.0)),
				"min": int(raw.get("min", 1)),
				"max": int(raw.get("max", 1)),
				"rare": bool(raw.get("rare", false)),
			})
		return l


class EnemyDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := DefinitionTraits.new()
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
		e.traits = DefinitionTraits.from_dict(d)
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
	var traits := DefinitionTraits.new()
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
		m.traits = DefinitionTraits.from_dict(d)
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

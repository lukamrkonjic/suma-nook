class_name NookDefs
extends RefCounted
## Typed definition resources for the Unfolding World: generated nature
## Nooks, landform stamps, biome palettes, moods, buried treasure tables,
## transformation Firsts, dormant mysteries, and keepsake moments.
##
## Content references content by slot/tag, never by hard-coded ID branches:
## stamps name palette slots ("ground", "water", "tree"), and each biome
## resolves those slots to concrete tile/structure IDs at generation time.


## A weighted pool of concrete content IDs behind one palette slot.
class SlotPool:
	extends Resource
	var ids: PackedStringArray = PackedStringArray()
	var weights: PackedFloat64Array = PackedFloat64Array()

	static func from_variant(raw: Variant) -> SlotPool:
		var pool := SlotPool.new()
		if raw is Array:
			for entry: Variant in raw:
				pool.ids.append(String(entry))
				pool.weights.append(1.0)
			return pool
		if raw is Dictionary:
			var raw_ids: Variant = raw.get("pool", [])
			var raw_weights: Variant = raw.get("weights", [])
			if raw_ids is Array:
				for index in (raw_ids as Array).size():
					pool.ids.append(String(raw_ids[index]))
					var weight := 1.0
					if raw_weights is Array and index < (raw_weights as Array).size():
						weight = maxf(0.0, float(raw_weights[index]))
					pool.weights.append(weight)
		return pool

	func is_empty() -> bool:
		return ids.is_empty()

	## Deterministic weighted pick from a caller-owned RNG.
	func pick(rng: RandomNumberGenerator) -> String:
		if ids.is_empty():
			return ""
		var total := 0.0
		for weight in weights:
			total += weight
		if total <= 0.0:
			return ids[rng.randi_range(0, ids.size() - 1)]
		var roll := rng.randf() * total
		for index in ids.size():
			roll -= weights[index]
			if roll <= 0.0:
				return ids[index]
		return ids[ids.size() - 1]


class NookBiomeDefinition:
	extends Resource
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	## slot name -> SlotPool of tile ids (terrain slots) or structure ids
	## (feature slots). The generator does not care which; stamps and the
	## scatter pass say which kind they expect.
	var resolve: Dictionary = {}
	## density name ("open"/"seeded"/"grown") -> feature fill chance per cell.
	var density: Dictionary = {}
	## Mood ids this biome can roll.
	var mood_ids: PackedStringArray = PackedStringArray()
	## density name -> treasure table id rolled at generation.
	var treasure_tables: Dictionary = {}
	## Feature slots used by the scatter pass, with relative weights.
	var scatter := SlotPool.new()
	## Offer weighting: neighbors of the same biome multiply the base weight,
	## producing drift instead of checkerboard.
	var base_weight := 1.0
	var neighbor_weight := 3.0

	static func from_dict(d: Dictionary) -> NookBiomeDefinition:
		var biome := NookBiomeDefinition.new()
		biome.id = String(d.get("id", ""))
		biome.display_name = String(d.get("name", biome.id.capitalize()))
		biome.traits = Defs.DefinitionTraits.from_dict(d)
		var raw_resolve: Variant = d.get("resolve", {})
		if raw_resolve is Dictionary:
			for slot: Variant in (raw_resolve as Dictionary):
				biome.resolve[String(slot)] = SlotPool.from_variant(raw_resolve[slot])
		var raw_density: Variant = d.get("density", {})
		if raw_density is Dictionary:
			for band: Variant in (raw_density as Dictionary):
				biome.density[String(band)] = clampf(float(raw_density[band]), 0.0, 1.0)
		for mood: Variant in d.get("moods", []):
			biome.mood_ids.append(String(mood))
		var raw_tables: Variant = d.get("treasure_tables", {})
		if raw_tables is Dictionary:
			for band: Variant in (raw_tables as Dictionary):
				biome.treasure_tables[String(band)] = String(raw_tables[band])
		biome.scatter = SlotPool.from_variant(d.get("scatter", []))
		biome.base_weight = maxf(0.0, float(d.get("base_weight", 1.0)))
		biome.neighbor_weight = maxf(0.0, float(d.get("neighbor_weight", 3.0)))
		return biome


class NookStampDefinition:
	extends Resource
	## Hand-authored landform mini-prefab. The grid is authored in palette
	## slots, so one stamp reads correctly in every biome that resolves them.
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	var size := Vector2i.ONE
	## row strings of single-character legend keys, y-down.
	var rows: PackedStringArray = PackedStringArray()
	## legend char -> terrain slot name ("." = leave scatter terrain alone).
	var legend: Dictionary = {}
	## authored features: [{"cell": Vector2i, "slot": String}]
	var features: Array[Dictionary] = []
	## side ("n"/"s"/"e"/"w") -> contract label ("land", "water_in", ...).
	var edges: Dictionary = {}
	var biome_ids: PackedStringArray = PackedStringArray()
	var dormant_socket := false
	## Local cell that hosts the dormant thing when this stamp carries it.
	var dormant_cell := Vector2i.ZERO
	var weight := 1.0

	static func from_dict(d: Dictionary) -> NookStampDefinition:
		var stamp := NookStampDefinition.new()
		stamp.id = String(d.get("id", ""))
		stamp.display_name = String(d.get("name", stamp.id.capitalize()))
		stamp.traits = Defs.DefinitionTraits.from_dict(d)
		var raw_size: Variant = d.get("size", [1, 1])
		if raw_size is Array and (raw_size as Array).size() >= 2:
			stamp.size = Vector2i(
				maxi(1, int(raw_size[0])), maxi(1, int(raw_size[1]))
			)
		for row: Variant in d.get("rows", []):
			stamp.rows.append(String(row))
		var raw_legend: Variant = d.get("legend", {})
		if raw_legend is Dictionary:
			for key: Variant in (raw_legend as Dictionary):
				stamp.legend[String(key)] = String(raw_legend[key])
		for raw_feature: Variant in d.get("features", []):
			if not raw_feature is Dictionary:
				continue
			var cell: Variant = raw_feature.get("cell", [0, 0])
			if cell is Array and (cell as Array).size() >= 2:
				stamp.features.append({
					"cell": Vector2i(int(cell[0]), int(cell[1])),
					"slot": String(raw_feature.get("slot", "")),
				})
		var raw_edges: Variant = d.get("edges", {})
		if raw_edges is Dictionary:
			for side: Variant in (raw_edges as Dictionary):
				stamp.edges[String(side).to_lower()] = String(raw_edges[side])
		for biome: Variant in d.get("biomes", []):
			stamp.biome_ids.append(String(biome))
		stamp.dormant_socket = bool(d.get("dormant_socket", false))
		var raw_dormant: Variant = d.get("dormant_cell", [0, 0])
		if raw_dormant is Array and (raw_dormant as Array).size() >= 2:
			stamp.dormant_cell = Vector2i(int(raw_dormant[0]), int(raw_dormant[1]))
		stamp.weight = maxf(0.0, float(d.get("weight", 1.0)))
		return stamp

	## Terrain slot at a local stamp cell, or "" for authored pass-through.
	func slot_at(cell: Vector2i) -> String:
		if cell.y < 0 or cell.y >= rows.size():
			return ""
		var row := rows[cell.y]
		if cell.x < 0 or cell.x >= row.length():
			return ""
		var key := row[cell.x]
		return String(legend.get(key, ""))


class NookMoodDefinition:
	extends Resource
	## Presentation-only palette/lighting/particle overrides. Multiplies
	## authored content: the same stamp reads differently under first snow.
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	var weather: String = "day"
	var time_of_day: String = "noon"
	var ambient_fx: String = ""
	var weight := 1.0

	static func from_dict(d: Dictionary) -> NookMoodDefinition:
		var mood := NookMoodDefinition.new()
		mood.id = String(d.get("id", ""))
		mood.display_name = String(d.get("name", mood.id.capitalize()))
		mood.traits = Defs.DefinitionTraits.from_dict(d)
		mood.weather = String(d.get("weather", "day"))
		mood.time_of_day = String(d.get("time_of_day", "noon"))
		mood.ambient_fx = String(d.get("ambient_fx", ""))
		mood.weight = maxf(0.0, float(d.get("weight", 1.0)))
		return mood


class TreasureTableDefinition:
	extends Resource
	## Rolled once at generation; assignments live in chunk meta so clearing
	## the qualifying feature always finds the same buried thing.
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	## [{"host_tag": String, "chance": float, "pool": String,
	##   "guaranteed": int}] — guaranteed slots always place that many.
	var slots: Array[Dictionary] = []

	static func from_dict(d: Dictionary) -> TreasureTableDefinition:
		var table := TreasureTableDefinition.new()
		table.id = String(d.get("id", ""))
		table.display_name = String(d.get("name", table.id.capitalize()))
		table.traits = Defs.DefinitionTraits.from_dict(d)
		for raw_slot: Variant in d.get("slots", []):
			if not raw_slot is Dictionary:
				continue
			table.slots.append({
				"host_tag": String(raw_slot.get("host_tag", "any")),
				"chance": clampf(float(raw_slot.get("chance", 0.0)), 0.0, 1.0),
				"pool": String(raw_slot.get("pool", "")),
				"guaranteed": maxi(0, int(raw_slot.get("guaranteed", 0))),
			})
		return table


class FirstDefinition:
	extends Resource
	## A transformation trigger. Pure listener: no advance UI surface exists
	## anywhere — a First may render nothing until after it has fired.
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	## World-signal name on WorldEvents (e.g. "water_added").
	var signal_name: String = ""
	var scope: String = "chunk"          # "chunk" or "world"
	## Fires only if the chunk lacked this terrain/feature tag before the
	## triggering change ("" = no requirement).
	var chunk_lacked_tag: String = ""
	var once_per_chunk := true
	var journal_text: String = ""
	var ambient_fx: String = ""
	## Structure/tile family unlocks granted through the journal unlock set.
	var unlock_structures: PackedStringArray = PackedStringArray()
	var unlock_tiles: PackedStringArray = PackedStringArray()

	static func from_dict(d: Dictionary) -> FirstDefinition:
		var first := FirstDefinition.new()
		first.id = String(d.get("id", ""))
		first.display_name = String(d.get("name", first.id.capitalize()))
		first.traits = Defs.DefinitionTraits.from_dict(d)
		first.signal_name = String(d.get("signal", ""))
		first.scope = String(d.get("scope", "chunk"))
		first.chunk_lacked_tag = String(d.get("chunk_lacked_tag", ""))
		first.once_per_chunk = bool(d.get("once_per_chunk", true))
		first.journal_text = String(d.get("journal", ""))
		first.ambient_fx = String(d.get("ambient_fx", ""))
		for sid: Variant in d.get("unlock_structures", []):
			first.unlock_structures.append(String(sid))
		for tid: Variant in d.get("unlock_tiles", []):
			first.unlock_tiles.append(String(tid))
		return first


class DormantDefinition:
	extends Resource
	## One visibly odd, non-interactive thing per Nook. No marker, no bar:
	## it wakes from accumulated nearby life, deferred to the next session.
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	## Structure placed at the stamp's dormant socket while dormant.
	var structure_id: String = ""
	## Structure it becomes when it wakes ("" = stays, only rewards).
	var woken_structure_id: String = ""
	var wake_score := 12.0
	var reward_pool_id: String = ""
	var journal_text: String = ""
	var weight := 1.0

	static func from_dict(d: Dictionary) -> DormantDefinition:
		var dormant := DormantDefinition.new()
		dormant.id = String(d.get("id", ""))
		dormant.display_name = String(d.get("name", dormant.id.capitalize()))
		dormant.traits = Defs.DefinitionTraits.from_dict(d)
		dormant.structure_id = String(d.get("structure", ""))
		dormant.woken_structure_id = String(d.get("woken_structure", ""))
		dormant.wake_score = maxf(0.1, float(d.get("wake_score", 12.0)))
		dormant.reward_pool_id = String(d.get("reward_pool", ""))
		dormant.journal_text = String(d.get("journal", ""))
		dormant.weight = maxf(0.0, float(d.get("weight", 1.0)))
		return dormant


class MomentDefinition:
	extends Resource
	## A keepsake moment: witnessed, never requested. Pure output — a minted
	## keepsake gates nothing.
	var id: String
	var display_name: String
	var traits := Defs.DefinitionTraits.new()
	var kind: String = "counter"        # "counter" or "cooccurrence"
	## counter: world-signal counted toward `count`.
	var signal_name: String = ""
	var count := 1
	## cooccurrence: every condition tag must hold in one chunk at once.
	## Supported condition tags are world-signal derived chunk facts
	## (e.g. "warm_light", "falling_snow", "night").
	var conditions: PackedStringArray = PackedStringArray()
	var journal_text: String = ""
	## Placeable display item unlocked when minted (unlimited copies).
	var keepsake_structure_id: String = ""

	static func from_dict(d: Dictionary) -> MomentDefinition:
		var moment := MomentDefinition.new()
		moment.id = String(d.get("id", ""))
		moment.display_name = String(d.get("name", moment.id.capitalize()))
		moment.traits = Defs.DefinitionTraits.from_dict(d)
		moment.kind = String(d.get("kind", "counter"))
		moment.signal_name = String(d.get("signal", ""))
		moment.count = maxi(1, int(d.get("count", 1)))
		for condition: Variant in d.get("conditions", []):
			moment.conditions.append(String(condition))
		moment.journal_text = String(d.get("journal", ""))
		moment.keepsake_structure_id = String(d.get("keepsake_structure", ""))
		return moment

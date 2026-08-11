class_name NookGenerator
extends RefCounted
## Pure generation pipeline: (seed card, neighbor context) -> NookPlan.
## Deterministic — the same seed card always produces the same plan, so
## saves can replay generation and treasure assignment can never be farmed
## by re-rolling.
##
## Pipeline: stamp placement -> blended biome material -> world-space water ->
## noise-shaped solid columns -> ecological scatter -> treasure & dormant.
## Every field samples absolute world cells, so rivers, ridges, and vegetation
## continue through Nooks that have not been generated yet.

const StampMargin := 1


class NookPlan:
	extends RefCounted
	var coord := Vector2i.ZERO
	var biome_id: String = ""
	var mood_id: String = ""
	var density: String = "seeded"
	var terrain_shape: String = "natural"
	var seed_value: int = 0
	var stamp_ids: PackedStringArray = PackedStringArray()
	## [{"local": Vector2i, "tile_id": String, "elevation": int}]
	var tiles: Array[Dictionary] = []
	## [{"local": Vector2i, "structure_id": String, "dormant": bool}]
	var features: Array[Dictionary] = []
	## local "x:y" -> {"pool": String, "host_tag": String, "found": false}
	var treasures: Dictionary = {}
	## {"id": String, "cell": [x, y]} or empty.
	var dormant: Dictionary = {}


var registries: Registries


func _init(regs: Registries) -> void:
	registries = regs


## seed_card: {"biome": String, "density": String, "mood": String,
## "seed": int, "stamp_hint": String (optional)}.
func generate(
	coord: Vector2i,
	seed_card: Dictionary,
	size: int,
	context: Dictionary = {}
) -> NookPlan:
	var plan := NookPlan.new()
	plan.coord = coord
	plan.biome_id = String(seed_card.get("biome", ""))
	plan.mood_id = String(seed_card.get("mood", ""))
	plan.density = String(seed_card.get("density", "seeded"))
	plan.terrain_shape = normalize_terrain_shape(
		String(seed_card.get("terrain_shape", "natural"))
	)
	plan.seed_value = int(seed_card.get("seed", 0))
	var biome := registries.nook_biome(plan.biome_id)
	if biome == null:
		push_error("NookGenerator: unknown biome '%s'" % plan.biome_id)
		return plan
	var rng := RandomNumberGenerator.new()
	rng.seed = plan.seed_value

	# Terrain starts as biome ground everywhere; stamps overwrite regions.
	var terrain_slots: Dictionary = {}   # Vector2i -> slot name
	for y in size:
		for x in size:
			terrain_slots[Vector2i(x, y)] = "ground"

	var stamp_features: Array[Dictionary] = []
	var stamp_cells: Dictionary = {}     # Vector2i -> true (feature keep-out)
	var dormant_socket := Vector2i(-1, -1)
	var stamps := _roll_stamps(biome, seed_card, rng)
	var placed_rects: Array[Rect2i] = []
	for stamp: NookDefs.NookStampDefinition in stamps:
		var rect := _find_stamp_rect(stamp, size, placed_rects, rng)
		if rect.position.x < 0:
			continue
		placed_rects.append(rect)
		plan.stamp_ids.append(stamp.id)
		for y in stamp.size.y:
			for x in stamp.size.x:
				var local := Vector2i(x, y)
				var slot := stamp.slot_at(local)
				var world_local: Vector2i = rect.position + local
				stamp_cells[world_local] = true
				if slot != "":
					terrain_slots[world_local] = slot
		for feature: Dictionary in stamp.features:
			stamp_features.append({
				"local": rect.position + (feature["cell"] as Vector2i),
				"slot": String(feature["slot"]),
			})
		if stamp.dormant_socket and dormant_socket.x < 0:
			dormant_socket = rect.position + stamp.dormant_cell

	# Bevel one or two un-authored corners so each compact slate has a distinct
	# silhouette instead of reading as another perfect square. The two middle
	# cells on every side remain intact, guaranteeing a clear seam to neighbors.
	_carve_footprint(terrain_slots, size, rng)

	# Resolve broad material patches and softly inherit the palette of revealed
	# neighbours along shared seams. The transition happens only inside this new
	# Nook, so generation never rewrites a player's established terrain.
	var terrain_tiles := _resolve_terrain_tiles(
		plan, biome, terrain_slots, size, rng, context
	)
	var relief_exclusions := {}
	for feature: Dictionary in stamp_features:
		relief_exclusions[feature["local"]] = true
	if dormant_socket.x >= 0:
		relief_exclusions[dormant_socket] = true
	var water_cells := _apply_hydrology(
		plan,
		biome,
		terrain_tiles,
		relief_exclusions,
		size,
		int(seed_card.get("hydrology_seed", seed_card.get(
			"terrain_seed", plan.seed_value
		)))
	)
	for local: Vector2i in terrain_tiles:
		plan.tiles.append({
			"local": local,
			"tile_id": String(terrain_tiles[local]),
			"elevation": 0,
		})

	# A low-frequency world-space height field builds whole solid columns.
	# Repeated full blocks create readable terraces and cliffs without relying
	# on detached quarter/half caps that can look like floating sheets.
	for local: Vector2i in water_cells:
		relief_exclusions[local] = true
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			if terrain_tiles.has(local + offset):
				relief_exclusions[local + offset] = true
	_shape_terrain(
		plan,
		biome,
		terrain_tiles,
		relief_exclusions,
		size,
		int(seed_card.get("terrain_seed", plan.seed_value)),
		plan.terrain_shape
	)

	# Scatter pass: features by density curve — thicker toward the chunk
	# edge (the wild rim), thinner near stamps and the chunk core.
	var authored_feature_cells: Dictionary = {}
	for feature: Dictionary in stamp_features:
		var structure_pool: NookDefs.SlotPool = biome.resolve.get(
			String(feature["slot"])
		)
		var structure_id := _pick_live_structure(structure_pool, rng)
		if structure_id == "" or water_cells.has(feature["local"]):
			continue
		plan.features.append({
			"local": feature["local"],
			"structure_id": structure_id,
			"dormant": false,
		})
		authored_feature_cells[feature["local"]] = true
	var base_density := float(biome.density.get(plan.density, 0.1))
	var half := float(size - 1) / 2.0
	var habitat_noise := FastNoiseLite.new()
	habitat_noise.seed = int((int(seed_card.get(
		"terrain_seed", plan.seed_value
	)) ^ 0x5D71B1) & 0x7FFFFFFF)
	habitat_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	habitat_noise.frequency = float(
		registries.nook_config.get("habitat_frequency", 0.095)
	)
	for y in size:
		for x in size:
			var local := Vector2i(x, y)
			if not terrain_slots.has(local):
				continue
			if stamp_cells.has(local) or authored_feature_cells.has(local):
				continue
			if local == dormant_socket:
				continue
			var terrain_slot := String(terrain_slots[local])
			if terrain_slot != "ground":
				continue
			if water_cells.has(local):
				continue
			var surface_definition := registries.tile(String(terrain_tiles.get(
				local, ""
			)))
			if surface_definition == null \
				or not surface_definition.supports_decor:
				continue
			var edge_distance := minf(
				minf(x, size - 1 - x), minf(y, size - 1 - y)
			)
			var rim := 1.0 - clampf(edge_distance / half, 0.0, 1.0)
			var world_cell := plan.coord * size + local
			var habitat := clampf(
				habitat_noise.get_noise_2d(world_cell.x, world_cell.y) * 0.5 + 0.5,
				0.0,
				1.0
			)
			var chance := base_density * (0.55 + 0.55 * rim) \
				* lerpf(0.55, 1.35, habitat)
			if rng.randf() >= chance:
				continue
			var slot_name := biome.scatter.pick(rng)
			var feature_pool: NookDefs.SlotPool = biome.resolve.get(slot_name)
			var structure_id := _pick_live_structure(feature_pool, rng)
			if structure_id == "":
				continue
			plan.features.append({
				"local": local,
				"structure_id": structure_id,
				"dormant": false,
			})

	_assign_treasures(plan, biome, rng)
	_assign_dormant(plan, dormant_socket, rng)
	return plan


func _resolve_terrain_tiles(
	plan: NookPlan,
	biome: NookDefs.NookBiomeDefinition,
	terrain_slots: Dictionary,
	size: int,
	rng: RandomNumberGenerator,
	context: Dictionary
) -> Dictionary:
	var resolved := {}
	var primary_by_slot := {}
	var secondary_by_slot := {}
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = int((plan.seed_value ^ 0x51A7B3) & 0x7FFFFFFF)
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch_noise.frequency = float(
		registries.nook_config.get("terrain_material_frequency", 0.13)
	)
	patch_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	patch_noise.fractal_octaves = 2
	var patch_threshold := float(
		registries.nook_config.get("terrain_material_patch_threshold", 0.28)
	)
	var transition_noise := FastNoiseLite.new()
	transition_noise.seed = int((plan.seed_value ^ 0x6B10D5) & 0x7FFFFFFF)
	transition_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	transition_noise.frequency = float(
		registries.nook_config.get("biome_blend_noise_frequency", 0.31)
	)
	var neighbors: Array = context.get("neighbors", [])
	for local: Vector2i in terrain_slots:
		var slot := String(terrain_slots[local])
		var source_biome := _blended_biome_for_cell(
			plan,
			biome,
			local,
			size,
			neighbors,
			transition_noise
		)
		var pool: NookDefs.SlotPool = source_biome.resolve.get(slot)
		if pool == null or pool.is_empty():
			pool = source_biome.resolve.get("ground")
		var cache_key := "%s|%s" % [source_biome.id, slot]
		if not primary_by_slot.has(cache_key):
			var primary := _pick_biome_ground_tile(source_biome, pool, rng)
			if primary == "" and slot != "ground":
				pool = source_biome.resolve.get("ground")
				primary = _pick_biome_ground_tile(source_biome, pool, rng)
			if primary == "":
				primary = _safe_ground_tile_id()
			primary_by_slot[cache_key] = primary
			secondary_by_slot[cache_key] = _pick_biome_ground_tile(
				source_biome, pool, rng, primary
			)
		var tile_id := String(primary_by_slot.get(cache_key, ""))
		var secondary := String(secondary_by_slot.get(cache_key, ""))
		if slot == "ground" and secondary != "":
			var global_cell := plan.coord * size + local
			if patch_noise.get_noise_2d(global_cell.x, global_cell.y) \
				> patch_threshold:
				tile_id = secondary
		if tile_id != "":
			resolved[local] = tile_id
	return resolved


func _blended_biome_for_cell(
	plan: NookPlan,
	biome: NookDefs.NookBiomeDefinition,
	local: Vector2i,
	size: int,
	neighbors: Array,
	noise: FastNoiseLite
) -> NookDefs.NookBiomeDefinition:
	var blend_width := clampi(int(
		registries.nook_config.get("biome_blend_width", 2)
	), 0, maxi(0, size / 2))
	if blend_width <= 0:
		return biome
	var best_biome := biome
	var best_influence := 0.0
	for raw_neighbor: Variant in neighbors:
		if not raw_neighbor is Dictionary:
			continue
		var entry: Dictionary = raw_neighbor
		var offset: Vector2i = entry.get("offset", Vector2i.ZERO)
		var distance := size
		if offset == Vector2i.LEFT:
			distance = local.x
		elif offset == Vector2i.RIGHT:
			distance = size - 1 - local.x
		elif offset == Vector2i.UP:
			distance = local.y
		elif offset == Vector2i.DOWN:
			distance = size - 1 - local.y
		if distance >= blend_width:
			continue
		var neighbor_biome := registries.nook_biome(String(entry.get(
			"biome", ""
		)))
		if neighbor_biome == null or neighbor_biome.id == biome.id:
			continue
		var influence := float(blend_width - distance) / float(blend_width + 1)
		if influence > best_influence:
			best_influence = influence
			best_biome = neighbor_biome
	if best_biome == biome:
		return biome
	var world_cell := plan.coord * size + local
	var jitter := noise.get_noise_2d(world_cell.x, world_cell.y) * 0.16
	var threshold := clampf(best_influence + jitter, 0.0, 0.9)
	var selector := _cell_hash_01(world_cell, plan.seed_value ^ 0x314159)
	return best_biome if selector < threshold else biome


func _pick_biome_ground_tile(
	biome: NookDefs.NookBiomeDefinition,
	pool: NookDefs.SlotPool,
	rng: RandomNumberGenerator,
	exclude := ""
) -> String:
	var eligible: Array[String] = []
	var weights: Array[float] = []
	if pool != null:
		for index in pool.ids.size():
			var tile_id := String(pool.ids[index])
			if tile_id == exclude or not _is_ordinary_terrain_tile(tile_id):
				continue
			eligible.append(tile_id)
			weights.append(float(pool.weights[index]) \
				if index < pool.weights.size() else 1.0)
	var automatic_weight := float(
		registries.nook_config.get("tagged_ground_weight", 0.35)
	)
	for definition: Defs.TileDefinition in registries.tiles.values():
		if definition.id == exclude or eligible.has(definition.id):
			continue
		if not definition.traits.has_tag("generation_ground") \
			or not _tile_matches_biome(definition, biome) \
			or not _is_ordinary_terrain_tile(definition.id):
			continue
		eligible.append(definition.id)
		weights.append(maxf(0.05, definition.weight * automatic_weight))
	return _weighted_id_pick(eligible, weights, rng)


func _tile_matches_biome(
	definition: Defs.TileDefinition,
	biome: NookDefs.NookBiomeDefinition
) -> bool:
	for tag: String in definition.biome_tags:
		if biome.traits.has_tag(tag):
			return true
	return false


func _pick_ordinary_tile(
	pool: NookDefs.SlotPool,
	rng: RandomNumberGenerator,
	exclude := ""
) -> String:
	if pool == null:
		return ""
	var eligible: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for index in pool.ids.size():
		var tile_id := String(pool.ids[index])
		if tile_id == exclude or not _is_ordinary_terrain_tile(tile_id):
			continue
		var weight := (
			float(pool.weights[index])
			if index < pool.weights.size()
			else 1.0
		)
		eligible.append(tile_id)
		weights.append(weight)
		total += weight
	if eligible.is_empty():
		return ""
	var roll := rng.randf() * maxf(total, 0.001)
	for index in eligible.size():
		roll -= weights[index]
		if roll <= 0.0:
			return eligible[index]
	return eligible.back()


func _weighted_id_pick(
	ids: Array[String], weights: Array[float], rng: RandomNumberGenerator
) -> String:
	if ids.is_empty():
		return ""
	var total := 0.0
	for weight: float in weights:
		total += maxf(0.0, weight)
	var roll := rng.randf() * maxf(total, 0.001)
	for index in ids.size():
		roll -= weights[index] if index < weights.size() else 1.0
		if roll <= 0.0:
			return ids[index]
	return ids.back()


func _safe_ground_tile_id() -> String:
	var configured := String(
		registries.nook_config.get("safe_ground_tile_id", "tile_grass")
	)
	return configured if _is_ordinary_terrain_tile(configured) else "tile_grass"


func _pick_live_structure(
	pool: NookDefs.SlotPool, rng: RandomNumberGenerator
) -> String:
	if pool == null:
		return ""
	var ids: Array[String] = []
	var weights: Array[float] = []
	for index in pool.ids.size():
		var structure_id := String(pool.ids[index])
		if registries.structure(structure_id) == null:
			continue
		ids.append(structure_id)
		weights.append(float(pool.weights[index]) \
			if index < pool.weights.size() else 1.0)
	return _weighted_id_pick(ids, weights, rng)


func _apply_hydrology(
	plan: NookPlan,
	biome: NookDefs.NookBiomeDefinition,
	terrain_tiles: Dictionary,
	exclusions: Dictionary,
	size: int,
	seed_value: int
) -> Dictionary:
	var water := {}
	var config: Dictionary = registries.nook_config.get("hydrology", {})
	if not bool(config.get("enabled", true)):
		return water
	var river := FastNoiseLite.new()
	river.seed = int((seed_value ^ 0x17A2D9) & 0x7FFFFFFF)
	river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	river.frequency = float(config.get("river_frequency", 0.045))
	river.fractal_type = FastNoiseLite.FRACTAL_FBM
	river.fractal_octaves = 2
	var river_warp := FastNoiseLite.new()
	river_warp.seed = int((seed_value ^ 0x7F4A7C15) & 0x7FFFFFFF)
	river_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	river_warp.frequency = float(config.get("river_warp_frequency", 0.018))
	var pond := FastNoiseLite.new()
	pond.seed = int((seed_value ^ 0x43C6EF) & 0x7FFFFFFF)
	pond.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pond.frequency = float(config.get("pond_frequency", 0.075))
	pond.fractal_type = FastNoiseLite.FRACTAL_FBM
	pond.fractal_octaves = 3
	var river_width := float(config.get("river_width", 0.075))
	var pond_threshold := float(config.get("pond_threshold", 0.62))
	for local: Vector2i in terrain_tiles:
		if exclusions.has(local):
			continue
		var world_cell := plan.coord * size + local
		var warp := river_warp.get_noise_2d(world_cell.x, world_cell.y) * 7.0
		var river_distance := absf(river.get_noise_2d(
			float(world_cell.x) + warp,
			float(world_cell.y) - warp * 0.65
		))
		var pond_value := pond.get_noise_2d(world_cell.x, world_cell.y)
		if river_distance <= river_width or pond_value >= pond_threshold:
			water[local] = "pond" if pond_value >= pond_threshold else "river"
	var water_id := _water_tile_id(biome)
	if water_id == "":
		return {}
	for local: Vector2i in water:
		terrain_tiles[local] = water_id
	# A one-cell natural bank softens every shore. Banks use ordinary full land
	# blocks, so water never introduces the framed basin tiles that caused holes.
	var bank_id := _riverbank_tile_id(biome)
	if bank_id != "":
		for local: Vector2i in water:
			for offset: Vector2i in WorldGrid.NEIGHBORS:
				var bank: Vector2i = local + offset
				if terrain_tiles.has(bank) and not water.has(bank):
					terrain_tiles[bank] = bank_id
	return water


func _water_tile_id(biome: NookDefs.NookBiomeDefinition) -> String:
	var pool: NookDefs.SlotPool = biome.resolve.get("water")
	if pool != null:
		for tile_id: String in pool.ids:
			var definition := registries.tile(tile_id)
			if definition != null and definition.render_profile == "continuous_water":
				return tile_id
	var fallback := String(registries.nook_config.get(
		"safe_water_tile_id", "tile_open_water"
	))
	var definition := registries.tile(fallback)
	return fallback if definition != null \
		and definition.render_profile == "continuous_water" else ""


func _riverbank_tile_id(biome: NookDefs.NookBiomeDefinition) -> String:
	var pool: NookDefs.SlotPool = biome.resolve.get("riverbank")
	var rng := RandomNumberGenerator.new()
	rng.seed = biome.id.hash()
	var result := _pick_ordinary_tile(pool, rng)
	return result if result != "" else _safe_ground_tile_id()


static func _cell_hash_01(cell: Vector2i, seed_value: int) -> float:
	var value := int(cell.x * 374761393 + cell.y * 668265263 + seed_value * 69069)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7FFFFFFF) / 2147483647.0


func _is_ordinary_terrain_tile(tile_id: String) -> bool:
	var definition := registries.tile(tile_id)
	return (
		definition != null
		and definition.height_fraction >= 1.0
		and definition.stackable
		and definition.supports_tiles
		and definition.surface_kind == "flat"
		and definition.render_profile != "continuous_water"
		and definition.water_cells.is_empty()
		and definition.collision_profile != "pond_basin"
	)


func _shape_terrain(
	plan: NookPlan,
	biome: NookDefs.NookBiomeDefinition,
	terrain_tiles: Dictionary,
	relief_exclusions: Dictionary,
	size: int,
	terrain_seed: int,
	terrain_shape := "natural"
) -> void:
	if terrain_tiles.is_empty():
		return
	terrain_shape = normalize_terrain_shape(terrain_shape)
	if terrain_shape == "flat":
		return
	var config: Dictionary = registries.nook_config.get("terrain_height", {})
	var max_levels := int(config.get("max_full_levels", 2))
	if biome.traits.has_tag(String(config.get("mountain_biome_tag", "rocky"))):
		max_levels = int(config.get("rocky_max_full_levels", 3))
	if terrain_shape == "rolling":
		max_levels = 2
	elif terrain_shape == "mountains":
		max_levels = maxi(3, max_levels)
	max_levels = clampi(max_levels, 1, 4)

	var macro_noise := FastNoiseLite.new()
	macro_noise.seed = int(terrain_seed & 0x7FFFFFFF)
	macro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	macro_noise.frequency = float(config.get("macro_frequency", 0.085))
	macro_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	macro_noise.fractal_octaves = 3
	macro_noise.fractal_gain = 0.52
	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = int((terrain_seed ^ 0x2C9277) & 0x7FFFFFFF)
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = float(config.get("detail_frequency", 0.24))
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 2

	var samples := {}
	for local: Vector2i in terrain_tiles:
		var definition := registries.tile(String(terrain_tiles[local]))
		if definition == null or definition.surface_kind == "water" \
			or definition.render_profile == "continuous_water":
			continue
		var world_cell := plan.coord * size + local
		var sample := (
			macro_noise.get_noise_2d(world_cell.x, world_cell.y) * 0.72
			+ detail_noise.get_noise_2d(world_cell.x, world_cell.y) * 0.28
		)
		samples[local] = sample

	var heights := {}
	# Absolute world-space thresholds preserve a ridge when it crosses a Nook
	# seam. Per-chunk min/max normalization made adjacent chunks disagree.
	var low_threshold := float(config.get("low_threshold", -0.16))
	var high_threshold := float(config.get("high_threshold", 0.10))
	var summit_threshold := float(config.get("summit_threshold", 0.34))
	if terrain_shape == "rolling":
		# Broad, low terraces: visible relief without turning a Nook into a
		# vertical obstacle course.
		low_threshold = -0.12
		high_threshold = 0.18
	elif terrain_shape == "mountains":
		# Pull each contour downward so three-level ridges are common enough to
		# read as a deliberate player choice, while keeping the same continuous
		# world-space field as neighboring Nooks.
		low_threshold = -0.30
		high_threshold = -0.04
		summit_threshold = 0.18
	for local: Vector2i in samples:
		var sample := float(samples[local])
		var height := 0
		if not relief_exclusions.has(local) and sample >= low_threshold:
			height = 1
		if not relief_exclusions.has(local) \
			and max_levels >= 2 and sample >= high_threshold:
			height = 2
		if not relief_exclusions.has(local) \
			and max_levels >= 3 and sample >= summit_threshold:
			height = 3
		heights[local] = mini(height, max_levels)

	# A Peaks choice should always read as Peaks, even if this particular slice
	# of the continuous field happens to sit in a valley. Seed one broad summit
	# at the highest eligible sample, then let the normal relaxation pass blend
	# it back into the surrounding field.
	var peak_local := Vector2i(-1, -1)
	if terrain_shape == "mountains":
		var peak_sample := -INF
		for local: Vector2i in samples:
			if relief_exclusions.has(local):
				continue
			var sample := float(samples[local])
			if sample > peak_sample:
				peak_sample = sample
				peak_local = local
		if peak_local.x >= 0:
			heights[peak_local] = max_levels
			for offset: Vector2i in WorldGrid.NEIGHBORS:
				var shoulder := peak_local + offset
				if heights.has(shoulder) and not relief_exclusions.has(shoulder):
					heights[shoulder] = maxi(
						int(heights[shoulder]), mini(2, max_levels)
					)

	# Quantized noise can produce needle cliffs. Relax only excessive local
	# jumps while retaining broad level changes and a guaranteed high summit.
	var smoothing_passes := int(config.get("smoothing_passes", 3))
	if terrain_shape == "mountains":
		# The seeded shoulder already prevents a needle; one pass keeps the
		# deliberately taller silhouette from relaxing back into rolling hills.
		smoothing_passes = 1
	for _pass in smoothing_passes:
		var relaxed := heights.duplicate()
		for local: Vector2i in heights:
			var height := int(heights[local])
			for offset: Vector2i in WorldGrid.NEIGHBORS:
				var neighbor := local + offset
				if heights.has(neighbor):
					height = mini(height, int(heights[neighbor]) + 1)
			relaxed[local] = height
		heights = relaxed
	if terrain_shape == "mountains" and peak_local.x >= 0:
		# Bank and authored-feature exclusions can surround the best sample and
		# relax it too aggressively. Keep one readable two-step-or-higher crown;
		# player-selected Peaks must never arrive looking like Rolling terrain.
		heights[peak_local] = maxi(
			int(heights[peak_local]), mini(3, max_levels)
		)

	for local: Vector2i in heights:
		var tile_id := String(terrain_tiles[local])
		for elevation in range(1, int(heights[local]) + 1):
			plan.tiles.append({
				"local": local,
				"tile_id": tile_id,
				"elevation": elevation,
			})


static func normalize_terrain_shape(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized in ["natural", "flat", "rolling", "mountains"]:
		return normalized
	return "natural"


func _roll_stamps(
	biome: NookDefs.NookBiomeDefinition,
	seed_card: Dictionary,
	rng: RandomNumberGenerator
) -> Array:
	var eligible: Array = []
	var weights: Array[float] = []
	var ruin_chance := float(registries.nook_config.get("ruin_chance", 0.05))
	var excluded_tags: Array = registries.nook_config.get(
		"excluded_stamp_tags", []
	)
	var allow_ruin := rng.randf() < ruin_chance
	for stamp in registries.nook_stamps.values():
		if not stamp.biome_ids.has(biome.id):
			continue
		var excluded := false
		for excluded_tag: Variant in excluded_tags:
			if stamp.traits.has_tag(String(excluded_tag)):
				excluded = true
				break
		if excluded:
			continue
		if stamp.traits.has_tag("ruin") and not allow_ruin:
			continue
		eligible.append(stamp)
		weights.append(stamp.weight)
	if eligible.is_empty():
		return []
	var stamp_hint := String(seed_card.get("stamp_hint", ""))
	var count := rng.randi_range(
		int(registries.nook_config.get("stamps_min", 1)),
		int(registries.nook_config.get("stamps_max", 2))
	)
	var result: Array = []
	var hinted_stamp := registries.nook_stamp(stamp_hint)
	if stamp_hint != "" and hinted_stamp != null and eligible.has(hinted_stamp):
		result.append(hinted_stamp)
	while result.size() < count:
		var picked: Variant = _weighted_pick(eligible, weights, rng)
		if picked == null:
			break
		if not result.has(picked):
			result.append(picked)
		else:
			break
	return result


func _find_stamp_rect(
	stamp: NookDefs.NookStampDefinition,
	size: int,
	taken: Array[Rect2i],
	rng: RandomNumberGenerator
) -> Rect2i:
	var margin := 0 if size <= 4 else StampMargin
	var max_x := size - margin - stamp.size.x
	var max_y := size - margin - stamp.size.y
	if max_x < margin or max_y < margin:
		return Rect2i(Vector2i(-1, -1), Vector2i.ZERO)
	for _attempt in 12:
		var position := Vector2i(
			rng.randi_range(margin, max_x),
			rng.randi_range(margin, max_y)
		)
		var rect := Rect2i(position, stamp.size)
		var collides := false
		for other: Rect2i in taken:
			if rect.grow(1).intersects(other):
				collides = true
				break
		if not collides:
			return rect
	return Rect2i(Vector2i(-1, -1), Vector2i.ZERO)


func _carve_footprint(
	terrain_slots: Dictionary,
	size: int,
	rng: RandomNumberGenerator
) -> void:
	if size < 3:
		return
	var candidates: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(size - 1, 0),
		Vector2i(0, size - 1),
		Vector2i(size - 1, size - 1),
	]
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary
	var minimum := clampi(
		int(registries.nook_config.get("corner_cuts_min", 1)),
		0,
		candidates.size()
	)
	var maximum := clampi(
		int(registries.nook_config.get("corner_cuts_max", 2)),
		minimum,
		candidates.size()
	)
	var wanted := rng.randi_range(minimum, maximum)
	var removed := 0
	for candidate: Vector2i in candidates:
		if removed >= wanted:
			break
		if String(terrain_slots.get(candidate, "")) != "ground":
			continue
		terrain_slots.erase(candidate)
		removed += 1


## Treasure is decided here, at generation, and stored in chunk meta. Denser
## Nooks roll richer tables — density finally has a purpose.
func _assign_treasures(
	plan: NookPlan,
	biome: NookDefs.NookBiomeDefinition,
	rng: RandomNumberGenerator
) -> void:
	var table_id := String(biome.treasure_tables.get(plan.density, ""))
	var table := registries.treasure_table(table_id)
	if table == null:
		return
	var host_cells: Dictionary = {}   # host cell -> tags
	for feature: Dictionary in plan.features:
		var definition := registries.structure(String(feature["structure_id"]))
		if definition == null:
			continue
		host_cells[feature["local"]] = definition.placement_tags
	for slot: Dictionary in table.slots:
		var host_tag := String(slot.get("host_tag", "any"))
		var eligible: Array[Vector2i] = []
		for cell: Vector2i in host_cells:
			var key := NookWorld.cell_key(cell)
			if plan.treasures.has(key):
				continue
			var tags: Array = host_cells[cell]
			if host_tag == "any" or tags.has(host_tag):
				eligible.append(cell)
		var guaranteed := int(slot.get("guaranteed", 0))
		var chance := float(slot.get("chance", 0.0))
		for cell: Vector2i in eligible:
			var place := false
			if guaranteed > 0:
				place = true
				guaranteed -= 1
			elif chance > 0.0:
				place = rng.randf() < chance
			if place:
				plan.treasures[NookWorld.cell_key(cell)] = {
					"pool": String(slot.get("pool", "")),
					"host_tag": host_tag,
					"found": false,
				}


func _assign_dormant(
	plan: NookPlan,
	socket: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	if socket.x < 0:
		return
	if rng.randf() >= float(registries.nook_config.get("dormant_chance", 0.85)):
		return
	var eligible: Array = []
	var weights: Array[float] = []
	for dormant in registries.dormants.values():
		eligible.append(dormant)
		weights.append(dormant.weight)
	var picked: Variant = _weighted_pick(eligible, weights, rng)
	if picked == null:
		return
	plan.dormant = {"id": picked.id, "cell": [socket.x, socket.y]}
	plan.features.append({
		"local": socket,
		"structure_id": picked.structure_id,
		"dormant": true,
	})


static func _weighted_pick(
	options: Array, weights: Array[float], rng: RandomNumberGenerator
) -> Variant:
	if options.is_empty():
		return null
	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return options[rng.randi_range(0, options.size() - 1)]
	var roll := rng.randf() * total
	for index in options.size():
		roll -= weights[index]
		if roll <= 0.0:
			return options[index]
	return options[options.size() - 1]

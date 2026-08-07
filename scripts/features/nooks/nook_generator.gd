class_name NookGenerator
extends RefCounted
## Pure generation pipeline: (seed card, neighbor context) -> NookPlan.
## Deterministic — the same seed card always produces the same plan, so
## saves can replay generation and treasure assignment can never be farmed
## by re-rolling.
##
## Pipeline: stamp placement -> ground fill -> scatter pass -> treasure &
## dormant assignment. Compact Nooks allow stamps at the outer rim, while
## footprint carving preserves the two middle seam cells on every side.

const StampMargin := 1


class NookPlan:
	extends RefCounted
	var coord := Vector2i.ZERO
	var biome_id: String = ""
	var mood_id: String = ""
	var density: String = "seeded"
	var seed_value: int = 0
	var stamp_ids: PackedStringArray = PackedStringArray()
	## [{"local": Vector2i, "tile_id": String}]
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
func generate(coord: Vector2i, seed_card: Dictionary, size: int) -> NookPlan:
	var plan := NookPlan.new()
	plan.coord = coord
	plan.biome_id = String(seed_card.get("biome", ""))
	plan.mood_id = String(seed_card.get("mood", ""))
	plan.density = String(seed_card.get("density", "seeded"))
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

	# Resolve terrain slots to concrete tiles.
	for local: Vector2i in terrain_slots:
		var slot := String(terrain_slots[local])
		var pool: NookDefs.SlotPool = biome.resolve.get(slot)
		if pool == null or pool.is_empty():
			pool = biome.resolve.get("ground")
		var tile_id := pool.pick(rng) if pool != null else ""
		if tile_id != "" and registries.tile(tile_id) != null:
			plan.tiles.append({"local": local, "tile_id": tile_id, "elevation": 0})

	# Relief pass: gentle knolls from fractional-height caps (quarter rims,
	# half cores), and in rocky biomes an occasional full-block mountain
	# shoulder with a half cap. Deterministic from the same seed.
	var relief_exclusions: Dictionary = {}
	for feature: Dictionary in stamp_features:
		relief_exclusions[feature["local"]] = true
	if dormant_socket.x >= 0:
		relief_exclusions[dormant_socket] = true
	_carve_relief(plan, biome, terrain_slots, relief_exclusions, size, rng)

	# Scatter pass: features by density curve — thicker toward the chunk
	# edge (the wild rim), thinner near stamps and the chunk core.
	var authored_feature_cells: Dictionary = {}
	for feature: Dictionary in stamp_features:
		var structure_pool: NookDefs.SlotPool = biome.resolve.get(
			String(feature["slot"])
		)
		if structure_pool == null or structure_pool.is_empty():
			continue
		var structure_id := structure_pool.pick(rng)
		plan.features.append({
			"local": feature["local"],
			"structure_id": structure_id,
			"dormant": false,
		})
		authored_feature_cells[feature["local"]] = true
	var base_density := float(biome.density.get(plan.density, 0.1))
	var half := float(size - 1) / 2.0
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
			var edge_distance := minf(
				minf(x, size - 1 - x), minf(y, size - 1 - y)
			)
			var rim := 1.0 - clampf(edge_distance / half, 0.0, 1.0)
			var chance := base_density * (0.6 + 0.8 * rim)
			if rng.randf() >= chance:
				continue
			var slot_name := biome.scatter.pick(rng)
			var feature_pool: NookDefs.SlotPool = biome.resolve.get(slot_name)
			if feature_pool == null or feature_pool.is_empty():
				continue
			plan.features.append({
				"local": local,
				"structure_id": feature_pool.pick(rng),
				"dormant": false,
			})

	_assign_treasures(plan, biome, rng)
	_assign_dormant(plan, dormant_socket, rng)
	return plan


## Elevation vocabulary: 0.25 rims, 0.5 cores, and (rocky biomes) a full
## block + half cap summit. All entries land at elevation 1/2 above the
## already-generated ground, never under water or authored feature sockets.
func _carve_relief(
	plan: NookPlan,
	biome: NookDefs.NookBiomeDefinition,
	terrain_slots: Dictionary,
	relief_exclusions: Dictionary,
	size: int,
	rng: RandomNumberGenerator
) -> void:
	var low_pool: NookDefs.SlotPool = biome.resolve.get("rise_low")
	var half_pool: NookDefs.SlotPool = biome.resolve.get("rise_half")
	if low_pool == null or low_pool.is_empty() \
		or half_pool == null or half_pool.is_empty():
		return
	var config: Dictionary = registries.nook_config.get("relief", {})
	var knolls := rng.randi_range(
		int(config.get("knolls_min", 1)), int(config.get("knolls_max", 3))
	)
	var full_pool: NookDefs.SlotPool = biome.resolve.get("rise_full")
	var mountain := (
		full_pool != null and not full_pool.is_empty()
		and biome.traits.has_tag(String(config.get("mountain_biome_tag", "rocky")))
		and rng.randf() < float(config.get("mountain_chance", 0.5))
	)
	var raised: Dictionary = {}
	for knoll_index in knolls:
		var radius := rng.randi_range(
			int(config.get("radius_min", 1)), int(config.get("radius_max", 2))
		)
		var centre := _pick_relief_centre(
			terrain_slots,
			relief_exclusions,
			raised,
			size,
			radius,
			rng
		)
		if centre.x < 0:
			continue
		var is_mountain := mountain and knoll_index == 0
		for y in range(centre.y - radius, centre.y + radius + 1):
			for x in range(centre.x - radius, centre.x + radius + 1):
				var local := Vector2i(x, y)
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				if raised.has(local) or relief_exclusions.has(local):
					continue
				if not terrain_slots.has(local):
					continue
				# Ponds remain readable depressions, while clearings and rocky
				# stamp ground are fair game for relief. Restricting knolls to the
				# generic ground slot made compact stamped Nooks almost flat.
				if not _terrain_accepts_relief(String(terrain_slots[local])):
					continue
				var distance := Vector2(local).distance_to(Vector2(centre))
				if distance > float(radius) + 0.08:
					continue
				var core := distance <= float(radius) * 0.55
				if is_mountain and core:
					plan.tiles.append({
						"local": local,
						"tile_id": full_pool.pick(rng),
						"elevation": 1,
					})
					plan.tiles.append({
						"local": local,
						"tile_id": half_pool.pick(rng),
						"elevation": 2,
					})
				else:
					var cap_pool := half_pool if core else low_pool
					plan.tiles.append({
						"local": local,
						"tile_id": cap_pool.pick(rng),
						"elevation": 1,
					})
				raised[local] = true


func _pick_relief_centre(
	terrain_slots: Dictionary,
	relief_exclusions: Dictionary,
	raised: Dictionary,
	size: int,
	radius: int,
	rng: RandomNumberGenerator
) -> Vector2i:
	# Compact 4x4 Nooks cannot reserve a one-cell perimeter for the centre:
	# a 3x3 pond would occupy every candidate and erase the landform. Score
	# every cell, then randomly select among the best usable silhouettes.
	var best_score := 0
	var best: Array[Vector2i] = []
	for centre_y in size:
		for centre_x in size:
			var centre := Vector2i(centre_x, centre_y)
			var score := 0
			for y in range(centre.y - radius, centre.y + radius + 1):
				for x in range(centre.x - radius, centre.x + radius + 1):
					var local := Vector2i(x, y)
					if x < 0 or y < 0 or x >= size or y >= size:
						continue
					if (
						relief_exclusions.has(local)
						or raised.has(local)
						or not terrain_slots.has(local)
						or not _terrain_accepts_relief(
							String(terrain_slots[local])
						)
					):
						continue
					if Vector2(local).distance_to(Vector2(centre)) <= float(radius) + 0.08:
						score += 1
			if score > best_score:
				best_score = score
				best.assign([centre])
			elif score == best_score and score > 0:
				best.append(centre)
	if best.is_empty():
		return Vector2i(-1, -1)
	return best[rng.randi_range(0, best.size() - 1)]


func _terrain_accepts_relief(slot: String) -> bool:
	return slot not in ["water", "water_edge"]


func _roll_stamps(
	biome: NookDefs.NookBiomeDefinition,
	seed_card: Dictionary,
	rng: RandomNumberGenerator
) -> Array:
	var eligible: Array = []
	var weights: Array[float] = []
	var ruin_chance := float(registries.nook_config.get("ruin_chance", 0.05))
	var allow_ruin := rng.randf() < ruin_chance
	for stamp in registries.nook_stamps.values():
		if not stamp.biome_ids.has(biome.id):
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
	if stamp_hint != "" and registries.nook_stamp(stamp_hint) != null:
		result.append(registries.nook_stamp(stamp_hint))
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

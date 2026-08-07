class_name NookOffers
extends RefCounted
## The only 1-of-3 choice in the game: Nook seeds. Placements never offer
## choices; expansion does. Soft frontier rhythm: the next offer becomes
## available after modest activity in the newest Nook — minutes, not
## completion.

signal offer_ready(coord: Vector2i, cards: Array)
signal offer_consumed(coord: Vector2i)

var registries: Registries
var rng: RngService
var world: NookWorld

## Pending offer: {"coord": Vector2i, "cards": Array[Dictionary],
##  "rerolls_left": int} or empty.
var pending: Dictionary = {}
var offers_made := 0


func _init(regs: Registries, rng_service: RngService, nook_world: NookWorld) -> void:
	registries = regs
	rng = rng_service
	world = nook_world


func has_pending() -> bool:
	return not pending.is_empty()


func pending_cards() -> Array:
	return (pending.get("cards", []) as Array).duplicate(true)


func pending_coord() -> Vector2i:
	return pending.get("coord", Vector2i.ZERO)


## The frontier gate: true when the newest Nook has seen enough activity
## (or the world has no offer outstanding and no activity requirement yet).
func can_offer() -> bool:
	if not registries.feature("nooks_enabled", true):
		return false
	if has_pending():
		return false
	var threshold := int(
		registries.nook_config.get("frontier_activity_threshold", 6)
	)
	var newest := _newest_nook()
	if newest == null:
		return true
	return newest.activity >= threshold or newest.starter


## Rolls a fresh 3-card offer for the next frontier coord.
func make_offer(coord := Vector2i(2147483647, 2147483647)) -> Dictionary:
	if not can_offer():
		return {}
	var target := coord
	if target.x == 2147483647:
		var frontier := world.frontier_coords()
		if frontier.is_empty():
			target = Vector2i.ZERO if not world.has_nook(Vector2i.ZERO) \
				else Vector2i.RIGHT
		else:
			target = frontier[0]
	offers_made += 1
	pending = {
		"coord": target,
		"cards": _roll_cards(target),
		"rerolls_left": int(registries.nook_config.get("free_rerolls", 1)),
	}
	offer_ready.emit(target, pending_cards())
	return pending.duplicate(true)


## Picks a card (0..2) and consumes the offer. "Surprise Me" is a random
## pick — same path, no special card kind.
func choose(index: int) -> Dictionary:
	if pending.is_empty():
		return {}
	var cards: Array = pending.get("cards", [])
	if index < 0 or index >= cards.size():
		return {}
	var card: Dictionary = (cards[index] as Dictionary).duplicate(true)
	var coord: Vector2i = pending.get("coord", Vector2i.ZERO)
	pending = {}
	offer_consumed.emit(coord)
	return {"coord": coord, "card": card}


func choose_surprise() -> Dictionary:
	if pending.is_empty():
		return {}
	var cards: Array = pending.get("cards", [])
	return choose(rng.randi_range("nook_offer_surprise", 0, cards.size() - 1))


func reroll() -> Dictionary:
	if pending.is_empty() or int(pending.get("rerolls_left", 0)) <= 0:
		return {}
	pending["rerolls_left"] = int(pending["rerolls_left"]) - 1
	pending["cards"] = _roll_cards(pending.get("coord", Vector2i.ZERO))
	offer_ready.emit(pending.get("coord", Vector2i.ZERO), pending_cards())
	return pending.duplicate(true)


## Biome drifts instead of checkerboarding: revealed neighbors multiply
## their biome's weight. Density and mood roll from data-declared weights.
func _roll_cards(coord: Vector2i) -> Array:
	var cards: Array = []
	var count := int(registries.nook_config.get("offer_count", 3))
	var used_biomes: Dictionary = {}
	for index in count:
		var stream := "nook_offer:%d:%d:%d:%d" % [
			coord.x, coord.y, offers_made, index
		]
		var biome := _roll_biome(coord, stream, used_biomes)
		if biome == null:
			continue
		# Prefer biome variety across the three cards when possible.
		used_biomes[biome.id] = true
		var density := _roll_density(stream)
		var mood_id := _roll_mood(biome, stream)
		cards.append({
			"biome": biome.id,
			"biome_name": biome.display_name,
			"density": density,
			"mood": mood_id,
			"mood_name": _mood_name(mood_id),
			"seed": rng.randi_range(stream + ":seed", 1, 0x7FFFFFFF),
		})
	return cards


func _roll_biome(
	coord: Vector2i, stream: String, avoid: Dictionary
) -> NookDefs.NookBiomeDefinition:
	var options: Array = []
	var weights: Array[float] = []
	var neighbors := world.revealed_neighbors(coord)
	var fresh_options: Array = []
	var fresh_weights: Array[float] = []
	for biome: NookDefs.NookBiomeDefinition in registries.nook_biomes.values():
		var weight := biome.base_weight
		for neighbor in neighbors:
			if neighbor.biome_id == biome.id:
				weight *= biome.neighbor_weight
		options.append(biome)
		weights.append(weight)
		if not avoid.has(biome.id):
			fresh_options.append(biome)
			fresh_weights.append(weight)
	if not fresh_options.is_empty():
		options = fresh_options
		weights = fresh_weights
	if options.is_empty():
		return null
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf_range(stream + ":biome", 0.0, maxf(total, 0.001))
	for index in options.size():
		roll -= weights[index]
		if roll <= 0.0:
			return options[index]
	return options[options.size() - 1]


func _roll_density(stream: String) -> String:
	var bands: Array = registries.nook_config.get(
		"density_bands", ["open", "seeded", "grown"]
	)
	var weights: Array = registries.nook_config.get(
		"density_weights", [1.0, 1.0, 1.0]
	)
	var total := 0.0
	for weight in weights:
		total += float(weight)
	var roll := rng.randf_range(stream + ":density", 0.0, maxf(total, 0.001))
	for index in bands.size():
		roll -= float(weights[index]) if index < weights.size() else 1.0
		if roll <= 0.0:
			return String(bands[index])
	return String(bands[bands.size() - 1]) if not bands.is_empty() else "seeded"


func _roll_mood(biome: NookDefs.NookBiomeDefinition, stream: String) -> String:
	if biome.mood_ids.is_empty():
		return ""
	var options: Array = []
	var weights: Array[float] = []
	for mood_id in biome.mood_ids:
		var mood := registries.nook_mood(mood_id)
		if mood != null:
			options.append(mood)
			weights.append(mood.weight)
	if options.is_empty():
		return ""
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf_range(stream + ":mood", 0.0, maxf(total, 0.001))
	for index in options.size():
		roll -= weights[index]
		if roll <= 0.0:
			return options[index].id
	return options[options.size() - 1].id


func _mood_name(mood_id: String) -> String:
	var mood := registries.nook_mood(mood_id)
	return mood.display_name if mood != null else ""


func _newest_nook() -> NookWorld.NookRecord:
	var newest: NookWorld.NookRecord = null
	for record: NookWorld.NookRecord in world.nooks.values():
		if newest == null or record.revealed_unix > newest.revealed_unix:
			newest = record
	return newest


func to_save_dict() -> Dictionary:
	var saved := pending.duplicate(true)
	if saved.has("coord"):
		var coord: Vector2i = saved["coord"]
		saved["coord"] = [coord.x, coord.y]
	return {"pending": saved, "offers_made": offers_made}


func from_save_dict(data: Dictionary) -> void:
	offers_made = int(data.get("offers_made", 0))
	pending = (data.get("pending", {}) as Dictionary).duplicate(true)
	if pending.has("coord"):
		var raw: Variant = pending["coord"]
		if raw is Array and (raw as Array).size() >= 2:
			pending["coord"] = Vector2i(int(raw[0]), int(raw[1]))
		else:
			pending = {}

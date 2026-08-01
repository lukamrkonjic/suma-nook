class_name GridHabitatAdapter
extends WorldHabitatQuery
## Reads the 3x3 neighborhood around a fishing edge straight from WorldGrid
## data — never the scene tree — and reduces it to broad weighted themes via
## the mapping tables in fishing_balance.json. Samples are cached per anchor
## and invalidated by a world revision that bumps on any grid change.

## The habitat window is exactly the 3x3 block around the anchor cell.
const SAMPLE_RADIUS := 1

var registries: Registries
var grid: WorldGrid
var balance: FishingBalance

var _revision := 1
var _cache: Dictionary = {}   # anchor (Vector2i) -> FishingHabitatSample


func _init(
	regs: Registries,
	world_grid: WorldGrid,
	balance_config: FishingBalance
) -> void:
	registries = regs
	grid = world_grid
	balance = balance_config
	grid.grid_changed.connect(_invalidate)
	grid.slot_changed.connect(func(_coord, _elevation): _invalidate())


func sample(anchor: Vector2i) -> FishingHabitatSample:
	var cached: FishingHabitatSample = _cache.get(anchor)
	if cached != null and cached.world_revision == _revision:
		return cached
	var config := balance.habitat_config()
	var weights: Dictionary = (config.get("base_themes", {"wild": 1.0}) as Dictionary).duplicate(true)
	var model_weights: Dictionary = {}
	var contributing_models: Dictionary = {}   # structure_id -> contribution count
	var max_models := int(config.get("max_model_contributions", 2))
	var duplicate_cap := int(config.get("model_duplicate_cap", 1))
	for x in range(anchor.x - SAMPLE_RADIUS, anchor.x + SAMPLE_RADIUS + 1):
		for y in range(anchor.y - SAMPLE_RADIUS, anchor.y + SAMPLE_RADIUS + 1):
			var coord := Vector2i(x, y)
			var tile := grid.top_tile_def(coord)
			if tile == null:
				continue
			_add_themes(weights, config.get("family_themes", {}), tile.family, 1.0)
			for biome_tag: String in tile.biome_tags:
				_add_themes(weights, config.get("biome_themes", {}), biome_tag, 1.0)
			_collect_model_themes(
				coord, config, model_weights,
				contributing_models, max_models, duplicate_cap
			)
	# Models season the habitat, they never dominate it: their combined
	# per-theme contribution is capped, and a model only ever contributes a
	# broad theme — never its exact item identity.
	var theme_cap := float(config.get("model_theme_cap", 2.0))
	for theme: String in model_weights:
		var contribution := minf(float(model_weights[theme]), theme_cap)
		weights[theme] = float(weights.get(theme, 0.0)) + contribution
	var result := FishingHabitatSample.new(anchor, _revision, weights)
	_cache[anchor] = result
	return result


func _collect_model_themes(
	coord: Vector2i,
	config: Dictionary,
	model_weights: Dictionary,
	contributing_models: Dictionary,
	max_models: int,
	duplicate_cap: int
) -> void:
	var tag_themes: Dictionary = config.get("structure_tag_themes", {})
	var top := grid.top_elevation(coord)
	for elevation in range(0, top + 1):
		var state := grid.cell_at(coord, elevation)
		if state == null:
			continue
		for placed: WorldGrid.StructureState in state.structures:
			var structure_id := placed.structure_id
			var already := int(contributing_models.get(structure_id, 0))
			if already >= duplicate_cap:
				continue   # duplicate identical models never stack forever
			if (
				already == 0
				and contributing_models.size() >= max_models
			):
				continue   # at most a few distinct landmark contributions
			var definition := registries.structure(structure_id)
			if definition == null:
				continue
			var contributed := false
			for tag: String in definition.placement_tags:
				contributed = _add_themes(model_weights, tag_themes, tag, 1.0) or contributed
			for tag: String in definition.traits.tags:
				contributed = _add_themes(model_weights, tag_themes, tag, 1.0) or contributed
			if contributed:
				contributing_models[structure_id] = already + 1


func _add_themes(
	weights: Dictionary,
	table: Dictionary,
	key: String,
	scale: float
) -> bool:
	var themes: Variant = table.get(key)
	if not themes is Dictionary:
		return false
	for theme: String in themes:
		weights[theme] = float(weights.get(theme, 0.0)) + float(themes[theme]) * scale
	return not (themes as Dictionary).is_empty()


func _invalidate() -> void:
	_revision += 1
	_cache.clear()

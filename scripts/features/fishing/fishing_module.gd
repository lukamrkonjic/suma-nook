class_name FishingModule
extends RefCounted
## Composition root for the void-fishing feature: wires the pure domain and
## application services to their Godot-side adapters, owns the versioned save
## payload, and exposes the debug/simulation surface. GameCore owns exactly
## one of these; no service here is a global singleton.

const SCHEMA_VERSION := 1

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var collection: CollectionManager
var progression: ProgressionModule

var balance: FishingBalance
var habitat: GridHabitatAdapter
var catalog: BuildCatalogAdapter
var composer: HaulComposer
var luck: HiddenLuckService
var generator: FishingRewardGenerator
var pouch: SpiritPouchService
var basket: CatchBasketAdapter
var session: FishingSessionService
var spirit_adapter: ActivitySpiritAdapter
var keepsakes: FishingKeepsakeService

var first_catch_done := false


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	stock_manager: StockManager,
	collection_manager: CollectionManager,
	progression_module: ProgressionModule
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	stock = stock_manager
	collection = collection_manager
	progression = progression_module
	balance = FishingBalance.new(regs.fishing_balance)
	habitat = GridHabitatAdapter.new(regs, grid, balance)
	catalog = BuildCatalogAdapter.new(regs, balance)
	composer = HaulComposer.new(balance, rng)
	luck = HiddenLuckService.new(balance)
	generator = FishingRewardGenerator.new(balance, catalog, composer, luck, rng)
	pouch = SpiritPouchService.new(regs, balance.pouch_capacity())
	basket = CatchBasketAdapter.new(regs, stock, collection, balance)
	session = FishingSessionService.new(
		balance, habitat, generator, basket, pouch, luck, rng
	)
	session.context_builder = _fill_context
	session.first_catch_recorder = func() -> void: first_catch_done = true
	keepsakes = FishingKeepsakeService.new(regs, grid)
	spirit_adapter = ActivitySpiritAdapter.new(regs, pouch, progression)
	session.haul_committed.connect(func(_haul: FishingHaul) -> void:
		progression.on_fishing_haul_committed()
	)


func tick(delta: float) -> void:
	session.advance(delta)


## Fresh-world state for new_game / begin_onboarding_game.
func reset() -> void:
	session.cancel("reset")
	basket.clear()
	pouch.from_save_dict({})
	luck.from_save_dict({})
	keepsakes.clear()
	first_catch_done = false


## Activating a keepsake takes its charm from the basket and applies its
## behavior through the keepsake service.
func activate_keepsake_from_basket(haul_id: int) -> String:
	var keepsake_id := basket.take_keepsake(haul_id)
	if keepsake_id == "":
		return ""
	keepsakes.activate(keepsake_id)
	return keepsake_id


func _fill_context(context: FishingRollContext) -> void:
	context.unlock_groups = balance.unlock_groups()
	context.first_catch_pending = not first_catch_done
	var owned: Array[String] = collection.discovered_in("keepsakes")
	for haul: FishingHaul in basket.hauls:
		if haul.keepsake != null and not owned.has(haul.keepsake.building_id):
			owned.append(haul.keepsake.building_id)
	context.owned_keepsake_ids = owned


# ---------------------------------------------------------------- persistence

func to_save_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"first_catch_done": first_catch_done,
		"pouch": pouch.to_save_dict(),
		"basket": basket.to_save_dict(),
		"luck": luck.to_save_dict(),
		"keepsakes": keepsakes.to_save_dict(),
	}


func from_save_dict(data: Dictionary) -> void:
	# Loading cancels any in-progress cast; an armed-but-unconsumed Spirit
	# stays armed because reservations are never persisted.
	session.cancel("load")
	first_catch_done = bool(data.get("first_catch_done", false))
	pouch.from_save_dict(data.get("pouch", {}))
	basket.from_save_dict(data.get("basket", {}))
	luck.from_save_dict(data.get("luck", {}))
	keepsakes.from_save_dict(data.get("keepsakes", {}))


# ---------------------------------------------------------- debug & balancing

## Development-only helpers. Nothing here is reachable from player UI.

func debug_habitat_report(anchor: Vector2i) -> Dictionary:
	var sample := habitat.sample(anchor)
	return {
		"anchor": anchor,
		"themes": sample.theme_weights.duplicate(true),
		"normalized": sample.normalized(),
		"dominant": sample.dominant_theme(),
	}


func debug_fill_pouch(spirit_id := "spirit_grove") -> void:
	while not pouch.is_full():
		if not pouch.add_spirit(spirit_id):
			break


func debug_clear_pouch() -> void:
	pouch.from_save_dict({})


func debug_clear_basket() -> void:
	basket.clear()


## Generates and commits one catch immediately, skipping presentation.
## `forced_size` may pin single/rich/bountiful; `force_keepsake` appends the
## keepsake roll deterministically.
func debug_force_catch(
	anchor := Vector2i.ZERO,
	forced_size := "",
	force_keepsake := false
) -> FishingHaul:
	var context := FishingRollContext.new(habitat.sample(anchor))
	_fill_context(context)
	context.spirit_theme = pouch.theme_for(pouch.armed_spirit_id())
	var haul: FishingHaul
	if forced_size == "":
		haul = generator.generate_haul(context)
	else:
		haul = _generate_forced(context, forced_size)
	if force_keepsake and haul.keepsake == null:
		var saved_chance := luck.state.catches_since_keepsake
		luck.state.catches_since_keepsake = 1000000
		var boosted := generator.generate_haul(context)
		luck.state.catches_since_keepsake = saved_chance
		haul.keepsake = boosted.keepsake
	if not basket.commit(haul):
		return null
	luck.on_haul_committed(haul)
	if context.first_catch_pending:
		first_catch_done = true
	# A debug catch is a real catch: announcing it through the session signal
	# runs the same practice counting and onboarding hooks as live play.
	session.haul_committed.emit(haul)
	return haul


func debug_fill_basket() -> void:
	while not basket.is_full():
		if debug_force_catch() == null:
			break


func _generate_forced(
	context: FishingRollContext,
	forced_size: String
) -> FishingHaul:
	# Reuses the live generator by looping until the requested size lands —
	# the same services roll every value, no parallel approximation.
	for _attempt in 512:
		var haul := generator.generate_haul(context)
		if haul.catch_size == forced_size:
			return haul
	return generator.generate_haul(context)


## Deterministic large-run simulation through the SAME service classes as
## gameplay, on isolated state so a report never disturbs the live session.
func run_simulation(
	seed_value: int,
	catches: int,
	sample_anchor := Vector2i.ZERO,
	armed_spirit_theme := ""
) -> Dictionary:
	var sim_rng := RngService.new(seed_value)
	var sim_luck := HiddenLuckService.new(balance)
	var sim_composer := HaulComposer.new(balance, sim_rng)
	var sim_generator := FishingRewardGenerator.new(
		balance, catalog, sim_composer, sim_luck, sim_rng
	)
	var sample := habitat.sample(sample_anchor)
	var report := {
		"catches": catches,
		"seed": seed_value,
		"spirit_theme": armed_spirit_theme,
		"habitat": sample.normalized(),
		"sizes": {"single": 0, "rich": 0, "bountiful": 0},
		"forms": {"tile_bundle": 0, "model": 0},
		"rarities": {"common": 0, "uncommon": 0, "rare": 0},
		"themes": {},
		"loot": {},
		"keepsakes": 0,
		"tiles_granted": 0,
		"empty_pool_fallbacks": 0,
		"safe_fallback_uses": 0,
		"invalid_definitions": catalog.invalid_definition_count,
	}
	var context := FishingRollContext.new(sample)
	context.unlock_groups = balance.unlock_groups()
	context.spirit_theme = armed_spirit_theme
	context.first_catch_pending = false
	for _index in catches:
		var haul := sim_generator.generate_haul(context)
		sim_luck.on_haul_committed(haul)
		report["sizes"][haul.catch_size] = int(report["sizes"][haul.catch_size]) + 1
		for entry: FishingReward in haul.entries:
			report["forms"][entry.form] = int(report["forms"].get(entry.form, 0)) + 1
			report["rarities"][entry.rarity] = int(report["rarities"].get(entry.rarity, 0)) + 1
			report["loot"][entry.loot_id] = int(report["loot"].get(entry.loot_id, 0)) + 1
			if entry.form == FishingReward.FORM_TILE_BUNDLE:
				report["tiles_granted"] = int(report["tiles_granted"]) + entry.quantity
			var definition := catalog.definition(entry.loot_id)
			if definition != null:
				for theme: String in definition.theme_tags:
					report["themes"][theme] = int(report["themes"].get(theme, 0)) + 1
		if haul.has_keepsake():
			report["keepsakes"] = int(report["keepsakes"]) + 1
	report["empty_pool_fallbacks"] = sim_generator.empty_pool_fallbacks
	report["safe_fallback_uses"] = sim_generator.safe_fallback_uses
	return report

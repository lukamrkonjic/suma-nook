class_name DioramaModule
extends RefCounted
## Composition root for Suma's endless collectible diorama progression.

var enabled := true
var collections: CreativeCollectionService
var gifts: WorldGiftService
var tray: DiscoveryTrayService
var cadence: BuildCadenceService
var curiosities: WorldCuriosityService


func _init(
	registries: Registries,
	rng: RngService,
	grid: WorldGrid,
	collection: CollectionManager,
	nooks: NookModule,
	build_rewards: BuildRewardService
) -> void:
	enabled = registries.feature("endless_diorama_enabled", true)
	gifts = WorldGiftService.new(registries, nooks)
	collections = CreativeCollectionService.new(registries, collection, gifts)
	collections.set_rng(rng)
	tray = DiscoveryTrayService.new(registries, rng, collections)
	tray.initialize()
	cadence = BuildCadenceService.new(registries, rng, tray, gifts)
	curiosities = WorldCuriosityService.new(
		registries, rng, grid, nooks, build_rewards, collections, gifts
	)
	var self_ref: WeakRef = weakref(self)
	nooks.nook_revealed.connect(func(coord: Vector2i, plan):
		var module := self_ref.get_ref() as DioramaModule
		if module == null or not module.enabled:
			return
		module.collections.record_generated_plan(plan)
	)
	cadence.skyfall_due.connect(func(_sequence: int):
		var module := self_ref.get_ref() as DioramaModule
		if module == null or not module.enabled:
			return
		module.curiosities.land_skyfall(grid.home_cell)
	)


func new_game() -> void:
	tray.initialize()
	collections.sync_unlocks(false)


func to_save_dict() -> Dictionary:
	return {
		"version": 1,
		"tray": tray.to_save_dict(),
		"collections": collections.to_save_dict(),
		"gifts": gifts.to_save_dict(),
		"cadence": cadence.to_save_dict(),
		"curiosities": curiosities.to_save_dict(),
	}


func from_save_dict(data: Dictionary) -> void:
	gifts.from_save_dict(data.get("gifts", {}) as Dictionary)
	collections.from_save_dict(data.get("collections", {}) as Dictionary)
	tray.from_save_dict(data.get("tray", {}) as Dictionary)
	cadence.from_save_dict(data.get("cadence", {}) as Dictionary)
	curiosities.from_save_dict(data.get("curiosities", {}) as Dictionary)

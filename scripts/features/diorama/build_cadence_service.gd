class_name BuildCadenceService
extends RefCounted
## Invisible placement cadence. Only first placements from the Discovery Tray
## count; real time and rearranging old copies never advance it.

signal skyfall_due(sequence: int)

var registries: Registries
var rng: RngService
var tray: DiscoveryTrayService
var gifts: WorldGiftService
var placements := 0
var expansion_rewards := 0
var next_expansion_at := 0
var next_skyfall_at := 0
var skyfall_sequence := 0


func _init(
	content: Registries,
	rng_service: RngService,
	discovery_tray: DiscoveryTrayService,
	world_gifts: WorldGiftService
) -> void:
	registries = content
	rng = rng_service
	tray = discovery_tray
	gifts = world_gifts
	placements = tray.placements_committed
	next_expansion_at = int(registries.build_cadence_config.get("first_expansion_after", 6))
	next_skyfall_at = int(registries.build_cadence_config.get("skyfall_min", 8))
	var self_ref: WeakRef = weakref(self)
	tray.offer_committed.connect(func(_reward, _replacement, _slot):
		var service := self_ref.get_ref() as BuildCadenceService
		if service != null:
			service._on_offer_committed()
	)
	gifts.gift_consumed.connect(func(gift_id: String):
		var service := self_ref.get_ref() as BuildCadenceService
		if service != null and gift_id == "expansion_ripple":
			service._schedule_next_expansion()
	)


func _on_offer_committed() -> void:
	placements += 1
	if next_expansion_at > 0 and placements >= next_expansion_at:
		expansion_rewards += 1
		gifts.add(
			"expansion_ripple",
			1,
			"cadence:expansion:%d" % expansion_rewards
		)
		next_expansion_at = 0
	if next_skyfall_at > 0 and placements >= next_skyfall_at:
		skyfall_sequence += 1
		skyfall_due.emit(skyfall_sequence)
		_schedule_next_skyfall()


func to_save_dict() -> Dictionary:
	return {
		"placements": placements,
		"expansion_rewards": expansion_rewards,
		"next_expansion_at": next_expansion_at,
		"next_skyfall_at": next_skyfall_at,
		"skyfall_sequence": skyfall_sequence,
	}


func from_save_dict(data: Dictionary) -> void:
	placements = maxi(tray.placements_committed, int(data.get("placements", tray.placements_committed)))
	expansion_rewards = maxi(0, int(data.get("expansion_rewards", 0)))
	next_expansion_at = int(data.get(
		"next_expansion_at",
		int(registries.build_cadence_config.get("first_expansion_after", 6))
	))
	next_skyfall_at = int(data.get(
		"next_skyfall_at",
		placements + int(registries.build_cadence_config.get("skyfall_min", 8))
	))
	skyfall_sequence = maxi(0, int(data.get("skyfall_sequence", 0)))


func _schedule_next_expansion() -> void:
	if next_expansion_at > 0:
		return
	var minimum := int(registries.build_cadence_config.get("later_expansion_min", 22))
	var maximum := maxi(minimum, int(registries.build_cadence_config.get("later_expansion_max", 34)))
	next_expansion_at = placements + rng.randi_range(
		"diorama_expansion:%d" % expansion_rewards, minimum, maximum
	)


func _schedule_next_skyfall() -> void:
	var minimum := int(registries.build_cadence_config.get("skyfall_min", 8))
	var maximum := maxi(minimum, int(registries.build_cadence_config.get("skyfall_max", 15)))
	next_skyfall_at = placements + rng.randi_range(
		"diorama_skyfall:%d" % skyfall_sequence, minimum, maximum
	)

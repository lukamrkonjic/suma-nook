class_name InspirationSystem
extends RefCounted
## Domain-typed Inspiration meters and the well's Vision bank. Activities pay
## Inspiration into their domain; a full meter banks a Vision at the well.
## The bank holds at most `vision_bank_cap` Visions — at the cap, earning is
## refused (the current action always completes; refusal is the signal the
## presentation layer turns into "the world gestures toward the well").
## Each banked Vision also grants one stacking movement-speed step so the
## mandatory claim walk gets faster the fuller the well is.

signal inspiration_changed(domain_id: String, current: float, cost: float)
signal vision_banked(domain_id: String, banked_count: int)
signal bank_changed(banked_count: int, cap: int)
signal earning_blocked(domain_id: String)

var registries: Registries
var meters: Dictionary = {}        # domain_id -> float progress toward next Vision
var banked: Array[String] = []     # FIFO of domain ids waiting at the well
var first_vision_done := false     # fast-tracks the very first meter


func _init(regs: Registries) -> void:
	registries = regs


func bank_cap() -> int:
	return registries.tunei("vision_bank_cap", 3)


func can_earn() -> bool:
	return banked.size() < bank_cap()


func speed_stacks() -> int:
	return banked.size()


func speed_multiplier() -> float:
	return 1.0 + speed_stacks() * registries.tunef("vision_speed_bonus_per_stack", 0.12)


func meter_progress(domain_id: String) -> Dictionary:
	var cost := meter_cost(domain_id)
	var current := float(meters.get(domain_id, 0.0))
	return {
		"current": current,
		"cost": cost,
		"fraction": clampf(current / cost, 0.0, 1.0) if cost > 0.0 else 0.0,
	}


func meter_cost(domain_id: String) -> float:
	if not first_vision_done:
		return registries.tunef("first_vision_meter_cost", 36.0)
	var domain := registries.inspiration_domain(domain_id)
	if domain != null and domain.meter_cost > 0.0:
		return domain.meter_cost
	return registries.tunef("vision_meter_cost", 240.0)


## Adds Inspiration to a domain. Returns feedback for the presentation layer:
## {added: bool, banked: bool, blocked: bool}. Meter overflow past the bank
## cap is impossible — earning is refused instead, so no wisp is ever wasted.
func add(domain_id: String, amount: float) -> Dictionary:
	if registries.inspiration_domain(domain_id) == null or amount <= 0.0:
		return {"added": false, "banked": false, "blocked": false}
	if not can_earn():
		earning_blocked.emit(domain_id)
		return {"added": false, "banked": false, "blocked": true}
	var did_bank := false
	meters[domain_id] = float(meters.get(domain_id, 0.0)) + amount
	while can_earn() and meters[domain_id] >= meter_cost(domain_id):
		meters[domain_id] -= meter_cost(domain_id)
		first_vision_done = true
		banked.append(domain_id)
		did_bank = true
		vision_banked.emit(domain_id, banked.size())
		bank_changed.emit(banked.size(), bank_cap())
	inspiration_changed.emit(domain_id, float(meters[domain_id]), meter_cost(domain_id))
	return {"added": true, "banked": did_bank, "blocked": false}


## Pops the oldest banked Vision; "" when the well is empty.
func claim_next() -> String:
	if banked.is_empty():
		return ""
	var domain_id := banked[0]
	banked = banked.slice(1)
	bank_changed.emit(banked.size(), bank_cap())
	return domain_id


func to_save_dict() -> Dictionary:
	return {
		"meters": meters.duplicate(),
		"banked": banked.duplicate(),
		"first_vision_done": first_vision_done,
	}


func from_save_dict(data: Dictionary) -> void:
	meters.clear()
	var saved_meters: Dictionary = data.get("meters", {})
	for domain_id: String in saved_meters:
		if registries.inspiration_domain(domain_id) != null:
			meters[domain_id] = float(saved_meters[domain_id])
	banked.clear()
	for raw_domain in data.get("banked", []):
		var domain_id := String(raw_domain)
		if registries.inspiration_domain(domain_id) != null:
			banked.append(domain_id)
	first_vision_done = bool(data.get("first_vision_done", false))
	bank_changed.emit(banked.size(), bank_cap())

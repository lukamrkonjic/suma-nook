class_name CatchBasketAdapter
extends RewardDeliveryPort
## The physical Catch Basket beside the fishing keeper: three haul slots that
## stage every reward in the world. There is no general reward inventory —
## taking a piece hands it to the existing Build Library / placement pipeline,
## and cancelled tile placement returns unused copies to the bundle.

signal basket_changed
signal haul_stored(haul: FishingHaul)
signal haul_removed(haul_id: int)
signal keepsake_taken(keepsake_id: String)

var registries: Registries
var stock: StockManager
var collection: CollectionManager
var balance: FishingBalance

var hauls: Array[FishingHaul] = []
var next_haul_id := 1
## One bundle may be "checked out" to placement at a time:
## {haul_id, entry_index, tile_id, taken}
var active_bundle: Dictionary = {}


func _init(
	regs: Registries,
	stock_manager: StockManager,
	collection_manager: CollectionManager,
	balance_config: FishingBalance
) -> void:
	registries = regs
	stock = stock_manager
	collection = collection_manager
	balance = balance_config


func capacity() -> int:
	return balance.basket_capacity()


func is_full() -> bool:
	return hauls.size() >= capacity()


func haul_count() -> int:
	return hauls.size()


func haul_by_id(haul_id: int) -> FishingHaul:
	for haul: FishingHaul in hauls:
		if haul.haul_id == haul_id:
			return haul
	return null


## One committed haul occupies one slot, even a Bountiful triple.
func commit(haul: FishingHaul) -> bool:
	if haul == null or is_full():
		return false
	haul.haul_id = next_haul_id
	next_haul_id += 1
	hauls.append(haul)
	_record_discoveries(haul)
	haul_stored.emit(haul)
	basket_changed.emit()
	return true


## Checks a tile bundle out to the existing tile-placement flow. The copies
## enter the Build Library so PlacementController can consume them; the entry
## stays in its tray at quantity 0 until the checkout is reconciled.
func take_tile_bundle(haul_id: int, entry_index: int) -> Dictionary:
	if not active_bundle.is_empty():
		reconcile_bundle_checkout()
	var haul := haul_by_id(haul_id)
	if haul == null or entry_index < 0 or entry_index >= haul.entries.size():
		return {}
	var entry := haul.entries[entry_index]
	if entry.form != FishingReward.FORM_TILE_BUNDLE or entry.quantity <= 0:
		return {}
	var quantity := entry.quantity
	stock.add_tile(entry.building_id, quantity)
	entry.quantity = 0
	active_bundle = {
		"haul_id": haul_id,
		"entry_index": entry_index,
		"tile_id": entry.building_id,
		"taken": quantity,
	}
	basket_changed.emit()
	return {"tile_id": entry.building_id, "quantity": quantity}


## Ends a bundle checkout: unplaced copies come back out of the Build Library
## into the bundle. Copies are anonymous, so if the player already owned the
## same tile the reclaim may swap which exact copies sit where — totals across
## world, library, and basket are always preserved.
func reconcile_bundle_checkout() -> void:
	if active_bundle.is_empty():
		return
	var checkout := active_bundle
	active_bundle = {}
	var tile_id := String(checkout["tile_id"])
	var leftover := mini(int(checkout["taken"]), stock.tile_count(tile_id))
	for _index in leftover:
		stock.take_tile(tile_id)
	var haul := haul_by_id(int(checkout["haul_id"]))
	if haul == null:
		# The haul disappeared while checked out (should not happen in normal
		# flow); never lose copies — they stay in the Build Library.
		if leftover > 0:
			stock.add_tile(tile_id, leftover)
		return
	var entry_index := int(checkout["entry_index"])
	if entry_index >= 0 and entry_index < haul.entries.size():
		var entry := haul.entries[entry_index]
		entry.quantity = leftover
		if entry.quantity <= 0:
			haul.entries.remove_at(entry_index)
	_maybe_free(haul)
	basket_changed.emit()


func has_active_bundle() -> bool:
	return not active_bundle.is_empty()


## Hands one model to the Build Library and the existing placement flow.
func take_model(haul_id: int, entry_index: int) -> String:
	var haul := haul_by_id(haul_id)
	if haul == null or entry_index < 0 or entry_index >= haul.entries.size():
		return ""
	var entry := haul.entries[entry_index]
	if entry.form != FishingReward.FORM_MODEL:
		return ""
	stock.add_structure(entry.building_id, entry.quantity)
	haul.entries.remove_at(entry_index)
	_maybe_free(haul)
	basket_changed.emit()
	return entry.building_id


## Removes the keepsake charm from its haul; the keepsake service applies its
## behavior — the basket only stages the physical charm.
func take_keepsake(haul_id: int) -> String:
	var haul := haul_by_id(haul_id)
	if haul == null or haul.keepsake == null:
		return ""
	var keepsake_id := haul.keepsake.building_id
	haul.keepsake = null
	_maybe_free(haul)
	basket_changed.emit()
	keepsake_taken.emit(keepsake_id)
	return keepsake_id


## Returns an unwanted haul to the void. No currency, no compensation.
func discard_haul(haul_id: int) -> bool:
	var haul := haul_by_id(haul_id)
	if haul == null:
		return false
	if (
		not active_bundle.is_empty()
		and int(active_bundle.get("haul_id", 0)) == haul_id
	):
		reconcile_bundle_checkout()
		haul = haul_by_id(haul_id)
		if haul == null:
			return true
	hauls.erase(haul)
	haul_removed.emit(haul_id)
	basket_changed.emit()
	slot_freed.emit()
	return true


func _maybe_free(haul: FishingHaul) -> void:
	if haul.entries.is_empty() and haul.keepsake == null:
		hauls.erase(haul)
		haul_removed.emit(haul.haul_id)
		slot_freed.emit()


## The journal records a discovery at the moment the catch physically lands.
func _record_discoveries(haul: FishingHaul) -> void:
	for entry: FishingReward in haul.entries:
		match entry.form:
			FishingReward.FORM_TILE_BUNDLE:
				collection.record("tiles", entry.building_id, 0)
			FishingReward.FORM_MODEL:
				collection.record("structures", entry.building_id, 0)
	if haul.keepsake != null:
		collection.record("keepsakes", haul.keepsake.building_id, 0)


func clear() -> void:
	hauls.clear()
	active_bundle = {}
	basket_changed.emit()


func to_save_dict() -> Dictionary:
	var serialized: Array = []
	for haul: FishingHaul in hauls:
		serialized.append(haul.to_dict())
	return {
		"hauls": serialized,
		"next_haul_id": next_haul_id,
		"active_bundle": active_bundle.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	hauls.clear()
	active_bundle = {}
	for raw_haul in data.get("hauls", []):
		if not raw_haul is Dictionary:
			continue
		var haul := FishingHaul.from_dict(raw_haul)
		_sanitize_haul(haul)
		if haul.entries.is_empty() and haul.keepsake == null:
			continue
		if hauls.size() < capacity():
			hauls.append(haul)
	next_haul_id = maxi(1, int(data.get("next_haul_id", 1)))
	# A save taken mid-checkout reconciles on load: loading cancels placement
	# mode, so unplaced copies return from the Build Library to the bundle.
	var checkout: Variant = data.get("active_bundle", {})
	if checkout is Dictionary and not (checkout as Dictionary).is_empty():
		active_bundle = (checkout as Dictionary).duplicate(true)
		reconcile_bundle_checkout()
	basket_changed.emit()


## A save that references removed content keeps every valid entry and replaces
## a missing tile with the safe fallback rather than losing the haul.
func _sanitize_haul(haul: FishingHaul) -> void:
	var kept: Array[FishingReward] = []
	for entry: FishingReward in haul.entries:
		match entry.form:
			FishingReward.FORM_TILE_BUNDLE:
				if registries.tile(entry.building_id) == null:
					var fallback := registries.fishing_loot_definition(
						balance.fallback_loot_id()
					)
					if fallback == null:
						continue
					push_warning(
						"Fishing: basket bundle '%s' no longer exists; replaced with '%s'"
						% [entry.building_id, fallback.building_definition_id]
					)
					entry.building_id = fallback.building_definition_id
					entry.loot_id = fallback.id
				kept.append(entry)
			FishingReward.FORM_MODEL:
				if registries.structure(entry.building_id) != null:
					kept.append(entry)
				else:
					push_warning(
						"Fishing: basket model '%s' no longer exists; entry dropped"
						% entry.building_id
					)
			_:
				pass
	haul.entries = kept
	if (
		haul.keepsake != null
		and registries.keepsake(haul.keepsake.building_id) == null
	):
		haul.keepsake = null

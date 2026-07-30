class_name RefundSystem
extends RefCounted
## The deliberate duplicate sink. Unwanted owned pieces are refunded at the
## well; each domain's refund meter is rendered as carvings on the well
## itself. A full meter mints that domain's coin, which waits at the well
## (never in an inventory) and releases a guaranteed in-domain Vision.
## Refunds consume the piece — the well keeps what it is given.

signal refund_recorded(domain_id: String, meter: int, meter_size: int)
signal coin_minted(domain_id: String, coins: int)
signal coin_spent(domain_id: String)

var registries: Registries
var stock: StockManager
var visions: VisionSystem

var meters: Dictionary = {}   # domain_id -> refunds toward next coin
var coins: Dictionary = {}    # domain_id -> coins waiting at the well


func _init(regs: Registries, stock_manager: StockManager, vision_system: VisionSystem) -> void:
	registries = regs
	stock = stock_manager
	visions = vision_system


func meter_size() -> int:
	return registries.tunei("refund_meter_size", 3)


func meter(domain_id: String) -> int:
	return int(meters.get(domain_id, 0))


func coin_count(domain_id: String) -> int:
	return int(coins.get(domain_id, 0))


## The domain a piece refunds into. Tiles resolve through their family;
## structures through an explicit domain tag. Pieces with no domain (or the
## wildcard's) cannot be refunded — the UI never offers them.
func domain_of(kind: String, content_id: String) -> Defs.InspirationDomainDefinition:
	match kind:
		VisionSystem.KIND_TILE:
			var tile := registries.tile(content_id)
			if tile != null:
				return registries.domain_for_family(tile.family)
		VisionSystem.KIND_STRUCTURE:
			var structure := registries.structure(content_id)
			if structure != null:
				for domain: Defs.InspirationDomainDefinition in registries.inspiration_domains.values():
					if not domain.wildcard and structure.traits.has_tag(domain.id):
						return domain
	return null


func can_refund(kind: String, content_id: String) -> bool:
	if domain_of(kind, content_id) == null:
		return false
	match kind:
		VisionSystem.KIND_TILE:
			return stock.tile_count(content_id) > 0
		VisionSystem.KIND_STRUCTURE:
			return stock.structure_count(content_id) > 0
	return false


func refund(kind: String, content_id: String) -> bool:
	if not can_refund(kind, content_id):
		return false
	var taken := false
	match kind:
		VisionSystem.KIND_TILE:
			taken = stock.take_tile(content_id)
		VisionSystem.KIND_STRUCTURE:
			taken = stock.take_structure(content_id)
	if not taken:
		return false
	var domain := domain_of(kind, content_id)
	meters[domain.id] = meter(domain.id) + 1
	if meters[domain.id] >= meter_size():
		meters[domain.id] = 0
		coins[domain.id] = coin_count(domain.id) + 1
		coin_minted.emit(domain.id, coins[domain.id])
	refund_recorded.emit(domain.id, meter(domain.id), meter_size())
	return true


## Releases a waiting coin into a guaranteed in-domain Vision. Refused while
## another reveal is pending — the coin keeps waiting at the well.
func spend_coin(domain_id: String) -> bool:
	if coin_count(domain_id) < 1 or visions.has_pending():
		return false
	coins[domain_id] = coin_count(domain_id) - 1
	if coins[domain_id] <= 0:
		coins.erase(domain_id)
	var options := visions.begin_domain_locked(domain_id)
	if options.is_empty():
		coins[domain_id] = coin_count(domain_id) + 1
		return false
	coin_spent.emit(domain_id)
	return true


func to_save_dict() -> Dictionary:
	return {"meters": meters.duplicate(), "coins": coins.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	meters.clear()
	coins.clear()
	var saved_meters: Dictionary = data.get("meters", {})
	for domain_id: String in saved_meters:
		if registries.inspiration_domain(domain_id) != null:
			meters[domain_id] = int(saved_meters[domain_id])
	var saved_coins: Dictionary = data.get("coins", {})
	for domain_id: String in saved_coins:
		if registries.inspiration_domain(domain_id) != null:
			coins[domain_id] = int(saved_coins[domain_id])

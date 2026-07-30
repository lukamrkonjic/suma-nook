class_name LandParcelPayload
extends Resource
## Delivery data shared by every arrival presentation. The ferry knows only
## how to carry it; the progression module knows how to reveal its gift —
## a full-catalog Vision that never touches the well's bank.

var gift_kind: String = "vision"
var delivery_id: int = 0


func is_valid(_registries: Registries) -> bool:
	return gift_kind == "vision"


func to_dict() -> Dictionary:
	return {"gift_kind": gift_kind, "delivery_id": delivery_id}


static func from_dict(data: Dictionary) -> LandParcelPayload:
	var payload := LandParcelPayload.new()
	payload.gift_kind = String(data.get("gift_kind", "vision"))
	payload.delivery_id = int(data.get("delivery_id", 0))
	return payload

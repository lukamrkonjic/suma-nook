class_name LandParcelPayload
extends Resource
## Delivery data shared by every arrival presentation. The ferry knows only
## how to carry it; progression knows how to reveal its broad discovery.

var gift_kind: String = "discovery"
var delivery_id: int = 0


func is_valid(_registries: Registries) -> bool:
	return gift_kind == "discovery"


func to_dict() -> Dictionary:
	return {"gift_kind": gift_kind, "delivery_id": delivery_id}


static func from_dict(data: Dictionary) -> LandParcelPayload:
	var payload := LandParcelPayload.new()
	payload.gift_kind = String(data.get("gift_kind", "discovery"))
	payload.delivery_id = int(data.get("delivery_id", 0))
	return payload

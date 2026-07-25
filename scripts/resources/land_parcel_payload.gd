class_name LandParcelPayload
extends Resource
## Delivery data shared by every arrival presentation. The ferry knows only
## how to carry it; ParcelManager knows how to reveal its choices.

var parcel_id: String = "parcel_wild"
var delivery_id: int = 0


func is_valid(registries: Registries) -> bool:
	return registries.parcel(parcel_id) != null


func to_dict() -> Dictionary:
	return {"parcel_id": parcel_id, "delivery_id": delivery_id}


static func from_dict(data: Dictionary) -> LandParcelPayload:
	var payload := LandParcelPayload.new()
	payload.parcel_id = String(data.get("parcel_id", "parcel_wild"))
	payload.delivery_id = int(data.get("delivery_id", 0))
	return payload

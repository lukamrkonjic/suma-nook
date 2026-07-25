class_name InstantPostcardArrivalPresentation
extends ArrivalPresentationBase
## Lightweight debug proof that schedule/payload/library logic is not tied to
## the ferry presentation.


func play(point: DeliveryPoint, payload: LandParcelPayload, presentation_config: Dictionary) -> void:
	super.play(point, payload, presentation_config)
	if active:
		return
	active = true
	arrival_started.emit()
	arrived.emit()
	var timer := get_tree().create_timer(0.35)
	timer.timeout.connect(func():
		delivery_ready.emit(active_payload)
		departure_started.emit()
		active = false
		active_payload = null
		departed.emit()
	)


func force_departure() -> void:
	if active and active_payload != null:
		delivery_ready.emit(active_payload)
	active = false
	active_payload = null
	departed.emit()

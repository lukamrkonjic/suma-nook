class_name ArrivalPresentationBase
extends Node3D

signal arrival_started
signal arrived
signal delivery_ready(payload: LandParcelPayload)
signal departure_started
signal departed

var delivery_point: DeliveryPoint
var active_payload: LandParcelPayload
var config: Dictionary = {}
var materials: MaterialLibrary
var active := false


func setup(material_library: MaterialLibrary) -> void:
	materials = material_library


func play(point: DeliveryPoint, payload: LandParcelPayload, presentation_config: Dictionary) -> void:
	delivery_point = point
	active_payload = payload
	config = presentation_config


func force_departure() -> void:
	pass

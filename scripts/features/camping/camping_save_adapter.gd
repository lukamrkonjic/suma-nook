class_name CampingSaveAdapter
extends RefCounted

var shelters


func _init(shelter_system) -> void:
	shelters = shelter_system


func to_save_dict() -> Dictionary:
	return shelters.to_save_dict()


func from_save_dict(data: Dictionary) -> void:
	shelters.from_save_dict(data)

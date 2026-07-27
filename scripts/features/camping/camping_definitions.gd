class_name CampingDefinitions
extends RefCounted
## Typed view of camping capability payloads. Raw JSON dictionaries stop here;
## gameplay systems consume these explicit value objects.

class ShelterSpec:
	extends RefCounted
	var capacity: int
	var weather_resistance: float

	static func from_dict(data: Dictionary):
		var spec := ShelterSpec.new()
		spec.capacity = int(data.get("capacity", 1))
		spec.weather_resistance = float(data.get("weather_resistance", 0.0))
		return spec


class SleepSpec:
	extends RefCounted
	var capacity: int
	var comfort: int

	static func from_dict(data: Dictionary):
		var spec := SleepSpec.new()
		spec.capacity = int(data.get("capacity", 1))
		spec.comfort = int(data.get("comfort", 0))
		return spec


class StorageSpec:
	extends RefCounted
	var slots: int

	static func from_dict(data: Dictionary):
		var spec := StorageSpec.new()
		spec.slots = int(data.get("slots", 0))
		return spec


class DurabilitySpec:
	extends RefCounted
	var maximum: float

	static func from_dict(data: Dictionary):
		var spec := DurabilitySpec.new()
		spec.maximum = float(data.get("maximum", 100.0))
		return spec


class StructureCampingDefinition:
	extends RefCounted
	var structure_id: String
	var shelter: ShelterSpec
	var sleep: SleepSpec
	var storage: StorageSpec
	var durability: DurabilitySpec


var by_structure: Dictionary = {}


func _init(registries: Registries) -> void:
	for structure: Defs.StructureDefinition in registries.structures.values():
		if not _is_camping_structure(structure):
			continue
		var definition := StructureCampingDefinition.new()
		definition.structure_id = structure.id
		if structure.has_capability("shelter"):
			definition.shelter = ShelterSpec.from_dict(structure.capability("shelter"))
		if structure.has_capability("sleep"):
			definition.sleep = SleepSpec.from_dict(structure.capability("sleep"))
		if structure.has_capability("storage"):
			definition.storage = StorageSpec.from_dict(structure.capability("storage"))
		if structure.has_capability("durability"):
			definition.durability = DurabilitySpec.from_dict(structure.capability("durability"))
		by_structure[structure.id] = definition


func structure(structure_id: String):
	return by_structure.get(structure_id)


func _is_camping_structure(structure: Defs.StructureDefinition) -> bool:
	for capability_id in ["shelter", "sleep", "storage", "durability"]:
		if structure.has_capability(capability_id):
			return true
	return false

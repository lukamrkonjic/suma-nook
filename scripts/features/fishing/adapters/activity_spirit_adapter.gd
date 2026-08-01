class_name ActivitySpiritAdapter
extends RefCounted
## Translates narrow activity-completion events into Spirit Pouch requests.
## Fishing never calls woodcutting or mining code — each activity remains
## responsible for its own gameplay and only publishes that a full source
## cycle finished; the skill → spirit mapping is data on SpiritDefinition.

var registries: Registries
var pouch: SpiritPouchService


func _init(
	regs: Registries,
	pouch_service: SpiritPouchService,
	progression: ProgressionModule
) -> void:
	registries = regs
	pouch = pouch_service
	progression.activity_cycle_completed.connect(_on_activity_cycle_completed)


func _on_activity_cycle_completed(skill_id: String) -> void:
	for spirit: Defs.SpiritDefinition in registries.spirits.values():
		if spirit.source_skill == skill_id:
			pouch.add_spirit(spirit.id)
			return

class_name CampingModule
extends RefCounted
## Concrete feature composition. A generic module framework is intentionally
## deferred until another feature proves that the lifecycle is shared.

const DefinitionsScript := preload(
	"res://scripts/features/camping/camping_definitions.gd"
)
const ShelterSystemScript := preload(
	"res://scripts/features/camping/shelter_system.gd"
)
const SleepSystemScript := preload(
	"res://scripts/features/camping/sleep_system.gd"
)
const InteractionsScript := preload(
	"res://scripts/features/camping/camping_interactions.gd"
)
const SaveAdapterScript := preload(
	"res://scripts/features/camping/camping_save_adapter.gd"
)
const PresenterScript := preload(
	"res://scripts/features/camping/presentation/shelter_presenter.gd"
)

var definitions
var shelters
var sleep
var interactions
var save_adapter
var presenter


func _init(registries: Registries, grid: WorldGrid, stock: StockManager) -> void:
	definitions = DefinitionsScript.new(registries)
	shelters = ShelterSystemScript.new(grid, definitions, stock)
	sleep = SleepSystemScript.new(grid, definitions, shelters)
	interactions = InteractionsScript.new(sleep)
	save_adapter = SaveAdapterScript.new(shelters)
	presenter = PresenterScript.new(grid, definitions, shelters)


func reset() -> void:
	shelters.reset()


func to_save_dict() -> Dictionary:
	return save_adapter.to_save_dict()


func from_save_dict(data: Dictionary) -> void:
	save_adapter.from_save_dict(data)

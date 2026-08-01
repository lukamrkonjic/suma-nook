class_name GameContentCatalog
extends RefCounted
## Application-owned content composition. Registries remains feature-agnostic;
## this is the one explicit place shipped feature schemas are installed.

const CampingDefinitionValidatorScript := preload(
	"res://scripts/features/camping/camping_definition_validator.gd"
)
const ProgressionDefinitionValidatorScript := preload(
	"res://scripts/features/progression/progression_definition_validator.gd"
)
const FishingDefinitionValidatorScript := preload(
	"res://scripts/features/fishing/fishing_definition_validator.gd"
)


static func create() -> Registries:
	var registries := Registries.new()
	registries.register_validator(CampingDefinitionValidatorScript.validate)
	registries.register_validator(ProgressionDefinitionValidatorScript.validate)
	registries.register_validator(FishingDefinitionValidatorScript.validate)
	return registries

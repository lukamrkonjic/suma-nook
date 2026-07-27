class_name GameContentCatalog
extends RefCounted
## Application-owned content composition. Registries remains feature-agnostic;
## this is the one explicit place shipped feature schemas are installed.

const CampingDefinitionValidatorScript := preload(
	"res://scripts/features/camping/camping_definition_validator.gd"
)


static func create() -> Registries:
	var registries := Registries.new()
	registries.register_validator(CampingDefinitionValidatorScript.validate)
	return registries

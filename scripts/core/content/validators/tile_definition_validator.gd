class_name TileDefinitionValidator
extends RefCounted

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")

const SURFACE_KINDS := ["flat", "stairs", "uneven", "water"]
const RENDER_PROFILES := ["standard", "continuous_water"]
const COLLISION_PROFILES := ["flat", "pond_basin", "none"]
const DETAIL_PROFILES := ["", "grass_speckles"]


static func validate(snapshot, issues: Array) -> void:
	for definition: Defs.TileDefinition in snapshot.tiles.values():
		var source: Variant = snapshot.source("tiles", definition.id)
		_require(
			issues, definition.asset_id != "", "tile.asset.required", source, "asset_id",
			"asset id must not be empty"
		)
		_require(
			issues, definition.weight >= 0.0, "tile.weight.range", source, "weight",
			"parcel weight must be zero or greater"
		)
		_require(
			issues,
			definition.decor_sockets >= 0 and definition.structure_sockets >= 0,
			"tile.sockets.range", source, "decor_sockets",
			"socket counts must be zero or greater"
		)
		_require(
			issues, definition.structure_sockets <= 1, "tile.structure_sockets.unsupported",
			source, "structure_sockets", "multiple major sockets are not supported"
		)
		_require_member(
			issues, definition.surface_kind, SURFACE_KINDS, "tile.surface_kind.invalid",
			source, "surface_kind"
		)
		_require_member(
			issues, definition.render_profile, RENDER_PROFILES, "tile.render_profile.invalid",
			source, "render_profile"
		)
		_require_member(
			issues, definition.collision_profile, COLLISION_PROFILES,
			"tile.collision_profile.invalid", source, "collision_profile"
		)
		_require_member(
			issues, definition.surface_detail_profile, DETAIL_PROFILES,
			"tile.surface_detail_profile.invalid", source, "surface_detail_profile"
		)
		_require(
			issues, not definition.supports_tiles or definition.surface_kind == "flat",
			"tile.stack.surface", source, "supports_tiles",
			"tile stacking requires a flat surface"
		)
		_require(
			issues,
			definition.render_profile != "continuous_water"
			or definition.water_cells.has("open_water"),
			"tile.water.render_tag", source, "render_profile",
			"continuous water rendering requires the open_water tag"
		)
		_require(
			issues,
			definition.collision_profile != "pond_basin"
			or definition.water_cells.has("pond"),
			"tile.pond.collision_tag", source, "collision_profile",
			"pond collision requires the pond tag"
		)
		_require(
			issues, definition.structure_sockets <= 0 or definition.supports_decor,
			"tile.socket.decor_support", source, "structure_sockets",
			"a major socket requires decor support"
		)


static func _require(
	issues: Array,
	condition: bool,
	code: String,
	source,
	field: String,
	message: String
) -> void:
	if not condition:
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, code, source, field, message
		))


static func _require_member(
	issues: Array,
	value: String,
	allowed: Array,
	code: String,
	source,
	field: String
) -> void:
	_require(
		issues, allowed.has(value), code, source, field,
		"expected one of %s, received '%s'" % [allowed, value]
	)

class_name TileDefinitionValidator
extends RefCounted

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")

const SURFACE_KINDS := ["flat", "stairs", "uneven", "water"]
const RENDER_PROFILES := ["standard", "layered", "continuous_water"]
const COLLISION_PROFILES := ["flat", "pond_basin", "none"]
const DETAIL_PROFILES := ["", "grass_speckles"]
const SOFT_SURFACE_PROFILES := ["", "sand", "snow"]
const LAYER_ROLES := ["base", "surface", "detail", "edge"]
const COVER_BEHAVIORS := ["persist", "hide"]
const SCALE_MODES := ["tile_xz", "none"]


static func validate(snapshot, issues: Array) -> void:
	for definition: Defs.TileDefinition in snapshot.tiles.values():
		var source: Variant = snapshot.source("tiles", definition.id)
		if definition.render_profile != "layered":
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
		if definition.render_profile == "layered":
			_validate_layers(definition, source, issues)
		_require_member(
			issues, definition.collision_profile, COLLISION_PROFILES,
			"tile.collision_profile.invalid", source, "collision_profile"
		)
		_require_member(
			issues, definition.surface_detail_profile, DETAIL_PROFILES,
			"tile.surface_detail_profile.invalid", source, "surface_detail_profile"
		)
		_require_member(
			issues, definition.soft_surface_profile, SOFT_SURFACE_PROFILES,
			"tile.soft_surface_profile.invalid", source, "soft_surface_profile"
		)
		_require(
			issues,
			definition.walk_surface_height >= 0.0
			and definition.walk_surface_height <= 0.15,
			"tile.walk_surface_height.range", source, "walk_surface_height",
			"walk surface height must be between 0 and 0.15 metres"
		)
		_require(
			issues,
			definition.soft_surface_profile == ""
			or (
				definition.walkable
				and definition.collision_profile == "flat"
				and definition.exposed_top == "raised"
			),
			"tile.soft_surface.contract", source, "soft_surface_profile",
			"soft terrain requires a raised, walkable tile with flat collision"
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


static func _validate_layers(
	definition: Defs.TileDefinition,
	source,
	issues: Array
) -> void:
	var role_counts := {}
	for index in definition.visual_layers.size():
		var layer: Defs.TileVisualLayerDefinition = definition.visual_layers[index]
		var field_prefix := "layers[%d]" % index
		_require_member(
			issues, layer.role, LAYER_ROLES, "tile.layer.role.invalid",
			source, "%s.role" % field_prefix
		)
		_require(
			issues, layer.asset_id != "", "tile.layer.asset.required",
			source, "%s.asset_id" % field_prefix, "layer asset id must not be empty"
		)
		_require_member(
			issues, layer.cover_behavior, COVER_BEHAVIORS,
			"tile.layer.cover_behavior.invalid",
			source, "%s.cover_behavior" % field_prefix
		)
		_require_member(
			issues, layer.scale_mode, SCALE_MODES, "tile.layer.scale_mode.invalid",
			source, "%s.scale_mode" % field_prefix
		)
		role_counts[layer.role] = int(role_counts.get(layer.role, 0)) + 1
		if layer.role == "base":
			_require(
				issues, layer.cover_behavior == "persist",
				"tile.layer.base.cover_behavior", source,
				"%s.cover_behavior" % field_prefix,
				"the structural base must persist when a tile is covered"
			)
	_require(
		issues, int(role_counts.get("base", 0)) == 1, "tile.layer.base.count",
		source, "layers", "a layered tile requires exactly one base layer"
	)
	_require(
		issues, int(role_counts.get("surface", 0)) == 1, "tile.layer.surface.count",
		source, "layers", "a layered tile requires exactly one surface layer"
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

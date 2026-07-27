class_name StructureDefinitionValidator
extends RefCounted

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")

const SOCKET_TYPES := ["decor", "structure"]
const COLLISION_PROFILES := ["blocker", "walkable_surface", "none"]
const GRID_FIT_PROFILES := ["", "tile_span"]
const SURFACE_KINDS := ["flat", "stairs", "uneven", "water"]


static func validate(snapshot, issues: Array) -> void:
	for definition: Defs.StructureDefinition in snapshot.structures.values():
		var source: Variant = snapshot.source("structures", definition.id)
		_require(
			issues, definition.asset_id != "", "structure.asset.required", source, "asset_id",
			"asset id must not be empty"
		)
		_require_member(
			issues, definition.socket_type, SOCKET_TYPES, "structure.socket_type.invalid",
			source, "socket_type"
		)
		_require_member(
			issues, definition.collision_profile, COLLISION_PROFILES,
			"structure.collision_profile.invalid", source, "collision_profile"
		)
		_require_member(
			issues, definition.grid_fit_profile, GRID_FIT_PROFILES,
			"structure.grid_fit_profile.invalid", source, "grid_fit_profile"
		)
		_require(
			issues, not definition.allowed_surface_kinds.is_empty(),
			"structure.allowed_surfaces.required", source, "allowed_surfaces",
			"at least one placement surface is required"
		)
		for index in definition.allowed_surface_kinds.size():
			_require_member(
				issues, definition.allowed_surface_kinds[index], SURFACE_KINDS,
				"structure.allowed_surfaces.invalid", source, "allowed_surfaces[%d]" % index
			)
		_require(
			issues, definition.placement_policy_explicit,
			"structure.placement_policy.required", source, "placement_tags",
			"placement_tags, can_be_stacked, and support_slots must be explicit"
		)
		_require(
			issues, not definition.placement_tags.is_empty(),
			"structure.placement_tags.required", source, "placement_tags",
			"at least one placement tag is required"
		)
		if definition.preserve_instance_state:
			_require(
				issues, not definition.capabilities.is_empty(),
				"structure.stateful.capability_required", source,
				"preserve_instance_state",
				"stateful structures must expose at least one owned capability"
			)
		var support_slot_ids := {}
		for index in definition.support_slots.size():
			var slot: Defs.SupportSlotDefinition = definition.support_slots[index]
			var field := "support_slots[%d]" % index
			_require(
				issues, slot.id != "", "structure.support_slot.id", source, field + ".id",
				"support slot id must not be empty"
			)
			_require(
				issues, not support_slot_ids.has(slot.id), "structure.support_slot.duplicate",
				source, field + ".id", "support slot id '%s' is duplicated" % slot.id
			)
			support_slot_ids[slot.id] = true
			_require(
				issues, not slot.accepts.is_empty(), "structure.support_slot.accepts",
				source, field + ".accepts", "support slot must accept at least one placement tag"
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

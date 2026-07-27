class_name CommonDefinitionValidator
extends RefCounted
## Global definition contract. Every current and future content family passes
## through this before feature-specific validation.

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)


static func validate(snapshot, issues: Array) -> void:
	for kind: String in snapshot.DEFINITION_KINDS:
		for content_id: String in snapshot.definitions(kind):
			var definition: Resource = snapshot.definitions(kind)[content_id]
			var source = snapshot.source(kind, content_id)
			_require(
				issues, source != null, "definition.source.missing", source, "id",
				"definition has no source provenance"
			)
			_require(
				issues, String(definition.get("id")) == content_id,
				"definition.id.mismatch", source, "id",
				"parsed id does not match catalog key '%s'" % content_id
			)
			_require(
				issues, _is_stable_id(content_id), "definition.id.invalid",
				source, "id",
				"use a stable lowercase id containing letters, numbers, or underscores"
			)
			var traits: Defs.DefinitionTraits = definition.get("traits")
			_require(
				issues, traits != null, "definition.traits.missing", source,
				"traits", "every definition family must expose common traits"
			)
			if traits == null:
				continue
			for parse_error: String in traits.parse_errors:
				issues.append(ValidationIssueScript.new(
					ValidationIssueScript.Severity.ERROR,
					"definition.traits.invalid", source, "traits", parse_error
				))
			var seen_tags := {}
			for index in traits.tags.size():
				var tag := traits.tags[index]
				_require(
					issues, tag != "", "definition.tag.empty", source,
					"tags[%d]" % index, "tags must not be empty"
				)
				_require(
					issues, not seen_tags.has(tag), "definition.tag.duplicate",
					source, "tags[%d]" % index, "tag '%s' is duplicated" % tag
				)
				seen_tags[tag] = true
			for capability_id: String in traits.capabilities:
				_require(
					issues, snapshot.capabilities.has(capability_id),
					"definition.capability.unknown", source,
					"capabilities.%s" % capability_id,
					"capability '%s' is not registered" % capability_id
				)


static func _is_stable_id(content_id: String) -> bool:
	if content_id == "":
		return false
	for index in content_id.length():
		var character := content_id[index]
		if (
			not character.is_valid_identifier()
			and not character.is_valid_int()
		):
			return false
	return content_id == content_id.to_lower() and not content_id[0].is_valid_int()


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

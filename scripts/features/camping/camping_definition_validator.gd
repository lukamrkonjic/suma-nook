class_name CampingDefinitionValidator
extends RefCounted

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")


static func validate(snapshot, issues: Array) -> void:
	for definition: Defs.StructureDefinition in snapshot.structures.values():
		var source: Variant = snapshot.source("structures", definition.id)
		if definition.has_capability("shelter"):
			var shelter := definition.capability("shelter")
			_positive_int(issues, source, "capabilities.shelter.capacity", shelter, "capacity")
			_float_range(
				issues, source, "capabilities.shelter.weather_resistance",
				shelter, "weather_resistance", 0.0, 1.0
			)
		if definition.has_capability("sleep"):
			var sleep := definition.capability("sleep")
			_positive_int(issues, source, "capabilities.sleep.capacity", sleep, "capacity")
			_non_negative_int(issues, source, "capabilities.sleep.comfort", sleep, "comfort")
			_require(
				issues, definition.has_capability("shelter"),
				"camping.sleep.requires_shelter", source, "capabilities.sleep",
				"sleep capability requires a shelter capability"
			)
			if definition.has_capability("shelter"):
				_require(
					issues,
					int(sleep.get("capacity", 0))
					<= int(definition.capability("shelter").get("capacity", 0)),
					"camping.sleep.capacity", source, "capabilities.sleep.capacity",
					"sleep capacity cannot exceed shelter capacity"
				)
		if definition.has_capability("storage"):
			_positive_int(
				issues, source, "capabilities.storage.slots",
				definition.capability("storage"), "slots"
			)
		if definition.has_capability("durability"):
			_positive_float(
				issues, source, "capabilities.durability.maximum",
				definition.capability("durability"), "maximum"
			)


static func _positive_int(
	issues: Array, source, field: String, data: Dictionary, key: String
) -> void:
	_require(
		issues, _is_integer_number(data.get(key)) and int(data[key]) > 0,
		"camping.integer.positive", source, field,
		"expected an integer greater than zero"
	)


static func _non_negative_int(
	issues: Array, source, field: String, data: Dictionary, key: String
) -> void:
	_require(
		issues, _is_integer_number(data.get(key)) and int(data[key]) >= 0,
		"camping.integer.non_negative", source, field,
		"expected an integer zero or greater"
	)


static func _positive_float(
	issues: Array, source, field: String, data: Dictionary, key: String
) -> void:
	_require(
		issues,
		data.has(key) and (data[key] is float or data[key] is int) and float(data[key]) > 0.0,
		"camping.number.positive", source, field,
		"expected a number greater than zero"
	)


static func _float_range(
	issues: Array,
	source,
	field: String,
	data: Dictionary,
	key: String,
	minimum: float,
	maximum: float
) -> void:
	_require(
		issues,
		data.has(key)
		and (data[key] is float or data[key] is int)
		and float(data[key]) >= minimum
		and float(data[key]) <= maximum,
		"camping.number.range", source, field,
		"expected a number in the range %.2f to %.2f" % [minimum, maximum]
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


static func _is_integer_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(value, roundf(value))

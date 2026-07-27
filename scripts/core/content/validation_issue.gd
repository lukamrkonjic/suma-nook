class_name ValidationIssue
extends RefCounted
## Machine-readable validation result with a human-readable source location.

enum Severity {
	WARNING,
	ERROR,
}

var severity := Severity.ERROR
var code: String
var source
var field: String
var message: String


func _init(
	issue_severity: int,
	issue_code: String,
	issue_source,
	issue_field: String,
	issue_message: String
) -> void:
	severity = issue_severity
	code = issue_code
	source = issue_source
	field = issue_field
	message = issue_message


func format() -> String:
	var prefix: String = source.location(field) if source != null else field
	if prefix == "":
		prefix = "<content>"
	return "%s: %s [%s]" % [prefix, message, code]

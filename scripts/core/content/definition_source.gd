class_name DefinitionSource
extends RefCounted
## Exact provenance for one loaded definition. Validation keeps this separate
## from runtime definitions so gameplay resources stay focused on immutable
## content facts.

var path: String
var kind: String
var root_key: String
var entry_index: int
var content_id: String


func _init(
	source_path: String,
	source_kind: String,
	source_root_key: String,
	source_entry_index: int,
	source_content_id: String
) -> void:
	path = source_path
	kind = source_kind
	root_key = source_root_key
	entry_index = source_entry_index
	content_id = source_content_id


func location(field: String = "") -> String:
	var out := "%s[%d]" % [path, entry_index]
	if content_id != "":
		out += " %s" % content_id
	if field != "":
		out += ".%s" % field
	return out

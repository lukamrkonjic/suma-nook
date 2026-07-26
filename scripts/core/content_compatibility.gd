class_name ContentCompatibility
extends RefCounted
## Stable content-ID compatibility catalog.
##
## Save schema versions describe the shape of a save. This catalog revision
## describes changes to content identifiers. Shipped IDs remain valid forever:
## aliases rename them, while retired entries may name a replacement. An entry
## without a replacement is preserved through a generated compatibility
## definition rather than silently deleting player-owned content.

const KINDS := ["tiles", "structures", "items", "parcels", "landmarks", "enemies", "skills"]

var revision := 0
var aliases: Dictionary = {}
var retired: Dictionary = {}
var load_errors: PackedStringArray = []


func load_from(path: String) -> bool:
	load_errors.clear()
	if not FileAccess.file_exists(path):
		load_errors.append("missing compatibility catalog " + path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_errors.append("invalid compatibility JSON in " + path)
		return false
	revision = int(parsed.get("revision", 0))
	var raw_aliases: Variant = parsed.get("aliases", {})
	var raw_retired: Variant = parsed.get("retired", {})
	if not raw_aliases is Dictionary or not raw_retired is Dictionary:
		load_errors.append("compatibility aliases and retired sections must be objects")
		return false
	aliases = raw_aliases.duplicate(true)
	retired = raw_retired.duplicate(true)
	for kind in KINDS:
		if not aliases.has(kind):
			aliases[kind] = {}
		elif not aliases[kind] is Dictionary:
			load_errors.append("compatibility aliases.%s must be an object" % kind)
			aliases[kind] = {}
		if not retired.has(kind):
			retired[kind] = {}
		elif not retired[kind] is Dictionary:
			load_errors.append("compatibility retired.%s must be an object" % kind)
			retired[kind] = {}
	_validate_cycles()
	return load_errors.is_empty()


func resolve_id(kind: String, raw_id: String) -> String:
	if raw_id == "":
		return ""
	var current := raw_id
	var visited := {}
	for _hop in 32:
		if visited.has(current):
			return current
		visited[current] = true
		var kind_aliases: Dictionary = aliases.get(kind, {})
		if kind_aliases.has(current):
			current = String(kind_aliases[current])
			continue
		var kind_retired: Dictionary = retired.get(kind, {})
		if kind_retired.has(current):
			var policy: Variant = kind_retired[current]
			var replacement := ""
			if policy is String:
				replacement = String(policy)
			elif policy is Dictionary:
				replacement = String(policy.get("replacement", ""))
			if replacement != "":
				current = replacement
				continue
		return current
	return current


func is_retired(kind: String, content_id: String) -> bool:
	return (retired.get(kind, {}) as Dictionary).has(content_id)


func _validate_cycles() -> void:
	for kind: String in KINDS:
		var kind_aliases: Dictionary = aliases[kind]
		var kind_retired: Dictionary = retired[kind]
		var sources := {}
		for content_id: String in kind_aliases:
			sources[content_id] = true
			if String(kind_aliases[content_id]) == "":
				load_errors.append("empty content alias target in %s at '%s'" % [kind, content_id])
		for content_id: String in kind_retired:
			sources[content_id] = true
			var policy: Variant = kind_retired[content_id]
			if not policy is String and not policy is Dictionary:
				load_errors.append("invalid retired policy in %s at '%s'" % [kind, content_id])
		for content_id: String in sources:
			var current := content_id
			var visited := {}
			for _hop in 64:
				if visited.has(current):
					load_errors.append(
						"content alias cycle in %s at '%s'" % [kind, content_id]
					)
					break
				visited[current] = true
				var next := ""
				if kind_aliases.has(current):
					next = String(kind_aliases[current])
				elif kind_retired.has(current):
					var policy: Variant = kind_retired[current]
					if policy is String:
						next = String(policy)
					elif policy is Dictionary:
						next = String(policy.get("replacement", ""))
				if next == "":
					break
				current = next

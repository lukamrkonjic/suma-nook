class_name CharacterBodyCatalog
extends Resource
## Ordered, player-facing body selections. Saved profiles store only the
## option index; invalid or legacy values safely fall back to option zero.

@export var options: Array[CharacterBodyOption] = []


func option_for(index: int) -> CharacterBodyOption:
	if options.is_empty():
		return null
	if index < 0 or index >= options.size():
		return options[0]
	return options[index]


func display_names() -> PackedStringArray:
	var names := PackedStringArray()
	for option in options:
		names.append(option.display_name if option != null else "?")
	return names


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if options.is_empty():
		errors.append("body catalog has no options")
	var seen: Dictionary = {}
	for option in options:
		if option == null:
			errors.append("body catalog contains a null option")
			continue
		errors.append_array(option.validation_errors())
		if seen.has(option.option_id):
			errors.append("duplicate body option '%s'" % option.option_id)
		seen[option.option_id] = true
	return errors

class_name FishingHabitatSample
extends RefCounted
## Immutable snapshot of one 3x3 edge neighborhood, reduced to broad weighted
## theme tags. Built once per cast by the habitat adapter; the reward pipeline
## only ever reads it.

var anchor := Vector2i.ZERO
var world_revision := 0
var theme_weights: Dictionary = {}   # theme (String) -> accumulated weight


func _init(
	sample_anchor := Vector2i.ZERO,
	revision := 0,
	weights: Dictionary = {}
) -> void:
	anchor = sample_anchor
	world_revision = revision
	theme_weights = weights.duplicate(true)


func weight(theme: String) -> float:
	return float(theme_weights.get(theme, 0.0))


func themes() -> Array[String]:
	var result: Array[String] = []
	for theme: String in theme_weights:
		result.append(theme)
	result.sort()
	return result


func dominant_theme() -> String:
	var best := ""
	var best_weight := 0.0
	for theme: String in theme_weights:
		if float(theme_weights[theme]) > best_weight:
			best = theme
			best_weight = float(theme_weights[theme])
	return best


func normalized() -> Dictionary:
	var total := 0.0
	for theme: String in theme_weights:
		total += float(theme_weights[theme])
	if total <= 0.0:
		return {}
	var result := {}
	for theme: String in theme_weights:
		result[theme] = float(theme_weights[theme]) / total
	return result

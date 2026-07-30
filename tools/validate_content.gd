extends SceneTree
## Fast content-only validation for CRUD iteration.
##
## Run:
##   Godot --headless --path . --script tools/validate_content.gd

const GameContentCatalogScript := preload(
	"res://scripts/core/game_content_catalog.gd"
)
const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)


func _init() -> void:
	var registries = GameContentCatalogScript.create()
	var valid := registries.load_all("res://data", false)
	for issue in registries.load_issues:
		var label := (
			"WARNING"
			if issue.severity == ValidationIssueScript.Severity.WARNING
			else "ERROR"
		)
		print("%s: %s" % [label, issue.format()])
	if valid:
		print(
			"CONTENT VALIDATION PASSED — %d definitions"
			% _definition_count(registries)
		)
		quit(0)
	else:
		print("CONTENT VALIDATION FAILED — %d errors" % registries.load_errors.size())
		quit(1)


func _definition_count(registries) -> int:
	var total := 0
	for kind: String in registries.definition_kinds():
		total += registries.definitions(kind).size()
	return total

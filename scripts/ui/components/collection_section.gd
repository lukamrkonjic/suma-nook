class_name CollectionSection
extends VBoxContainer
## Reusable visual grouping for one Build Bag collection.

var category_id := ""
var divider_node: CollectionDivider
var grid: GridContainer


func setup(
	kit: UiKit,
	id: String,
	section_name: String,
	accent: Color,
	glyph: String,
	columns: int
) -> void:
	category_id = id
	name = "BuildSection_%s" % id
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", kit.tokens.divider_gap)

	divider_node = CollectionDivider.new()
	divider_node.setup(kit, section_name, accent, glyph)
	add_child(divider_node)

	grid = GridContainer.new()
	grid.name = "BuildGrid_%s" % id
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", kit.tokens.cell_gap)
	grid.add_theme_constant_override("v_separation", kit.tokens.row_gap)
	add_child(grid)


func set_columns(columns: int) -> void:
	if grid != null:
		grid.columns = columns


func add_item(control: Control) -> void:
	grid.add_child(control)

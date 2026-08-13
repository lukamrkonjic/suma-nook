class_name SumaUiTheme
extends Resource
## Central presentation tokens for every player-facing interface.
##
## Screens own their content and behavior. UiKit and reusable UI components
## resolve these semantic roles through the canonical PaletteDefinition so
## spacing, proportions, motion, and colour do not drift between surfaces.

@export_category("Palette roles")
@export var color_tokens: Dictionary = {}

@export_category("Sheet geometry")
@export_range(0.5, 0.9, 0.01) var sheet_width_ratio := 0.68
@export_range(0.3, 0.7, 0.01) var sheet_height_ratio := 0.44
@export var minimum_sheet_size := Vector2(680, 360)
@export var sheet_bottom_margin := 20
@export var sheet_padding := 22
@export var sheet_corner_radius := 18
@export var control_corner_radius := 12
@export var cell_corner_radius := 10
@export var hairline_width := 1
@export var focus_width := 2

@export_category("Collection grid")
@export var reference_cell_size := Vector2(112, 112)
@export var minimum_columns := 4
@export var maximum_columns := 10
@export var column_reference_width := 170.0
@export var cell_gap := 6
@export var row_gap := 14
@export var section_gap := 28
@export var divider_gap := 10
@export var marker_visual_size := 13
@export var marker_hit_size := 30
@export var scrollbar_width := 7

@export_category("Typography")
@export var body_font_size := 18
@export var quantity_font_size := 13
@export var tooltip_font_size := 17
@export var utility_font_size := 14
@export var title_font_size := 32

@export_category("Motion")
@export var open_duration := 0.18
@export var close_duration := 0.14
@export var hover_duration := 0.11
@export var hover_scale := 1.03
@export var pressed_scale := 0.98
@export var open_offset := 12.0


func token(role: String, fallback := "ui_text_primary") -> String:
	return String(color_tokens.get(role, fallback))


func sheet_size(viewport_size: Vector2) -> Vector2:
	return Vector2(
		minf(
			maxf(minimum_sheet_size.x, viewport_size.x * sheet_width_ratio),
			viewport_size.x - 32.0
		),
		minf(
			maxf(minimum_sheet_size.y, viewport_size.y * sheet_height_ratio),
			viewport_size.y - 48.0
		)
	)


func columns_for(viewport_width: float) -> int:
	return clampi(
		int(round(viewport_width / column_reference_width)),
		minimum_columns,
		maximum_columns
	)

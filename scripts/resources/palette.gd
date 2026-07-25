class_name CozyPalette
extends Resource
## Shared color vocabulary for the whole game. Every material, UI tint, and
## generated asset color routes through this resource so the look stays coherent.
## Keep in sync with the PALETTE dict in art_source/procedural/build_assets.py.

@export var colors: Dictionary = {}

## Skin/hair choices offered by the character creator (indices are saved).
@export var skin_tones: PackedColorArray = []
@export var hair_colors: PackedColorArray = []
@export var outfit_colors: PackedColorArray = []


func color(key: String, fallback := Color.MAGENTA) -> Color:
	var value: Variant = colors.get(key)
	return value if value is Color else fallback

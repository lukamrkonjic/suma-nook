class_name PixelLook
extends CanvasLayer
## Optional retro presentation, ported from Imota's pixel pipeline
## (imota-idle: RenderViewportPresenter + palette_snap.gdshader). Imota
## renders its world into a low-resolution SubViewport and presents it at an
## exact integer scale; Suma keeps its scene tree and picking untouched and
## gets the same read from one full-screen pass that snaps the rendered
## world to integer pixel blocks and optionally cel-posterizes colour.
##
## The layer sits below every UI CanvasLayer, so menus and the HUD stay
## crisp while only the world pixelates — same split as Imota.

const PIXEL_SHADER := preload("res://assets/materials/reworked/pixel_present.gdshader")

## Imota's presenter levels: display pixels per world pixel at each
## "Pixel size" dropdown index (index 0 = off / crisp render).
const PIXEL_LEVELS := [1, 2, 3, 4, 5, 6, 8]
const CEL_STRENGTH := 0.85
const PAINTERLY_PIXEL_SIZE := 4.0

var _rect: ColorRect
var _material: ShaderMaterial


func _init() -> void:
	# Layer 0 draws after the 3D scene (and after the lighting rig's grade
	# pass, which is added to the tree earlier) but below the HUD at layer 1.
	# A negative layer would be treated as the 3D background whenever the
	# environment uses BG_CANVAS, which the GG backdrop relies on.
	layer = 0


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = PIXEL_SHADER
	_rect = ColorRect.new()
	_rect.name = "PixelPresent"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	visible = false


## Painterly mode is the live default art direction from the first retro
## visual push. When the toggle is off, `level_index` and `cel` retain the
## older optional retro presentation.
func apply(level_index: int, cel: bool, painterly := false) -> void:
	if _material == null:
		return
	if painterly:
		_apply_painterly()
		return
	var index := clampi(level_index, 0, PIXEL_LEVELS.size() - 1)
	_material.set_shader_parameter("pixel_size", float(PIXEL_LEVELS[index]))
	_material.set_shader_parameter("posterize_strength", CEL_STRENGTH if cel else 0.0)
	_material.set_shader_parameter("contrast", 1.0)
	_material.set_shader_parameter("saturation", 1.0)
	_material.set_shader_parameter("brightness", 1.0)
	_material.set_shader_parameter("value_steps", 10.0)
	_material.set_shader_parameter("sat_steps", 7.0)
	_material.set_shader_parameter("painterly_strength", 0.0)
	_material.set_shader_parameter("dither_strength", 0.0)
	visible = index > 0 or cel


## Ultra-realistic mode deliberately applies no fullscreen stylization. Native
## PBR materials, the environment tonemapper, reflections, and shadowing own
## the image; the optional legacy pixel controls still work when this is off.
func _apply_realistic() -> void:
	visible = false


## Outline-free moving pixel painting: medium-size blocks retain silhouettes,
## broad colour ramps replace smooth gradients, and extremely light ordered
## breakup keeps large surfaces from reading as a flat posterize filter.
func _apply_painterly() -> void:
	_material.set_shader_parameter("pixel_size", PAINTERLY_PIXEL_SIZE)
	_material.set_shader_parameter("posterize_strength", 0.76)
	_material.set_shader_parameter("contrast", 1.0)
	_material.set_shader_parameter("saturation", 1.08)
	_material.set_shader_parameter("brightness", 1.055)
	_material.set_shader_parameter("value_steps", 12.0)
	_material.set_shader_parameter("sat_steps", 10.0)
	_material.set_shader_parameter("painterly_strength", 1.0)
	_material.set_shader_parameter("dither_strength", 0.025)
	visible = true

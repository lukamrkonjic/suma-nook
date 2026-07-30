extends SceneTree
## Rebuilds the two small deterministic 3D textures used by the cloud shader.
## Run with:
## Godot --headless --path . --script res://tools/generate_cloud_noise.gd

const SIZE := 64
const OUTPUT_DIRECTORY := "res://assets/textures/clouds"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	)
	var started := Time.get_ticks_msec()
	var shape_error := _save_texture(
		_build_shape_noise(),
		"%s/cloud_shape_noise.png" % OUTPUT_DIRECTORY,
		false
	)
	if shape_error != OK:
		push_error(
			"Cloud texture bake failed (%d)." % shape_error
		)
		quit(1)
		return
	print(
		"CLOUD_NOISE_BAKED size=%d elapsed_ms=%d"
		% [SIZE, Time.get_ticks_msec() - started]
	)
	quit()


func _build_shape_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = 27183
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.052
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.05
	noise.fractal_gain = 0.52
	noise.domain_warp_enabled = true
	noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	noise.domain_warp_amplitude = 13.0
	noise.domain_warp_frequency = 0.035
	noise.domain_warp_fractal_type = (
		FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	)
	noise.domain_warp_fractal_octaves = 3
	return noise


func _save_texture(
	noise: FastNoiseLite,
	path: String,
	invert: bool
) -> Error:
	var images: Array[Image] = noise.get_image_3d(
		SIZE,
		SIZE,
		SIZE,
		invert,
		true
	)
	if images.size() != SIZE:
		return ERR_CANT_CREATE
	# Godot imports a horizontal strip as a Texture3D when its import preset
	# declares one slice per tile. Keeping the source PNG makes this bake
	# deterministic and portable across render backends.
	var strip := Image.create(
		SIZE * SIZE,
		SIZE,
		false,
		images[0].get_format()
	)
	for slice_index in SIZE:
		strip.blit_rect(
			images[slice_index],
			Rect2i(0, 0, SIZE, SIZE),
			Vector2i(slice_index * SIZE, 0)
		)
	return strip.save_png(path)

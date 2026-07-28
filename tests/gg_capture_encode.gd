class_name GGCaptureEncode
extends RefCounted
## With hdr_2d enabled, Viewport.get_texture().get_image() returns the LINEAR
## 2D buffer; the display blit applies the sRGB encode on the way to screen.
## Capture tools must apply that same encode so saved PNGs match what the
## player sees. Godot 4.6 Image has no linear_to_srgb(), so use a LUT.


static func encode_srgb(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	var lut := PackedByteArray()
	lut.resize(256)
	for i in 256:
		var linear := i / 255.0
		var encoded := (
			12.92 * linear if linear <= 0.0031308
			else 1.055 * pow(linear, 1.0 / 2.4) - 0.055
		)
		lut[i] = clampi(roundi(encoded * 255.0), 0, 255)
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		data[i] = lut[data[i]]
		data[i + 1] = lut[data[i + 1]]
		data[i + 2] = lut[data[i + 2]]
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)

extends RefCounted
# legacy-disabled class_name SumaPixelArt

# Runtime-authored pixel art keeps the prototype self-contained while ensuring every
# world sprite uses the same small palette, hard one-pixel edges, and nearest filtering.

const CLEAR := Color(0, 0, 0, 0)
const OUTLINE := Color("#172b24")
const DEEP := Color("#24452f")
const LEAF_DARK := Color("#2f6438")
const LEAF := Color("#4f8a43")
const LEAF_LIGHT := Color("#83b84c")
const MOSS := Color("#9fc958")
const BARK_DARK := Color("#4c3025")
const BARK := Color("#765036")
const BARK_LIGHT := Color("#a87543")
const CREAM := Color("#f3e9c8")
const GOLD := Color("#f0c45c")
const WATER := Color("#559a91")
const WATER_LIGHT := Color("#87c7ad")
const STONE_DARK := Color("#59645e")
const STONE := Color("#899388")
const STONE_LIGHT := Color("#bbc4ad")
const BERRY := Color("#d96b69")
const PURPLE := Color("#a178b4")

static var _textures: Dictionary = {}


static func prop_texture(kind: StringName) -> ImageTexture:
	var key := "prop:%s" % String(kind)
	if _textures.has(key):
		return _textures[key]
	var image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	match String(kind):
		"sapling":
			_tree(image)
		"berry_bush":
			_bush(image, true)
		"moonflowers":
			_flowers(image)
		"moss_rock":
			_rock(image)
		"root_bench":
			_bench(image)
		"glow_lantern", "wish_lantern":
			_lantern(image, String(kind) == "wish_lantern")
		"twig_fence":
			_fence(image)
		"seed_crate":
			_crate(image)
		"old_stump":
			_stump(image)
		"mushroom_ring":
			_mushrooms(image)
		"way_sign":
			_sign(image)
		"root_arch":
			_arch(image)
		"tea_table":
			_table(image)
		"stone_planter":
			_planter(image)
		"still_bell":
			_bell(image)
		_:
			_bush(image, false)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func character_texture(appearance: Dictionary, step := 0) -> ImageTexture:
	var skin_index := clampi(int(appearance.get("skin", 1)), 0, 3)
	var hair_index := clampi(int(appearance.get("hair", 0)), 0, 3)
	var outfit_index := clampi(int(appearance.get("outfit", 0)), 0, 3)
	var key := "hero:%d:%d:%d:%d" % [skin_index, hair_index, outfit_index, posmod(step, 2)]
	if _textures.has(key):
		return _textures[key]
	var skins := [Color("#f3d1ad"), Color("#dba475"), Color("#a96f4f"), Color("#6f4638")]
	var hairs := [Color("#573a2d"), Color("#d1843e"), Color("#496146"), Color("#6e507b")]
	var outfits := [Color("#4f8a43"), Color("#568d9a"), Color("#bd6c50"), Color("#8874a6")]
	var image := Image.create(24, 32, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	var skin: Color = skins[skin_index]
	var hair: Color = hairs[hair_index]
	var outfit: Color = outfits[outfit_index]
	var foot_shift := posmod(step, 2)
	_rect(image, Rect2i(8 - foot_shift, 27, 4, 3), OUTLINE)
	_rect(image, Rect2i(13 + foot_shift, 27, 4, 3), OUTLINE)
	_rect(image, Rect2i(7, 18, 10, 10), OUTLINE)
	_rect(image, Rect2i(8, 18, 8, 9), outfit)
	_rect(image, Rect2i(6, 19, 2, 7), OUTLINE)
	_rect(image, Rect2i(17, 19, 2, 7), OUTLINE)
	_rect(image, Rect2i(6, 20, 2, 5), outfit.darkened(0.12))
	_rect(image, Rect2i(17, 20, 2, 5), outfit.darkened(0.12))
	_rect(image, Rect2i(8, 8, 9, 11), OUTLINE)
	_rect(image, Rect2i(9, 9, 7, 9), skin)
	_rect(image, Rect2i(8, 7, 9, 5), OUTLINE)
	_rect(image, Rect2i(9, 7, 8, 4), hair)
	_rect(image, Rect2i(7, 10, 2, 5), hair)
	_rect(image, Rect2i(16, 10, 2, 4), hair.darkened(0.1))
	_rect(image, Rect2i(10, 13, 2, 2), OUTLINE)
	_rect(image, Rect2i(14, 13, 2, 2), OUTLINE)
	_put_pixel(image, 10, 13, CREAM)
	_put_pixel(image, 14, 13, CREAM)
	_rect(image, Rect2i(11, 16, 4, 1), skin.darkened(0.18))
	_rect(image, Rect2i(9, 20, 6, 2), outfit.lightened(0.15))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func wisp_texture(variant: int, carrying := true) -> ImageTexture:
	var key := "wisp:%d:%d" % [posmod(variant, 3), int(carrying)]
	if _textures.has(key):
		return _textures[key]
	var image := Image.create(24, 28, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	var bodies := [Color("#c5e780"), Color("#80cfad"), Color("#e5a7d0")]
	var body: Color = bodies[posmod(variant, bodies.size())]
	_circle(image, Vector2i(12, 15), 7, OUTLINE)
	_circle(image, Vector2i(12, 14), 6, body)
	_rect(image, Rect2i(6, 8, 12, 5), OUTLINE)
	_rect(image, Rect2i(7, 8, 10, 4), body.darkened(0.15))
	_put_pixel(image, 9, 14, OUTLINE)
	_put_pixel(image, 15, 14, OUTLINE)
	_put_pixel(image, 9, 13, CREAM)
	_put_pixel(image, 15, 13, CREAM)
	_rect(image, Rect2i(8, 20, 3, 2), OUTLINE)
	_rect(image, Rect2i(14, 20, 3, 2), OUTLINE)
	if carrying:
		_circle(image, Vector2i(18, 6), 4, OUTLINE)
		_circle(image, Vector2i(18, 6), 3, GOLD)
		_put_pixel(image, 18, 5, Color("#fff3a3"))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func light_texture() -> ImageTexture:
	if _textures.has("forest_light"):
		return _textures["forest_light"]
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	_put_pixel(image, 5, 0, Color("#fff3a3"))
	_put_pixel(image, 6, 0, Color("#fff3a3"))
	_put_pixel(image, 5, 11, GOLD)
	_put_pixel(image, 6, 11, GOLD)
	_put_pixel(image, 0, 5, GOLD)
	_put_pixel(image, 0, 6, GOLD)
	_put_pixel(image, 11, 5, GOLD)
	_put_pixel(image, 11, 6, GOLD)
	_circle(image, Vector2i(6, 6), 5, OUTLINE)
	_circle(image, Vector2i(6, 6), 4, GOLD)
	_circle(image, Vector2i(5, 5), 2, Color("#fff3a3"))
	var texture := ImageTexture.create_from_image(image)
	_textures["forest_light"] = texture
	return texture


static func forest_tree_texture(variant: int) -> ImageTexture:
	var key := "forest_tree:%d" % posmod(variant, 4)
	if _textures.has(key):
		return _textures[key]
	var image := Image.create(40, 64, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	var offset := posmod(variant * 3, 7) - 3
	_rect(image, Rect2i(17 + offset / 2, 39, 7, 22), OUTLINE)
	_rect(image, Rect2i(18 + offset / 2, 39, 5, 21), BARK)
	_rect(image, Rect2i(19 + offset / 2, 40, 2, 20), BARK_LIGHT)
	_cluster(image, Vector2i(20 + offset, 20), 14, LEAF_DARK, LEAF)
	_cluster(image, Vector2i(12 + offset / 2, 29), 10, LEAF_DARK, LEAF_LIGHT)
	_cluster(image, Vector2i(29 + offset / 2, 31), 11, LEAF_DARK, LEAF)
	_cluster(image, Vector2i(21, 10), 10, LEAF_DARK, MOSS)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func tile_texture(kind: StringName, coord := Vector2i.ZERO) -> ImageTexture:
	var variant := posmod(coord.x * 17 + coord.y * 31, 4)
	var key := "tile:%s:%d" % [String(kind), variant]
	if _textures.has(key):
		return _textures[key]
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var base := LEAF_DARK
	match String(kind):
		"ground_loam":
			base = BARK
		"ground_stone":
			base = STONE
		"ground_water":
			base = WATER
		_:
			base = LEAF
	image.fill(base)
	for y: int in 16:
		for x: int in 16:
			var noise := posmod(x * 13 + y * 7 + variant * 19 + x * y, 23)
			var color := base
			if String(kind) == "ground_water":
				if noise in [1, 2, 3]:
					color = WATER_LIGHT
				elif noise == 9:
					color = DEEP
			elif String(kind) == "ground_stone":
				if noise in [2, 3]:
					color = STONE_LIGHT
				elif noise == 11:
					color = STONE_DARK
			elif String(kind) == "ground_loam":
				if noise in [1, 2, 3]:
					color = BARK_LIGHT
				elif noise == 12:
					color = BARK_DARK
			else:
				if noise in [1, 2, 3, 4]:
					color = LEAF_LIGHT
				elif noise == 12:
					color = DEEP
			image.set_pixel(x, y, color)
	if String(kind) == "ground_grass":
		_put_pixel(image, 3 + variant, 4, MOSS)
		_put_pixel(image, 4 + variant, 3, MOSS)
		_put_pixel(image, 11 - variant, 12, LEAF_LIGHT)
	elif String(kind) == "ground_loam":
		for x: int in range(1, 16, 4):
			_rect(image, Rect2i(x, 0, 1, 16), BARK_DARK)
	elif String(kind) == "ground_stone":
		_line(image, Vector2i(1, 5), Vector2i(8, 6), STONE_DARK)
		_line(image, Vector2i(8, 6), Vector2i(11, 12), STONE_DARK)
	elif String(kind) == "ground_water":
		_line(image, Vector2i(2, 4), Vector2i(8, 4), WATER_LIGHT)
		_line(image, Vector2i(7, 11), Vector2i(14, 11), WATER_LIGHT)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func _tree(image: Image) -> void:
	_rect(image, Rect2i(14, 27, 5, 18), OUTLINE)
	_rect(image, Rect2i(15, 27, 3, 17), BARK)
	_cluster(image, Vector2i(16, 15), 11, LEAF_DARK, LEAF)
	_cluster(image, Vector2i(9, 23), 8, LEAF_DARK, LEAF_LIGHT)
	_cluster(image, Vector2i(23, 23), 8, LEAF_DARK, MOSS)


static func _bush(image: Image, berries: bool) -> void:
	_cluster(image, Vector2i(16, 31), 11, LEAF_DARK, LEAF)
	_cluster(image, Vector2i(9, 35), 7, LEAF_DARK, LEAF_LIGHT)
	_cluster(image, Vector2i(24, 35), 7, LEAF_DARK, MOSS)
	if berries:
		for point: Vector2i in [Vector2i(10, 29), Vector2i(18, 26), Vector2i(23, 34), Vector2i(15, 38)]:
			_circle(image, point, 2, OUTLINE)
			_put_pixel(image, point.x, point.y, BERRY)


static func _flowers(image: Image) -> void:
	for x: int in [9, 16, 23]:
		_line(image, Vector2i(x, 43), Vector2i(x, 28 + posmod(x, 3)), LEAF_DARK)
		_circle(image, Vector2i(x, 27 + posmod(x, 3)), 4, OUTLINE)
		_circle(image, Vector2i(x, 27 + posmod(x, 3)), 3, BERRY if x != 16 else PURPLE)
		_put_pixel(image, x, 27 + posmod(x, 3), GOLD)


static func _rock(image: Image) -> void:
	_rect(image, Rect2i(7, 30, 19, 13), OUTLINE)
	_rect(image, Rect2i(9, 27, 14, 16), OUTLINE)
	_rect(image, Rect2i(10, 29, 13, 12), STONE)
	_rect(image, Rect2i(12, 28, 8, 4), STONE_LIGHT)
	_rect(image, Rect2i(10, 29, 5, 3), MOSS)


static func _bench(image: Image) -> void:
	_rect(image, Rect2i(4, 21, 24, 5), OUTLINE)
	_rect(image, Rect2i(5, 22, 22, 3), BARK_LIGHT)
	_rect(image, Rect2i(5, 29, 23, 5), OUTLINE)
	_rect(image, Rect2i(6, 30, 21, 3), BARK)
	_rect(image, Rect2i(7, 34, 4, 10), OUTLINE)
	_rect(image, Rect2i(22, 34, 4, 10), OUTLINE)
	_rect(image, Rect2i(8, 34, 2, 9), BARK_DARK)
	_rect(image, Rect2i(23, 34, 2, 9), BARK_DARK)


static func _lantern(image: Image, magical: bool) -> void:
	_rect(image, Rect2i(9, 17, 14, 25), OUTLINE)
	_rect(image, Rect2i(11, 20, 10, 17), GOLD)
	_rect(image, Rect2i(13, 22, 6, 12), Color("#fff1a1"))
	_rect(image, Rect2i(8, 15, 16, 4), OUTLINE)
	_rect(image, Rect2i(11, 11, 10, 4), OUTLINE)
	if magical:
		for point: Vector2i in [Vector2i(5, 20), Vector2i(27, 14), Vector2i(26, 30)]:
			_put_pixel(image, point.x, point.y, Color("#fff1a1"))
			_put_pixel(image, point.x + 1, point.y, GOLD)


static func _fence(image: Image) -> void:
	for x: int in [6, 25]:
		_rect(image, Rect2i(x, 16, 4, 28), OUTLINE)
		_rect(image, Rect2i(x + 1, 18, 2, 25), BARK)
	for y: int in [25, 35]:
		_rect(image, Rect2i(5, y, 23, 5), OUTLINE)
		_rect(image, Rect2i(6, y + 1, 21, 3), BARK_LIGHT)


static func _crate(image: Image) -> void:
	_rect(image, Rect2i(6, 21, 21, 22), OUTLINE)
	_rect(image, Rect2i(8, 23, 17, 18), BARK_LIGHT)
	_rect(image, Rect2i(8, 28, 17, 3), BARK_DARK)
	_line(image, Vector2i(9, 24), Vector2i(23, 39), BARK_DARK)
	_line(image, Vector2i(23, 24), Vector2i(9, 39), BARK_DARK)


static func _stump(image: Image) -> void:
	_rect(image, Rect2i(9, 24, 15, 19), OUTLINE)
	_rect(image, Rect2i(11, 25, 11, 17), BARK)
	_rect(image, Rect2i(8, 22, 17, 7), OUTLINE)
	_rect(image, Rect2i(10, 23, 13, 4), BARK_LIGHT)
	_rect(image, Rect2i(4, 40, 9, 4), OUTLINE)
	_rect(image, Rect2i(21, 40, 8, 4), OUTLINE)


static func _mushrooms(image: Image) -> void:
	for row: Array in [[8, 34, BERRY], [16, 27, PURPLE], [24, 36, BERRY], [14, 40, GOLD]]:
		var x := int(row[0])
		var y := int(row[1])
		_rect(image, Rect2i(x - 1, y, 3, 7), CREAM)
		_rect(image, Rect2i(x - 4, y - 3, 9, 4), OUTLINE)
		_rect(image, Rect2i(x - 3, y - 2, 7, 2), row[2])


static func _sign(image: Image) -> void:
	_rect(image, Rect2i(14, 23, 5, 22), OUTLINE)
	_rect(image, Rect2i(15, 24, 3, 21), BARK_DARK)
	_rect(image, Rect2i(4, 16, 25, 13), OUTLINE)
	_rect(image, Rect2i(6, 18, 21, 9), BARK_LIGHT)
	_rect(image, Rect2i(11, 21, 10, 2), CREAM)


static func _arch(image: Image) -> void:
	_rect(image, Rect2i(4, 15, 5, 30), OUTLINE)
	_rect(image, Rect2i(24, 15, 5, 30), OUTLINE)
	_rect(image, Rect2i(6, 17, 2, 27), BARK)
	_rect(image, Rect2i(25, 17, 2, 27), BARK)
	_rect(image, Rect2i(7, 10, 20, 7), OUTLINE)
	_rect(image, Rect2i(9, 11, 16, 5), BARK)
	for p: Vector2i in [Vector2i(7, 12), Vector2i(13, 9), Vector2i(20, 10), Vector2i(27, 13)]:
		_circle(image, p, 4, LEAF_DARK)
		_circle(image, p, 2, LEAF_LIGHT)


static func _table(image: Image) -> void:
	_rect(image, Rect2i(5, 23, 23, 8), OUTLINE)
	_rect(image, Rect2i(7, 24, 19, 5), BARK_LIGHT)
	_rect(image, Rect2i(14, 30, 5, 15), OUTLINE)
	_rect(image, Rect2i(15, 31, 3, 13), BARK_DARK)
	_rect(image, Rect2i(18, 19, 7, 7), OUTLINE)
	_rect(image, Rect2i(19, 20, 5, 5), WATER_LIGHT)


static func _planter(image: Image) -> void:
	_rect(image, Rect2i(7, 29, 19, 14), OUTLINE)
	_rect(image, Rect2i(9, 31, 15, 10), STONE)
	_rect(image, Rect2i(5, 26, 23, 6), OUTLINE)
	_rect(image, Rect2i(8, 27, 17, 3), STONE_LIGHT)
	for p: Vector2i in [Vector2i(11, 23), Vector2i(16, 18), Vector2i(21, 22)]:
		_cluster(image, p, 5, LEAF_DARK, LEAF_LIGHT)


static func _bell(image: Image) -> void:
	_rect(image, Rect2i(5, 40, 22, 5), OUTLINE)
	_rect(image, Rect2i(7, 41, 18, 3), STONE_DARK)
	_rect(image, Rect2i(7, 13, 4, 29), OUTLINE)
	_rect(image, Rect2i(8, 15, 2, 25), BARK)
	_rect(image, Rect2i(8, 12, 18, 4), OUTLINE)
	_rect(image, Rect2i(18, 15, 9, 13), OUTLINE)
	_rect(image, Rect2i(20, 17, 5, 9), GOLD)
	_rect(image, Rect2i(21, 27, 3, 4), OUTLINE)


static func _cluster(image: Image, center: Vector2i, radius: int, dark: Color, light: Color) -> void:
	_circle(image, center, radius, OUTLINE)
	_circle(image, center, radius - 2, dark)
	_circle(image, center + Vector2i(-radius / 3, -radius / 3), maxi(2, radius / 2), light)
	_rect(image, Rect2i(center.x + radius / 4, center.y + radius / 4, 3, 3), dark.darkened(0.12))


static func _rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y: int in range(maxi(0, rect.position.y), mini(image.get_height(), rect.end.y)):
		for x: int in range(maxi(0, rect.position.x), mini(image.get_width(), rect.end.x)):
			image.set_pixel(x, y, color)


static func _circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			if Vector2(x - center.x, y - center.y).length_squared() <= radius * radius:
				_put_pixel(image, x, y, color)


static func _line(image: Image, from: Vector2i, to: Vector2i, color: Color) -> void:
	var points := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i: int in range(points + 1):
		var t := float(i) / maxf(1.0, float(points))
		_put_pixel(image, roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t)), color)


static func _put_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
		image.set_pixel(x, y, color)

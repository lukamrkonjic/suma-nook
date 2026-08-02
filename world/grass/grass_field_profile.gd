@tool
class_name GrassFieldProfile
extends Resource
## Every number the grass generators are allowed to know.
##
## The field is built by several cooperating passes — chunk surface, dense
## micro-tuft carpet, sparse flexible tufts, wind, LOD. When each pass owns its
## own constants they drift apart, and the moment two passes disagree about the
## cell size or the tone ramp the logical grid reappears on screen: the surface
## swells at one frequency, the carpet thins at another, and the eye reads the
## mismatch as a square. So the generators hard-code NOTHING. They read this
## resource, and a designer retunes the whole field by editing one .tres.
##
## Everything here is expressed in WORLD units and world-space frequencies, for
## the same reason tools/tile_forge/grass/grass_field.gd evaluates its fields in
## world space: two chunks agree because they sampled the same function at the
## same coordinate, not because someone stitched their edges afterwards.

## Suma's logical cell is 1.35 m (data/tuning.json::tile_size), but the grass
## catalog under tools/tile_forge/modules/grass was authored against a 1.70 m
## footprint. Any LINEAR figure quoted in catalog space must therefore be
## multiplied by 1.35 / 1.70 = 0.794 before it is used in the world — see
## catalog_scale(). Areal figures (instances per square metre) are already
## cell-size independent and must NOT be scaled.
const CATALOG_TILE_SIZE := 1.70

## Tone noise is offset from the height seed by a prime rather than by 1, so the
## two fields decorrelate completely. Sharing a seed makes every rise the same
## colour as every other rise, which reads as a repeating stamp.
const TONE_SEED_OFFSET := 7919
## Same reasoning as TONE_SEED_OFFSET: a third prime keeps density independent
## of both height and colour, so a thin patch does not always sit on a rise or
## always share an edge with a colour change.
const DENSITY_SEED_OFFSET := 15485


@export_group("Grid")
## Matches data/tuning.json::tile_size. The grid stays purely logical: it decides
## which cells are grass and nothing else about what is drawn.
@export var tile_size := 1.35
## Cells per render chunk. Chunks are the culling and rebuild unit, so they stay
## small enough to cull usefully and large enough that internal cell boundaries
## are simply interior vertices with nothing to reveal them.
@export var chunk_size_in_tiles := 4
## Surface samples per cell edge. Eight gives ~0.17 m spacing at 1.35 m cells:
## fine enough for broad swells, coarse enough to stay cheap.
@export var surface_segments_per_tile := 8

@export_group("Surface Form")
## Peak-to-trough sculpting of the ground, in metres. Deliberately gentle — the
## target is soft rolling terrain, and anything past ~0.12 m starts to read as
## lumps sitting inside individual cells instead of swells crossing many.
## Raised from 0.085 after the first render came back visually dead flat. The
## brief's own suggested figures (±0.035 m typical) were written against a 1.70 m
## cell; at Suma's 1.35 m cell and a 15° gameplay lens that much relief is below
## the threshold where shading reads it at all, and "soft rolling macro terrain"
## simply did not happen. This is still gentle — a ~2% grade — and stays
## buildable.
@export var surface_height_amplitude := 0.19
## World-space frequency of the height field. Lowered to match: a period of
## ~17 m spans twelve cells, so a swell is unmistakably landscape rather than
## anything that could be read as a tile.
@export var surface_noise_frequency := 0.058
## Tone varies faster than height so colour drift and terrain shape do not share
## a silhouette, but still far slower than a cell.
@export var surface_tone_noise_frequency := 0.105

@export_group("Density")
## Dense leaf clumps: the carpet itself. This has to be high enough that clump
## footprints OVERLAP — leaves from one clump lying across the next is what
## closes the field into a continuous mass. The first attempt ran at 68/m² with
## small footprints, giving roughly 18% coverage, and read exactly as what it
## was: countable specks on a green plane. Overlap is not a polish detail here,
## it is the difference between a carpet and a scatter.
@export_range(40.0, 220.0, 1.0) var dense_instances_per_square_metre := 105.0
## Taller flexible clumps over the carpet. Sparse by design — they are the
## motion and the broken silhouette, not the coverage.
@export_range(4.0, 40.0, 0.5) var flexible_instances_per_square_metre := 12.0
## Jitter applied to each placement lattice cell, 0 = a visible grid, 1 = full
## cell. Kept just under 1 so instances stay inside their own lattice cell and
## cannot clump into accidental voids.
@export_range(0.0, 1.0, 0.01) var placement_jitter := 0.92
## Broad world-space swing in density, as a fraction. The field must breathe —
## a perfectly even carpet reads as artificial turf — but this stays small
## because density that drops far enough to bare the ground reintroduces the
## patchiness the whole rework exists to remove.
@export_range(0.0, 0.4, 0.01) var density_variation := 0.15
## Frequency of that density field. Slower than tone, so a thin region spans
## several metres and never lines up with a cell.
@export var density_noise_frequency := 0.085

@export_group("Placement")
## How far each tuft is pushed into the ground, in metres. Non-zero so the
## authored base ring is buried and no instance shows a floating rim; small
## enough that the cushion is not swallowed.
@export var dense_sink_min := 0.004
@export var dense_sink_max := 0.011
@export var flexible_sink_min := 0.006
@export var flexible_sink_max := 0.014
## Uniform scale band per instance. Wide on purpose: the clumps are authored at
## three sizes already, and spreading each of those across a further ±35% is
## what stops the eye finding a repeated silhouette in a field of thousands.
## Centred near 1.0 because the meshes are authored at final world size.
@export var dense_scale_min := 0.70
@export var dense_scale_max := 1.35
@export var flexible_scale_min := 0.75
@export var flexible_scale_max := 1.30
## INSTANCE_CUSTOM.g — how much of the shader's wind each instance takes. The
## dense carpet is deliberately near-inert: it is the ground, and ground that
## sways destroys the illusion faster than still grass ever could.
@export var dense_wind_amount_min := 0.05
@export var dense_wind_amount_max := 0.30
@export var flexible_wind_amount_min := 0.50
@export var flexible_wind_amount_max := 1.0

@export_group("Exposed Edge")
## Only ever generated where the region actually meets the void — never between
## two grass cells, which is what would draw the grid back on.
@export var skirt_height := 0.22
## Chamfer at the exposed rim. The top edge still lands exactly on the boundary;
## the wall below is inset by this much, so the rim catches light without the
## surface stopping short and leaving a sliver.
@export var skirt_bevel := 0.042
## Side darkening relative to the surface colour directly above it.
@export_range(0.0, 0.5, 0.01) var skirt_darken := 0.12

@export_group("Detail States")
## Fraction of each layer kept at MID range. Applied through MultiMesh
## visible_instance_count, so dropping detail costs no rebuild and no allocation
## — and because placements are stored in hash-shuffled order, the survivors are
## a spatially uniform subset rather than a shrinking corner of the chunk.
@export_range(0.0, 1.0, 0.01) var mid_dense_fraction := 0.55
@export_range(0.0, 1.0, 0.01) var mid_flexible_fraction := 0.35

@export_group("Meshes")
## Low rounded moss cushions / plush nubs. NOT vertical blades and NOT leaf
## rosettes — the carpet must read as one continuous surface at grazing angles.
@export var micro_tuft_meshes: Array[String] = [
	"res://world/grass/meshes/grass_leaf_small.glb",
	"res://world/grass/meshes/grass_leaf_medium.glb",
	"res://world/grass/meshes/grass_leaf_large.glb",
]
## The taller pieces the wind shader actually animates.
@export var flexible_tuft_meshes: Array[String] = [
	"res://world/grass/meshes/grass_leaf_tall.glb",
	"res://world/grass/meshes/grass_leaf_accent.glb",
]

@export_group("Surface Colour")
## Three closely related greens — at most ~9% apart in value — so the ground has
## rhythm without any one blob reading as a patch of different material.
@export var surface_deep := PaletteDefinition.shared().color(
	"grass_field_surface_deep"
)
@export var surface_primary := PaletteDefinition.shared().color(
	"grass_field_surface_primary"
)
@export var surface_light := PaletteDefinition.shared().color(
	"grass_field_surface_light"
)

@export_group("Tuft Colour")
## These resolve from the canonical color design system and are pushed into the
## shader at runtime. Tufts sit a touch cooler and deeper than the surface
## beneath them, which stops the carpet reading as flat paint when they overlap.
## Lightened and pulled closer together after the straw pass came back reading
## as near-black strands over a pale lawn. The brief asks for close green tones;
## foliage that sits far darker than the ground it grows from separates into
## individually countable pieces, which is the opposite of a carpet.
@export var tuft_deep := PaletteDefinition.shared().color(
	"grass_field_tuft_deep"
)
@export var tuft_primary := PaletteDefinition.shared().color(
	"grass_field_tuft_primary"
)
@export var tuft_light := PaletteDefinition.shared().color(
	"grass_field_tuft_light"
)

@export_group("Wind")
## Prevailing direction in world XZ. One direction for the whole field: gusts
## that disagree about which way the weather is blowing destroy the illusion of
## a single living surface faster than any amount of per-instance variation
## builds it.
@export var wind_direction := Vector2(0.82, 0.57)
@export var wind_speed := 0.72
## World-space wavelength scale of the travelling wave. Around 1.1 the crest
## takes several metres to cross, so neighbouring tufts lean together in a
## coordinated ripple instead of shivering independently.
@export var wind_world_scale := 1.10
## Constant breathing amplitude, in metres of lateral displacement. Tiny: these
## are stiff little cushions, not wheat.
@export var wind_strength := 0.004
## Extra amplitude at the peak of a gust, added on top of wind_strength.
@export var gust_strength := 0.010

@export_group("Visibility")
## LOD bands in metres. The bands OVERLAP by 2 m on purpose (near ends at 12,
## mid starts at 10; mid ends at 24, far starts at 22) so a camera drifting
## across a boundary cross-fades instead of popping a whole chunk of carpet in
## and out.
@export var near_visibility_end := 12.0
@export var mid_visibility_begin := 10.0
@export var mid_visibility_end := 24.0
@export var far_visibility_begin := 22.0
## Godot treats a visibility range end of 0.0 as "no limit", which is exactly
## what the far band wants — it is the last one, so it never ends.
@export var far_visibility_end := 0.0

@export_group("Determinism")
## Matches the seed used by tools/tile_forge/grass/field_review.gd so validation
## renders stay comparable across sessions. Every random decision in the field
## derives from this one number.
@export var random_seed := 771


# --- derived geometry --------------------------------------------------------


## Catalog space is 1.70 m; Suma's cell is tile_size. Multiply any linear figure
## quoted against the authored catalog (footprint radii, authored heights, mesh
## scale) by this before placing it in the world. Default 1.35 / 1.70 = 0.794.
func catalog_scale() -> float:
	return tile_size / CATALOG_TILE_SIZE


## Spacing between surface samples, in metres. Also the correct step for the
## finite-difference normal: sampling the height function at exactly this
## distance means a boundary vertex gets an identical normal from either chunk,
## so the join cannot show as a shading line.
func surface_step() -> float:
	return tile_size / float(maxi(surface_segments_per_tile, 1))


## Edge length of one render chunk, in metres.
func chunk_size_in_metres() -> float:
	return tile_size * float(maxi(chunk_size_in_tiles, 1))


## Instances of each layer to place over an area. Density is areal, so it is
## already independent of tile_size and must not be scaled by catalog_scale().
func dense_instance_count(area_in_square_metres: float) -> int:
	return int(round(maxf(area_in_square_metres, 0.0) * dense_instances_per_square_metre))


func flexible_instance_count(area_in_square_metres: float) -> int:
	return int(round(maxf(area_in_square_metres, 0.0) * flexible_instances_per_square_metre))


# --- reproducible fields -----------------------------------------------------


## Height field. Simplex-smooth rather than value noise, and a fractal gain well
## under 0.5, because the higher octaves are here to break the silhouette of the
## broad swells — not to add bumpiness. Bumpiness is what made the earlier
## terrain read as noise sitting on top of tiles rather than as rolling ground.
func create_height_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = random_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = surface_noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.42
	return noise


## Tone field. Two octaves only — colour wants broad soft regions, and a third
## octave starts speckling individual instances. The offset seed keeps tone from
## tracking height (see TONE_SEED_OFFSET).
func create_tone_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = random_seed + TONE_SEED_OFFSET
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = surface_tone_noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.45
	return noise


## Density field. Deliberately the slowest of the three: density controls where
## the carpet thins, and thin regions have to be metres across to read as
## natural clearing rather than as damage.
func create_density_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = random_seed + DENSITY_SEED_OFFSET
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = density_noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.38
	return noise


## Surface colour for a tone value in 0..1, ramped through the middle green so
## the three tones read as one material lit differently rather than as three.
func surface_colour(tone: float) -> Color:
	var t := clampf(tone, 0.0, 1.0)
	if t < 0.5:
		return surface_deep.lerp(surface_primary, t * 2.0)
	return surface_primary.lerp(surface_light, (t - 0.5) * 2.0)


# --- mesh resolution ---------------------------------------------------------


func micro_tuft_mesh_list() -> Array[Mesh]:
	return load_mesh_list(micro_tuft_meshes)


func flexible_tuft_mesh_list() -> Array[Mesh]:
	return load_mesh_list(flexible_tuft_meshes)


## Paths may point at either a Mesh resource or an imported .glb (which Godot
## hands back as a PackedScene). Callers want a Mesh either way, so the digging
## lives here instead of being repeated — and mis-typed in — every generator.
static func load_mesh_list(paths: Array[String]) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	for path in paths:
		var mesh := load_mesh(path)
		if mesh == null:
			push_warning("GrassFieldProfile: no mesh at %s" % path)
			continue
		meshes.append(mesh)
	return meshes


static func load_mesh(path: String) -> Mesh:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource := load(path)
	if resource is Mesh:
		return resource as Mesh
	if resource is PackedScene:
		var root := (resource as PackedScene).instantiate()
		var mesh := _first_mesh(root)
		# The Mesh is reference-counted, so it outlives the scene instance we
		# only ever wanted in order to reach it.
		root.free()
		return mesh
	return null


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null

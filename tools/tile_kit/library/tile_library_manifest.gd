@tool
class_name TileLibraryManifest
extends Resource
## Stable official-content record for one tile.
##
## Recipes answer "what does it look like?". This manifest answers "what is
## it called by the game, where is its source, and may players obtain it?".
## Keeping those contracts separate lets artists reroll or replace geometry
## without changing the id stored in worlds, stock, rewards, or saves.

const SCHEMA_VERSION := 1
const SOURCE_PROCEDURAL := "procedural"
const SOURCE_EXTERNAL := "external"
const LIFECYCLE_DRAFT := "draft"
const LIFECYCLE_PUBLISHED := "published"
const LIFECYCLE_ARCHIVED := "archived"
const VISIBILITY_ACTIVE := "active"
const VISIBILITY_PREVIEW := "preview"
const VISIBILITY_HIDDEN := "hidden"

@export_group("Identity")
@export var schema_version := SCHEMA_VERSION
@export var tile_id := ""
@export var display_name := "Untitled Tile"
@export var revision := 0
@export var lifecycle := LIFECYCLE_DRAFT
@export var visibility := VISIBILITY_HIDDEN

@export_group("Source")
@export var source_kind := SOURCE_PROCEDURAL
@export_file("*.tres") var recipe_path := ""
@export var separate_tiles := false
## External/imported tiles keep their full authored definition here. It remains
## editable and compilable even before their geometry is replaced by Tile Kit.
@export var runtime_definition: Dictionary = {}
@export var baked_roles := PackedStringArray(["base", "surface", "detail"])

@export_group("Catalog")
@export var family := "tile_kit"
@export var connection_group := ""
@export var biome_tags := PackedStringArray([])
@export var rarity := "common"
@export var weight := 1.0
@export var obtainable := true
@export var placement_sound := "grass"
@export_multiline var collection_hint := ""
## Explicit content references not represented in runtime_definition. Hard
## delete treats these as dependencies; archive does not require removing them.
@export var dependencies := PackedStringArray([])
@export var stackable := true
@export var supports_tiles := true
@export var supports_decor := true
@export var walkable := true
@export var surface_kind := "flat"
@export var collision_profile := "flat"
@export var soft_surface_profile := ""
@export var walk_surface_height := 0.0

@export_group("Audit")
@export var created_at := ""
@export var updated_at := ""
@export var published_at := ""
@export_multiline var notes := ""


func duplicate_manifest() -> TileLibraryManifest:
	var copy := duplicate(true) as TileLibraryManifest
	copy.runtime_definition = runtime_definition.duplicate(true)
	copy.biome_tags = biome_tags.duplicate()
	copy.baked_roles = baked_roles.duplicate()
	copy.dependencies = dependencies.duplicate()
	return copy


func is_official() -> bool:
	return lifecycle in [LIFECYCLE_PUBLISHED, LIFECYCLE_ARCHIVED]


func is_editable_recipe() -> bool:
	return source_kind == SOURCE_PROCEDURAL and not recipe_path.is_empty()


func asset_id(role: String) -> String:
	return "%s_%s" % [tile_id, role]


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if tile_id.is_empty():
		errors.append("Tile ID is required.")
	elif not tile_id.begins_with("tile_"):
		errors.append("Tile ID must begin with 'tile_'.")
	elif tile_id != tile_id.to_snake_case() or not tile_id.is_valid_identifier():
		errors.append("Tile ID must contain only lowercase letters, numbers, and underscores.")
	if display_name.strip_edges().is_empty():
		errors.append("Display name is required.")
	if lifecycle not in [LIFECYCLE_DRAFT, LIFECYCLE_PUBLISHED, LIFECYCLE_ARCHIVED]:
		errors.append("Unknown lifecycle '%s'." % lifecycle)
	if visibility not in [VISIBILITY_ACTIVE, VISIBILITY_PREVIEW, VISIBILITY_HIDDEN]:
		errors.append("Unknown visibility '%s'." % visibility)
	if source_kind not in [SOURCE_PROCEDURAL, SOURCE_EXTERNAL]:
		errors.append("Unknown source kind '%s'." % source_kind)
	if source_kind == SOURCE_PROCEDURAL and recipe_path.is_empty():
		errors.append("Procedural tiles require a .tres recipe.")
	if source_kind == SOURCE_EXTERNAL and runtime_definition.is_empty():
		errors.append("External tiles require their runtime definition.")
	if weight < 0.0:
		errors.append("Catalog weight cannot be negative.")
	if walk_surface_height < 0.0 or walk_surface_height > 0.15:
		errors.append("Walk surface height must remain between 0 and 0.15 metres.")
	if is_official() and revision < 1:
		errors.append("Published or archived manifests require revision 1 or newer.")
	return errors


func to_tile_dictionary() -> Dictionary:
	var definition := (
		runtime_definition.duplicate(true)
		if source_kind == SOURCE_EXTERNAL
		else _procedural_definition()
	)
	definition["id"] = tile_id
	definition["name"] = display_name
	definition["family"] = family
	definition["connection_group"] = (
		connection_group if not connection_group.is_empty() else tile_id
	)
	definition["biome_tags"] = Array(biome_tags)
	definition["rarity"] = rarity
	definition["weight"] = weight
	definition["placement_sound"] = placement_sound
	definition["collection_hint"] = collection_hint
	definition["obtainable"] = lifecycle == LIFECYCLE_PUBLISHED and obtainable
	definition["source_manifest"] = resource_path
	definition["source_kind"] = source_kind
	definition["source_revision"] = revision
	return definition


func _procedural_definition() -> Dictionary:
	var layers: Array[Dictionary] = []
	for role in baked_roles:
		var normalized := String(role)
		if normalized not in ["base", "surface", "detail"]:
			continue
		layers.append({
			"role": normalized,
			"asset_id": asset_id(normalized),
			"cover_behavior": "persist" if normalized == "base" else "hide",
		})
	return {
		"id": tile_id,
		"name": display_name,
		"family": family,
		"asset_id": asset_id("surface"),
		"render_profile": "layered",
		"layers": layers,
		"stackable": stackable,
		"supports_tiles": supports_tiles,
		"supports_decor": supports_decor,
		"walkable": walkable,
		"surface_kind": surface_kind,
		"collision_profile": collision_profile,
		"soft_surface_profile": soft_surface_profile,
		"walk_surface_height": walk_surface_height,
		"geometry_profile": "rounded_corner_slab",
		"connection_mode": "tiny_individual_seam" if separate_tiles else "full_flush",
		# Procedural caps may add seed-driven relief above the nominal walk
		# plane. Declaring the authored shell raised gives that visual relief its
		# validated vertical envelope while collision remains the explicit flat
		# walk_surface_height contract.
		"exposed_top": "raised",
	}

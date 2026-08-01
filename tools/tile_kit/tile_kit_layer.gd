@tool
class_name TileKitLayer
extends Resource
## One lego brick of a Tile Kit tile.
##
## A layer is a KIND (which builder runs), a deterministic seed offset, and a
## bag of parameters the builder reads. Tiles are just ordered lists of these,
## so a new tile family — pavers, planks, sand — is a new builder script plus
## presets that stack it with the existing bricks, never a new generator.
##
## `locked` and `enabled` belong to the layer, not the editor: a locked layer
## survives Randomize All untouched, and a disabled layer builds nothing while
## keeping every setting for when it is re-enabled.

## Which builder runs this layer. Must be a key in TileKitGenerator.BUILDERS.
@export var kind := ""
## Deterministic sub-seed. The layer's RNG derives from
## (master_seed, kind, seed_offset), so rerolling one layer means bumping its
## offset — the other layers' streams never notice.
@export var seed_offset := 0
@export var enabled := true
## Locked layers are skipped by every randomize action, including Randomize
## All. The mesh still rebuilds (deterministically identical) when unrelated
## layers change.
@export var locked := false
## Frozen RNG stream, captured at the moment the layer is locked. While this
## is non-zero the layer ignores the master seed entirely, which is what lets
## Randomize All reroll the rest of the tile without this layer moving — and
## what makes the lock survive saving the preset and reopening the editor.
@export var stream_snapshot := 0
## Builder-specific parameters. Builders read with defaults, so presets only
## carry what they deviate on.
@export var params: Dictionary = {}


func _init(layer_kind := "", layer_params: Dictionary = {}) -> void:
	kind = layer_kind
	params = layer_params


func value(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)


func duplicate_layer() -> TileKitLayer:
	var copy := TileKitLayer.new(kind, params.duplicate(true))
	copy.seed_offset = seed_offset
	copy.enabled = enabled
	copy.locked = locked
	copy.stream_snapshot = stream_snapshot
	return copy

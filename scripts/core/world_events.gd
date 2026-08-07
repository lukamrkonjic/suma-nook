class_name WorldEvents
extends RefCounted
## Scoped world-signal hub for the Unfolding World. This is NOT a global
## event bus or autoload: GameCore owns exactly one instance and injects it
## into the systems that need it, keeping wiring explicit and testable.
##
## Discovery systems (treasures, firsts, dormants, keepsakes) are pure
## listeners on these signals. Deleting any listener leaves the game running
## — you just find less.
##
## Every typed signal is mirrored onto `world_signal(name, payload)` so
## data-defined listeners (Firsts, Moments) can subscribe by signal *name*
## from JSON without new code per signal.

signal world_signal(name: String, payload: Dictionary)

signal nook_revealed(coord: Vector2i, payload: Dictionary)
signal nook_connected(coord: Vector2i, other: Vector2i, payload: Dictionary)
signal nook_named(coord: Vector2i, payload: Dictionary)
signal tile_placed(payload: Dictionary)
signal feature_cleared(payload: Dictionary)
signal sapling_planted(payload: Dictionary)
signal sapling_matured(payload: Dictionary)
signal model_placed(payload: Dictionary)
signal model_removed(payload: Dictionary)
signal water_added(payload: Dictionary)
signal path_linked(payload: Dictionary)
signal treasure_found(payload: Dictionary)
signal first_fired(payload: Dictionary)
signal dormant_woken(payload: Dictionary)
signal keepsake_minted(payload: Dictionary)

const TYPED := {
	"nook_revealed": true,
	"nook_connected": true,
	"nook_named": true,
	"tile_placed": true,
	"feature_cleared": true,
	"sapling_planted": true,
	"sapling_matured": true,
	"model_placed": true,
	"model_removed": true,
	"water_added": true,
	"path_linked": true,
	"treasure_found": true,
	"first_fired": true,
	"dormant_woken": true,
	"keepsake_minted": true,
}


## Single emission choke point. Payloads carry `nook` (Vector2i chunk coord)
## whenever the event happened inside a revealed Nook, plus event-specific
## fields; listeners must treat payloads as read-only.
func publish(name: String, payload: Dictionary) -> void:
	match name:
		"nook_revealed":
			nook_revealed.emit(payload.get("nook", Vector2i.ZERO), payload)
		"nook_connected":
			nook_connected.emit(
				payload.get("nook", Vector2i.ZERO),
				payload.get("other", Vector2i.ZERO),
				payload
			)
		"nook_named":
			nook_named.emit(payload.get("nook", Vector2i.ZERO), payload)
		"tile_placed": tile_placed.emit(payload)
		"feature_cleared": feature_cleared.emit(payload)
		"sapling_planted": sapling_planted.emit(payload)
		"sapling_matured": sapling_matured.emit(payload)
		"model_placed": model_placed.emit(payload)
		"model_removed": model_removed.emit(payload)
		"water_added": water_added.emit(payload)
		"path_linked": path_linked.emit(payload)
		"treasure_found": treasure_found.emit(payload)
		"first_fired": first_fired.emit(payload)
		"dormant_woken": dormant_woken.emit(payload)
		"keepsake_minted": keepsake_minted.emit(payload)
	world_signal.emit(name, payload)

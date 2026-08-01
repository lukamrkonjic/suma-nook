@tool
class_name TileSeedUtil
extends RefCounted
## Deterministic seeding. Every random decision in the Tile Forge derives from
## (recipe seed, variant index, a stable string channel), so the same recipe and
## seed always rebuild the identical tile — on any machine, in any order, no
## matter which layers were rebuilt in between.
##
## Never call `randi()`, `randf()`, or an unseeded RandomNumberGenerator inside
## a generator. Always take an RNG from here.

const FNV_OFFSET := 1469598103934665603
const FNV_PRIME := 1099511628211


## Stable 64-bit hash of a string. GDScript's String.hash() is 32-bit and its
## value is not contractually stable across engine versions, so the Forge
## carries its own FNV-1a. Baked manifests record hashes produced by this.
static func hash_string(text: String) -> int:
	var h := FNV_OFFSET
	for byte in text.to_utf8_buffer():
		h ^= byte
		h *= FNV_PRIME
	return h


## Mixes a base seed with a named channel. Two layers asking for "clump" and
## "pebble" never share a stream, so editing one layer cannot shift another.
static func channel_seed(base_seed: int, channel: String, offset := 0) -> int:
	var mixed := base_seed ^ hash_string(channel)
	mixed = mixed * 6364136223846793005 + 1442695040888963407
	mixed ^= (mixed >> 33)
	mixed += offset * 2654435761
	mixed ^= (mixed >> 29)
	return mixed


static func rng_for(base_seed: int, channel: String, offset := 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = channel_seed(base_seed, channel, offset)
	return rng


## Weighted pick that consumes exactly one random draw, so adding a module to
## the end of a set does not reshuffle earlier picks any more than necessary.
static func weighted_index(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return 0
	var roll := rng.randf() * total
	var cursor := 0.0
	for index in weights.size():
		cursor += maxf(0.0, weights[index])
		if roll <= cursor:
			return index
	return weights.size() - 1


## Deterministic low-discrepancy point. Used to spread cluster members without
## the clumped-and-gappy look of pure uniform randomness.
static func halton(index: int, base: int) -> float:
	var result := 0.0
	var fraction := 1.0
	var i := index + 1
	while i > 0:
		fraction /= float(base)
		result += fraction * float(i % base)
		i = i / base
	return result


## Value noise in [-1, 1], sampled from a hash rather than a texture. This is
## only ever used for *sub-centimetre* softening of an already-authored macro
## form. It is never the primary shape source — see docs/README_TILE_FORGE.md.
static func value_noise_2d(seed_value: int, x: float, y: float) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var xf := x - float(xi)
	var yf := y - float(yi)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := _lattice(seed_value, xi, yi)
	var b := _lattice(seed_value, xi + 1, yi)
	var c := _lattice(seed_value, xi, yi + 1)
	var d := _lattice(seed_value, xi + 1, yi + 1)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


static func _lattice(seed_value: int, x: int, y: int) -> float:
	var h := seed_value ^ (x * 374761393) ^ (y * 668265263)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 32767.5 - 1.0

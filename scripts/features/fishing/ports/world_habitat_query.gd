class_name WorldHabitatQuery
extends RefCounted
## Narrow contract: given the land cell the keeper fishes from, return an
## immutable broad-theme sample of the surrounding built environment. The
## domain never touches the grid, the scene tree, or renderer state.


func sample(_anchor: Vector2i) -> FishingHabitatSample:
	return FishingHabitatSample.new()

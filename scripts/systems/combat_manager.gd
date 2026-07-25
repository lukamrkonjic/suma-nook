class_name CombatManager
extends RefCounted
## Player health and combat resolution. Enemy movement/AI is scene-side
## (enemy.gd); every health mutation and reward routes through here so the
## rules stay in one testable place. Defeat is gentle: return home, heal,
## enemies reset; nothing is lost.

signal health_changed(current: int, maximum: int)
signal player_defeated
signal enemy_hit(slot_id: String, remaining: int)
signal enemy_defeated(slot_id: String, grants: Array)

var registries: Registries
var landmarks: LandmarkManager
var reward_manager: RewardManager
var equipment: EquipmentManager
var collection: CollectionManager

var max_health: int = 5
var health: int = 5
var _regen_accum := 0.0
# Runtime enemy health per landmark slot: "landmark_id|slot_id" -> hp left.
var _enemy_health: Dictionary = {}


func _init(regs: Registries, landmark_mgr: LandmarkManager, rewards: RewardManager, equip: EquipmentManager, coll: CollectionManager) -> void:
	registries = regs
	landmarks = landmark_mgr
	reward_manager = rewards
	equipment = equip
	collection = coll
	max_health = regs.tunei("player_max_health", 5)
	health = max_health


func attack_damage() -> int:
	return 1 + int(equipment.stat_total("damage"))


func defense() -> int:
	return int(equipment.stat_total("defense"))


func enemy_max_health(enemy_id: String) -> int:
	var def := registries.enemy(enemy_id)
	return def.max_health if def else 1


func enemy_health(landmark_id: String, slot_id: String) -> int:
	var key := "%s|%s" % [landmark_id, slot_id]
	if not _enemy_health.has(key):
		_enemy_health[key] = enemy_max_health(slot_id.get_slice(":", 0))
	return _enemy_health[key]


## Player hits an enemy. Returns remaining hp (<=0 means defeated).
func damage_enemy(landmark_id: String, slot_id: String, is_guardian: bool) -> int:
	var key := "%s|%s" % [landmark_id, slot_id]
	var remaining := enemy_health(landmark_id, slot_id) - attack_damage()
	_enemy_health[key] = remaining
	var enemy_id := slot_id.get_slice(":", 0)
	if remaining <= 0:
		_enemy_health.erase(key)
		collection.record("creatures", enemy_id)
		var state := landmarks.state_for(landmark_id)
		var grants: Array = []
		if state != null:
			grants = landmarks.on_enemy_defeated(state, slot_id, is_guardian)
			if not is_guardian:
				var def := registries.enemy(enemy_id)
				if def != null and def.loot_table != "":
					grants += reward_manager.roll_table(def.loot_table, "combat_loot")
		enemy_defeated.emit(slot_id, grants)
	else:
		enemy_hit.emit(slot_id, remaining)
	return remaining


## Enemy hits the player. Defense soaks single points on alternating hits is
## overkill for MVP — flat reduction with a 1 minimum keeps it readable.
func damage_player(amount: int) -> void:
	var reduced := maxi(1, amount - (1 if defense() >= 2 else 0))
	health = maxi(0, health - reduced)
	health_changed.emit(health, max_health)
	if health == 0:
		health = max_health
		_reset_encounters()
		health_changed.emit(health, max_health)
		player_defeated.emit()


func heal_full() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func tick(delta: float) -> void:
	if health >= max_health:
		_regen_accum = 0.0
		return
	_regen_accum += delta
	var per_point := registries.tunef("health_regen_seconds_per_point", 6.0)
	if _regen_accum >= per_point:
		_regen_accum -= per_point
		health = mini(max_health, health + 1)
		health_changed.emit(health, max_health)


## On defeat, in-progress encounter hp resets (defeated enemies STAY defeated —
## no respawn during the same claim; only wounded ones recover).
func _reset_encounters() -> void:
	_enemy_health.clear()


func to_save_dict() -> Dictionary:
	return {"health": health, "enemy_health": _enemy_health.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	health = clampi(int(data.get("health", max_health)), 1, max_health)
	_enemy_health = data.get("enemy_health", {}).duplicate()
	health_changed.emit(health, max_health)

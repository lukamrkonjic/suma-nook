class_name SdfCreatureVisitorPresenter
extends Node3D
## Initial visitor look only. It consumes a generic presentation definition and
## knows nothing about cadence, reward pools, stock, onboarding, or saves.

signal departure_finished(event_id: int)

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

var event_id := 0
var world_cell := Vector2i.ZERO
var _creature: Node3D
var _shine: MeshInstance3D
var _departing := false
var _motion_state


func setup(
	event: Dictionary,
	presentation: Defs.VisitorPresentationDefinition
) -> void:
	event_id = int(event.get("event_id", 0))
	var raw_cell: Array = event.get("cell", [0, 0])
	world_cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	add_to_group("world_visitors")
	set_meta("visitor_event_id", event_id)
	set_meta("visitor_cell", world_cell)
	_creature = ProceduralCreatureScript.new() as Node3D
	_creature.name = "VisitorCreature"
	add_child(_creature)
	_creature.call("build_from_path", presentation.presentation_resource)
	_creature.scale = Vector3.ONE * presentation.scale
	_motion_state = ProceduralCreatureScript.MotionState.new()
	_build_shine(presentation.shine_color)
	var appear := create_tween()
	scale = Vector3.ONE * 0.15
	appear.tween_property(self, "scale", Vector3.ONE, 0.48).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _departing or _creature == null:
		return
	_creature.call("advance", delta, _motion_state)
	rotation.y += sin(Time.get_ticks_msec() * 0.0013 + event_id) * delta * 0.035


func begin_departure() -> bool:
	if _departing:
		return false
	_departing = true
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + 0.26, 0.42).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.42).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_IN)
	if _shine != null:
		tween.tween_property(_shine, "transparency", 1.0, 0.32)
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		tween.tween_property(mesh_instance, "transparency", 1.0, 0.38)
	tween.chain().tween_callback(func(): departure_finished.emit(event_id))
	return true


func _build_shine(color: Color) -> void:
	_shine = MeshInstance3D.new()
	_shine.name = "VisitorShine"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.012
	disc.radial_segments = 32
	_shine.mesh = disc
	_shine.position.y = 0.018
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	color.a = 0.3
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 0.65
	_shine.material_override = material
	add_child(_shine)
	var pulse := _shine.create_tween().set_loops()
	pulse.tween_property(_shine, "scale", Vector3.ONE * 1.13, 1.35).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_shine, "scale", Vector3.ONE * 0.96, 1.35).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)

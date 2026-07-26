extends Node3D
## Throwaway: try several shadow configurations, capture each.

var sun: DirectionalLight3D
var cam: Camera3D
var idx := 0
var variants := []

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.91, 0.89, 0.81)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.82, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)

	var std_mat := StandardMaterial3D.new()
	std_mat.albedo_color = Color(0.72, 0.7, 0.15)
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(6, 0.2, 6)
	ground.mesh = plane
	ground.position = Vector3(0, -0.1, 0)
	ground.material_override = std_mat
	add_child(ground)
	var caster := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 1.6, 0.4)
	caster.mesh = box
	caster.position = Vector3(0, 0.8, 0)
	caster.material_override = std_mat
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(caster)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.0
	var b := Basis.from_euler(Vector3(deg_to_rad(-34), deg_to_rad(45), 0))
	cam.transform = Transform3D(b, b.z * 30.0)
	add_child(cam)
	cam.current = true

	variants = [
		["ortho60", func():
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 60.0],
		["ortho200", func():
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 200.0],
		["pssm4_100", func():
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 100.0],
		["ortho60_nearfar", func():
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 60.0
			cam.near = 1.0
			cam.far = 80.0],
		["persp_cam", func():
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 30.0
			cam.near = 0.5
			cam.far = 200.0],
	]
	_next()

func _next() -> void:
	if idx >= variants.size():
		get_tree().quit()
		return
	var v: Array = variants[idx]
	(v[1] as Callable).call()
	get_tree().create_timer(0.8).timeout.connect(func():
		get_viewport().get_texture().get_image().save_png("docs/visual_match/captures/dbg_micro_%s.png" % v[0])
		print("MICRO SAVED %s" % v[0])
		idx += 1
		_next())

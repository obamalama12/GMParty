## Renders the landmark props in two rows: godot --path . --script res://tools/board_builder/preview_props.gd
## Environment: SHOTS_DIR (default user://)
extends SceneTree

const DIR := "res://plugins/boards/MarkyValley/props/"


func _initialize() -> void:
	_run()


func _run() -> void:
	var names: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".glb"):
			names.append(f.trim_suffix(".glb"))
	names.sort()
	var vp := SubViewport.new()
	vp.size = Vector2i(1800, 900)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.85, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 1.0)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.72, 0.3)
	plane.material = gm
	ground.mesh = plane
	vp.add_child(ground)
	var per_row := 10
	for i in names.size():
		var inst: Node3D = load(DIR + names[i] + ".glb").instantiate()
		var row := i / per_row
		inst.position = Vector3((i % per_row) * 12.0 - 54.0, 0, row * 22.0 - 10.0)
		if names[i] == "Castle":
			inst.scale = Vector3.ONE * 0.45
		vp.add_child(inst)
	var cam := Camera3D.new()
	cam.fov = 38
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 34, 58), Vector3(0, 3, 0))
	for i in 8:
		await process_frame
	var dir := OS.get_environment("SHOTS_DIR") if OS.get_environment("SHOTS_DIR") != "" else "user://"
	vp.get_texture().get_image().save_png(dir.path_join("props.png"))
	print("PROPS ", names)
	quit()

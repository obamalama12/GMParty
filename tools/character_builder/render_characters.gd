## Dev tool: renders character previews (and icon.png / splash.png for the
## procedural characters). Needs a display or xvfb, see README.md.
##
## Environment: ICON_SIZE    size of icon.png and splash.png in pixels (default 512)
##              SHOTS_DIR  where previews go (default user://character_previews)
##              WRITE_ICONS=1  also write icon.png and splash.png into the plugin folders
extends SceneTree

## Characters to preview: every folder in plugins/characters, or the ones listed in CHARACTERS
## (comma separated).
var characters: Array = []

var shots_dir: String
var write_icons := false
var icon_size := 512


func _initialize() -> void:
	shots_dir = OS.get_environment("SHOTS_DIR")
	if shots_dir == "":
		shots_dir = "user://character_previews"
	DirAccess.make_dir_recursive_absolute(shots_dir)
	write_icons = OS.get_environment("WRITE_ICONS") == "1"
	if OS.get_environment("ICON_SIZE") != "":
		icon_size = int(OS.get_environment("ICON_SIZE"))
	if OS.get_environment("CHARACTERS") != "":
		characters = Array(OS.get_environment("CHARACTERS").split(","))
	else:
		characters = Array(DirAccess.get_directories_at("res://plugins/characters"))
		characters.sort()
	_run()


func load_char(char_name: String) -> Node3D:
	return load("res://plugins/characters/%s/character.tscn" % char_name).instantiate()


## Remembers the pose; it is applied once the node is in the scene tree (see render).
func pose(node: Node, anim: String, t: float) -> void:
	node.set_meta("pose", [anim, t])


func apply_pose(node: Node) -> void:
	if not node.has_meta("pose"):
		return
	var spec: Array = node.get_meta("pose")
	var player := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player and player.has_animation(spec[0]):
		player.play(spec[0])
		player.seek(spec[1], true)
		player.pause()


## Renders the nodes with a camera and returns the image.
func render(nodes: Array, cam_pos: Vector3, look_at: Vector3, fov: float, size: Vector2i,
		transparent: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.85, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 1.0)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.8
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -150, 0)
	fill.light_energy = 0.35
	vp.add_child(fill)

	for n in nodes:
		vp.add_child(n)
		apply_pose(n)

	var cam := Camera3D.new()
	cam.fov = fov
	vp.add_child(cam)
	cam.position = cam_pos
	cam.look_at(look_at)

	for i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _run() -> void:
	# Turnaround sheets for the procedural characters: front, three-quarter, side, back.
	for char_name in characters:
		var views: Array[Image] = []
		for angle in [0.0, 40.0, 90.0, 180.0]:
			var c := load_char(char_name)
			c.rotation_degrees.y = angle
			pose(c, "idle", 0.3)
			views.append(await render([c], Vector3(0, 0.62, 3.1), Vector3(0, 0.46, 0), 28.0,
					Vector2i(380, 540), false))
		var sheet := Image.create(380 * 4, 540, false, Image.FORMAT_RGBA8)
		for i in views.size():
			sheet.blit_rect(views[i], Rect2i(0, 0, 380, 540), Vector2i(380 * i, 0))
		sheet.save_png(shots_dir.path_join(char_name + "_turnaround.png"))
		print("PREVIEW ", char_name)

	# Animation strip so the poses can be checked.
	for char_name in characters:
		var anims := [["idle", 0.5], ["walk", 0.1], ["run", 0.1], ["jump", 0.4], ["happy", 0.25],
				["sad", 1.0], ["stun", 0.1], ["punch", 0.2], ["kick", 0.35]]
		var strip := Image.create(300 * anims.size(), 420, false, Image.FORMAT_RGBA8)
		for i in anims.size():
			var c := load_char(char_name)
			c.rotation_degrees.y = 35
			pose(c, anims[i][0], anims[i][1])
			var img: Image = await render([c], Vector3(0, 0.62, 3.2), Vector3(0, 0.46, 0), 28.0,
					Vector2i(300, 420), false)
			strip.blit_rect(img, Rect2i(0, 0, 300, 420), Vector2i(300 * i, 0))
		strip.save_png(shots_dir.path_join(char_name + "_animations.png"))

	# Lineup next to the existing characters, to compare size and style.
	var nodes: Array = []
	var x := -(characters.size() - 1) * 0.6
	for char_name in characters:
		var c := load_char(char_name)
		c.position.x = x
		x += 1.2
		pose(c, "idle", 0.3)
		nodes.append(c)
	var line := await render(nodes, Vector3(0, 0.75, 6.2), Vector3(0, 0.42, 0), 32.0,
			Vector2i(1800, 520), false)
	line.save_png(shots_dir.path_join("lineup.png"))
	print("PREVIEW lineup")

	if write_icons:
		for char_name in characters:
			var c := load_char(char_name)
			pose(c, "idle", 0.3)
			var icon := await render([c], Vector3(0, 0.72, 1.5), Vector3(0, 0.7, 0), 30.0,
					Vector2i(icon_size, icon_size), true)
			icon.save_png("res://plugins/characters/%s/icon.png" % char_name)
			var s := load_char(char_name)
			s.rotation_degrees.y = 25
			pose(s, "happy", 0.5)
			var splash := await render([s], Vector3(0, 0.6, 2.7), Vector3(0, 0.46, 0), 30.0,
					Vector2i(icon_size, icon_size), true)
			splash.save_png("res://plugins/characters/%s/splash.png" % char_name)
			print("ICONS ", char_name)
	print("RENDER DONE")
	quit()

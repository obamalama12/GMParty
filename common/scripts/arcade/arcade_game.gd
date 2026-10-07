class_name ArcadeGame
extends Node3D
## Base of the small arcade minigames. It finds the players, builds the camera, light and floor, runs the clock and
## calls the hooks below. The server (the peer that decides) runs `server_tick`, every peer runs `world_tick`.

@export var duration := 30.0

var lobby: Lobby
var players: Array[ArcadePlayer] = []
var running := false
var finished := false
var time_left := 0.0

const NATURE := "res://assets/models/nature/glTF/"


func _enter_tree() -> void:
	lobby = Lobby.get_lobby(self)


func _ready() -> void:
	for i in 4:
		var p := get_node_or_null("Player%d" % (i + 1)) as ArcadePlayer
		if p:
			players.append(p)
	build_world()
	if has_node("Countdown"):
		$Countdown.finish.connect(_on_go)
	else:
		_on_go()
	_update_time_label()


# ----- hooks for the games -----

## Builds the arena. Called once, before the countdown.
func build_world() -> void:
	pass

## The countdown is over.
func on_go() -> void:
	pass

## Runs on every peer while the game is on.
func world_tick(_delta: float) -> void:
	pass

## Runs on the server only while the game is on.
func server_tick(_delta: float) -> void:
	pass

## The time is up (the server decides how the game ends).
func on_time_up() -> void:
	pass


# ----- the clock -----

func _on_go() -> void:
	running = true
	time_left = duration
	on_go()


func _physics_process(delta: float) -> void:
	if not running or finished:
		return
	time_left = maxf(time_left - delta, 0.0)
	_update_time_label()
	world_tick(delta)
	if multiplayer.is_server():
		server_tick(delta)
		if time_left <= 0.0:
			on_time_up()


func _update_time_label() -> void:
	var label := get_node_or_null("Screen/Time") as Label
	if label:
		label.text = "%d" % ceili(time_left if running else duration)


# ----- helpers for building the scene -----

func make_environment(sky: Color, ambient: Color) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)


func make_camera(pos: Vector3, look_at_point: Vector3, fov := 50.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.position = pos
	add_child(cam)
	cam.look_at(look_at_point)
	cam.current = true
	return cam


func make_music(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var music := AudioStreamPlayer.new()
	music.stream = stream
	music.bus = &"Music"
	music.autoplay = true
	add_child(music)


func toon(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = texture
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 1.0
	return m


## A round floor with collision, its top at y = 0.
func add_disc(radius: float, color: Color, texture: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.6
	cyl.material = toon(color, texture)
	mesh.mesh = cyl
	mesh.position.y = -0.3
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = 0.6
	shape.shape = cs
	shape.position.y = -0.3
	body.add_child(shape)
	add_child(body)
	return body


## Scenery outside of a circle: rocks, bushes and trees from the nature models.
func decorate(inner_radius: float, outer_radius: float, count: int, kinds: Array, seed_value := 1, behind_only := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scenes: Array[PackedScene] = []
	for kind: String in kinds:
		var scene := load(NATURE + kind + ".gltf") as PackedScene
		if scene:
			scenes.append(scene)
	if scenes.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Scenery"
	add_child(holder)
	for i in count:
		var inst := scenes[rng.randi() % scenes.size()].instantiate() as Node3D
		var ang := rng.randf() * TAU
		if behind_only:
			ang = -rng.randf() * PI * 1.15 + PI * 0.075      # the far half, so nothing hides the arena from the camera
		var r := rng.randf_range(inner_radius, outer_radius)
		inst.position = Vector3(cos(ang) * r, -0.35, sin(ang) * r)
		inst.rotation.y = rng.randf() * TAU
		inst.scale = Vector3.ONE * rng.randf_range(1.0, 1.7)
		holder.add_child(inst)


func sound(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Effects"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func player_by_id(player_id: int) -> ArcadePlayer:
	for p in players:
		if p.info.player_id == player_id:
			return p
	return null


# ----- finishing -----

## Ends a game that is won by points (one entry per player node, in order), for FFA, Duel and 2v2.
func finish_by_points(points: Array) -> void:
	if finished:
		return
	finished = true
	match lobby.minigame_state.minigame_type:
		Lobby.MINIGAME_TYPES.TWO_VS_TWO:
			lobby.minigame_team_win_by_points([points[0] + points[1], points[2] + points[3]])
		_:
			lobby.minigame_win_by_points(points)

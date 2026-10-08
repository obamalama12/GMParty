extends Node3D

const CANNON_BALL := preload("res://plugins/minigames/forest_run/Forest Arena/CannonBall.tscn")
const MAX_LIVES := 3
const TIME_BONUS := 4.0
const BOOST_TIME := 3.0
const PICKUP_CLOCK := 0
const PICKUP_BOOST := 1

@onready var lobby := Lobby.get_lobby(self)

var lives := MAX_LIVES
var invulnerable := 0.0
var game_over := false
var pickups_spawned := false
var pickups := {}
var sky_timer := 4.0
var elapsed := 0.0
var lives_label: Label

func fire_catapults():
	for i in range(1, 8):
		get_node("Catapult" + str(i)).fire()
		await get_tree().create_timer(0.1).timeout

func _ready():
	lives_label = Label.new()
	lives_label.theme_type_variation = &"HeaderLarge"
	lives_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	lives_label.position = Vector2(30, 20)
	add_child(lives_label)
	update_lives_label()

func update_lives_label():
	lives_label.text = tr("FOREST_RUN_LIVES").format({"lives": lives})

func _client_process(_delta: float):
	$Remaining.text = str(snapped($Timer2.time_left, 0.1))

# The index of the last waypoint the player has passed, used for respawning
func checkpoint_position() -> Vector3:
	var best: Node3D = $Ground/Waypoint
	for waypoint in get_waypoints():
		if waypoint.global_position.x <= $Player1.global_position.x:
			best = waypoint
	return best.global_position + Vector3(0, 1.0, 0)

func get_waypoints() -> Array:
	var result := []
	for i in range(1, 10):
		result.append(get_node("Ground/Waypoint" + (str(i) if i > 1 else "")))
	return result

func _server_process(delta: float):
	if game_over:
		return
	elapsed += delta
	invulnerable = maxf(0.0, invulnerable - delta)
	if not pickups_spawned:
		spawn_pickups()
	
	if $Player1.position.y < -5:
		on_player_fell()
	
	# Sky balls: warning marker first, then a ball drops on the player's path
	var player_x: float = $Player1.global_position.x
	sky_timer -= delta
	if sky_timer <= 0:
		var progress := clampf((player_x + 50.0) / 120.0, 0.0, 1.0)
		sky_timer = lerpf(3.2, 1.3, progress)
		if player_x > -38 and player_x < 62:
			drop_sky_ball()

func drop_sky_ball():
	var player = $Player1
	var target: Vector3 = player.global_position + Vector3(player.acceleration.x, 0, player.acceleration.z) * 1.3
	target += Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	var pos := Vector3(target.x, 11.0, target.z)
	lobby.broadcast(spawn_sky_ball.bind(pos))
	spawn_sky_ball(pos)

@rpc func spawn_sky_ball(pos: Vector3):
	var ball = CANNON_BALL.instantiate()
	$Catapult1.add_child(ball)
	ball.set_as_top_level(true)
	ball.transform = Transform3D(Basis(), pos)
	ball.velocity = Vector3.ZERO
	ball.hit_height = 0.25

# ----- Lives ----- #

func on_player_hit():
	if not multiplayer.is_server() or game_over or invulnerable > 0:
		return
	lose_life()

func on_player_fell():
	if invulnerable > 0:
		return
	var respawn_pos := checkpoint_position()
	lose_life()
	if not game_over:
		lobby.broadcast($Player1.respawn.bind(respawn_pos))
		$Player1.respawn(respawn_pos)

func lose_life():
	lives -= 1
	invulnerable = 1.8
	lobby.broadcast(lives_changed.bind(lives))
	lives_changed(lives)
	if lives <= 0:
		game_over = true
		await get_tree().create_timer(1.0).timeout
		lobby.minigame_gnu_loose()

@rpc func lives_changed(new_lives: int):
	lives = new_lives
	update_lives_label()
	$Player1.show_popup(tr("FOREST_RUN_OUCH"), Color(1, 0.3, 0.3))
	$Player1.blink(1.8)
	var player := AudioStreamPlayer.new()
	player.stream = load("res://assets/sounds/wrong.wav")
	player.bus = &"Effects"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

# ----- Pickups ----- #

func spawn_pickups():
	pickups_spawned = true
	var points := []
	for waypoint in get_waypoints():
		points.append(waypoint.global_position)
	# Walk along the path and place a pickup every few meters
	var id := 0
	var dist_since := 0.0
	var spacing := 9.0
	var next_at := 14.0
	var walked := 0.0
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var length := a.distance_to(b)
		while next_at <= walked + length:
			var t := (next_at - walked) / length
			var pos: Vector3 = a.lerp(b, t) + Vector3(0, 0.9, 0)
			if pos.x < 62:
				var type := PICKUP_BOOST if id % 3 == 2 else PICKUP_CLOCK
				lobby.broadcast(spawn_pickup.bind(id, type, pos))
				spawn_pickup(id, type, pos)
				id += 1
			next_at += spacing
		walked += length

@rpc func spawn_pickup(id: int, type: int, pos: Vector3):
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.9
	col.shape = shape
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if type == PICKUP_CLOCK:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.35
		cyl.bottom_radius = 0.35
		cyl.height = 0.12
		mesh.mesh = cyl
		mesh.rotation_degrees.x = 90
		material.albedo_color = Color(1, 0.85, 0.2)
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		mesh.mesh = sphere
		material.albedo_color = Color(1, 0.3, 0.3)
	mesh.material_override = material
	area.add_child(mesh)
	add_child(area)
	area.position = pos
	pickups[id] = area
	var tween := mesh.create_tween().set_loops()
	tween.tween_property(mesh, ^"position:y", 0.25, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mesh, ^"position:y", -0.15, 0.5).set_trans(Tween.TRANS_SINE)
	if multiplayer.is_server():
		area.body_entered.connect(_on_pickup_entered.bind(id, type))

func _on_pickup_entered(body, id: int, type: int):
	if game_over or not pickups.has(id) or not body.is_in_group("player"):
		return
	lobby.broadcast(collect_pickup.bind(id, type))
	collect_pickup(id, type)

@rpc func collect_pickup(id: int, type: int):
	if pickups.has(id):
		pickups[id].queue_free()
		pickups.erase(id)
	var sound := AudioStreamPlayer.new()
	sound.stream = load("res://assets/sounds/correct.wav")
	sound.bus = &"Effects"
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	if type == PICKUP_CLOCK:
		$Timer2.start($Timer2.time_left + TIME_BONUS)
		$Player1.show_popup(tr("FOREST_RUN_TIME_BONUS").format({"seconds": int(TIME_BONUS)}), Color(1, 0.85, 0.2))
		sound.pitch_scale = 1.3
	else:
		$Player1.apply_boost(BOOST_TIME)
		$Player1.show_popup(tr("FOREST_RUN_SPEED"), Color(1, 0.4, 0.4))
		sound.pitch_scale = 1.6
	sound.play()

func _on_Finish_body_entered(_body):
	if not multiplayer.is_server() or game_over:
		return
	game_over = true
	lobby.minigame_gnu_win()

func _on_Timer2_timeout():
	if not multiplayer.is_server() or game_over:
		return
	game_over = true
	lobby.minigame_gnu_loose()

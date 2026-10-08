extends Node3D

@onready var lobby := Lobby.get_lobby(self)
const fireball := preload("res://plugins/minigames/dungeon_parkour/fireball.tscn")

const MAX_LIVES := 3
const TIME_BONUS := 4.0
const BOOST_TIME := 3.0
const PICKUP_CLOCK := 0
const PICKUP_BOOST := 1
const PICKUP_HEART := 2

var lives := MAX_LIVES
var invulnerable := 0.0
var game_over := false
var pickups_spawned := false
var pickups := {}
var lane_timer := 5.0
var lives_label: Label

func _ready():
	lives_label = Label.new()
	lives_label.theme_type_variation = &"HeaderLarge"
	lives_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	lives_label.position = Vector2(30, 20)
	add_child(lives_label)
	update_lives_label()
	create_fireballs()

func update_lives_label():
	lives_label.text = tr("DUNGEON_PARKOUR_LIVES").format({"lives": lives})

func play_sound(path: String, pitch := 1.0):
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.pitch_scale = pitch
	player.bus = &"Effects"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

@rpc func create_fireball(pos: Vector3):
	var instance = fireball.instantiate()
	instance.position = pos
	add_child(instance)

func create_fireballs():
	if not multiplayer.is_server():
		return
	lobby.broadcast(create_fireball.bind($Fireball2.position))
	create_fireball($Fireball2.position)
	
	await get_tree().create_timer(0.25).timeout
	
	lobby.broadcast(create_fireball.bind($Fireball3.position))
	create_fireball($Fireball3.position)
	
	await get_tree().create_timer(0.25).timeout
	
	lobby.broadcast(create_fireball.bind($Fireball1.position))
	create_fireball($Fireball1.position)

func _client_process(_delta: float):
	$Remaining.text = "%.1f"%$Timer2.time_left

# Waypoints that are on solid ground (the two on the moving platform are skipped)
func get_checkpoints() -> Array:
	var result := []
	for waypoint_name in ["Waypoint", "Waypoint7", "Waypoint8", "Waypoint2", "Waypoint3", "Waypoint9", "Waypoint5", "Waypoint6"]:
		result.append(get_node("Ground/" + waypoint_name))
	return result

func checkpoint_position() -> Vector3:
	var best: Node3D = $Ground/Waypoint
	var player_x: float = $Player1.global_position.x
	for waypoint in get_checkpoints():
		if waypoint.global_position.x <= player_x:
			best = waypoint
	return best.global_position + Vector3(0, 1.0, 0)

func _server_process(delta: float):
	if game_over:
		return
	invulnerable = maxf(0.0, invulnerable - delta)
	if not pickups_spawned:
		spawn_pickups()
	
	if $Player1.position.y < -5:
		on_player_fell()
	
	# Extra fireball lanes, aimed ahead of the player. They get more frequent.
	var player_pos: Vector3 = $Player1.global_position
	lane_timer -= delta
	if lane_timer <= 0:
		var progress := clampf((player_pos.x + 50.0) / 110.0, 0.0, 1.0)
		lane_timer = lerpf(3.2, 1.4, progress)
		if player_pos.x > -22 and player_pos.x < 50 and player_pos.z < -12:
			launch_lane_fireball(clampf(player_pos.x + randf_range(2.0, 8.0), -20.0, 54.0))

func launch_lane_fireball(x: float):
	lobby.broadcast(show_warning.bind(x))
	show_warning(x)
	await get_tree().create_timer(0.8).timeout
	if game_over:
		return
	var pos := Vector3(x, 1, -35)
	lobby.broadcast(create_fireball.bind(pos))
	create_fireball(pos)

@rpc func show_warning(x: float):
	var label := Label3D.new()
	label.text = "!"
	label.modulate = Color(1, 0.3, 0.1)
	label.outline_size = 12
	label.pixel_size = 0.02
	label.font_size = 64
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.position = Vector3(x, 2.5, -24)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.2, 0.2)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.tween_property(label, "modulate:a", 0.2, 0.2)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.tween_callback(label.queue_free)
	play_sound("res://assets/sounds/wrong.wav", 1.8)

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
	lobby.broadcast(lives_changed.bind(lives, false))
	lives_changed(lives, false)
	if lives <= 0:
		game_over = true
		await get_tree().create_timer(1.0).timeout
		lobby.minigame_nolok_loose()

@rpc func lives_changed(new_lives: int, gained: bool):
	lives = new_lives
	update_lives_label()
	if gained:
		return
	$Player1.show_popup(tr("DUNGEON_PARKOUR_OUCH"), Color(1, 0.3, 0.3))
	$Player1.blink(1.8)
	play_sound("res://assets/sounds/wrong.wav")

# ----- Pickups ----- #

func spawn_pickups():
	pickups_spawned = true
	var points := []
	for waypoint in get_checkpoints():
		points.append(waypoint.global_position)
	# Walk along the path and place a pickup every few meters
	var id := 0
	var spacing := 8.0
	var next_at := 12.0
	var walked := 0.0
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var length := a.distance_to(b)
		while next_at <= walked + length:
			var t := (next_at - walked) / length
			var pos: Vector3 = a.lerp(b, t) + Vector3(0, 0.9, 0)
			# Keep pickups off the moving platform section
			if pos.x < 62 and not (pos.x > 3 and pos.x < 17):
				var type := PICKUP_CLOCK
				if id % 4 == 3:
					type = PICKUP_BOOST
				elif id % 7 == 5:
					type = PICKUP_HEART
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
	match type:
		PICKUP_CLOCK:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.35
			cyl.bottom_radius = 0.35
			cyl.height = 0.12
			mesh.mesh = cyl
			mesh.rotation_degrees.x = 90
			material.albedo_color = Color(1, 0.85, 0.2)
		PICKUP_BOOST:
			var sphere := SphereMesh.new()
			sphere.radius = 0.32
			sphere.height = 0.64
			mesh.mesh = sphere
			material.albedo_color = Color(0.3, 1, 0.5)
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 0.5, 0.5)
			mesh.mesh = box
			mesh.rotation_degrees = Vector3(45, 0, 45)
			material.albedo_color = Color(1, 0.2, 0.4)
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
	if game_over or not pickups.has(id) or not body is CharacterBody3D:
		return
	if type == PICKUP_HEART:
		if lives >= MAX_LIVES:
			return
		lives += 1
		lobby.broadcast(lives_changed.bind(lives, true))
		lives_changed(lives, true)
	lobby.broadcast(collect_pickup.bind(id, type))
	collect_pickup(id, type)

@rpc func collect_pickup(id: int, type: int):
	if pickups.has(id):
		pickups[id].queue_free()
		pickups.erase(id)
	match type:
		PICKUP_CLOCK:
			$Timer2.start($Timer2.time_left + TIME_BONUS)
			$Player1.show_popup(tr("DUNGEON_PARKOUR_TIME_BONUS").format({"seconds": int(TIME_BONUS)}), Color(1, 0.85, 0.2))
			play_sound("res://assets/sounds/correct.wav", 1.3)
		PICKUP_BOOST:
			$Player1.apply_boost(BOOST_TIME)
			$Player1.show_popup(tr("DUNGEON_PARKOUR_SPEED"), Color(0.4, 1, 0.5))
			play_sound("res://assets/sounds/correct.wav", 1.6)
		_:
			$Player1.show_popup(tr("DUNGEON_PARKOUR_LIFE"), Color(1, 0.3, 0.5))
			play_sound("res://assets/sounds/correct.wav", 0.9)

func _on_Finish_body_entered(_body):
	if not multiplayer.is_server() or game_over:
		return
	game_over = true
	lobby.minigame_nolok_win()

func _on_Timer2_timeout():
	if not multiplayer.is_server() or game_over:
		return
	game_over = true
	lobby.minigame_nolok_loose()

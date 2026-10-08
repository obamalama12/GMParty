extends ArcadeGame
## Jump Rope: a rope sweeps around the pole in the middle, faster and faster. Jump over it! Whoever is hit is out.
## Coins and stars float above the ring and can only be grabbed in mid-air. The rope plays tricks: it turns around, surges,
## stops for a fake-out and rises for a high swing. Points: time survived plus the coins grabbed.

const ARENA := 5.6
const ROPE_LENGTH := 5.7
const ROPE_HEIGHT := 0.55            # players whose feet are lower than this are hit
const HIT_WIDTH := 0.62
const MAX_TIME := 60.0
const COIN_VALUE := 2.0              # seconds of survival a coin is worth
const STAR_VALUE := 6.0
const COIN_LIFE := 9.0
const HIGH_HEIGHT := 1.0

var angle := 0.0
var spin := 1.7                      # radians per second, can be negative
var direction := 1.0
var elapsed := 0.0
var next_reversal := 9.0
var warn_left := 0.0
var survived := {}                   # player id -> seconds
var alive: Array[int] = []
var ended := false
var ropes: Array[Node3D] = []
var rope_count := 1
var arrow: Label3D
var sync_timer := 0.0
var rope_h := 0.55                   # current rope height (a high swing needs a good jump)
var rope_h_target := 0.55
var pattern := ""                    # "", "surge", "fake_slow", "fake_fast", "high"
var pattern_left := 0.0
var next_pattern := 8.0
var accel := 2.4
var coins := {}                      # player id -> value collected (server)
var coin_count := {}                 # player id -> number of pickups, for the HUD
var coin_nodes := {}                 # id -> Node3D
var coin_info := {}                  # server: id -> { "pos", "star", "life" }
var next_coin := 0
var coin_timer := 2.5
var hud: Label
var called_double := false
var called_triple := false
var called_fast := false


func build_world() -> void:
	make_sky(Color(0.95, 0.5, 0.45), Color(1.0, 0.85, 0.55), Color(0.7, 0.4, 0.3))
	make_camera(Vector3(0, 9.8, 8.2), Vector3(0, 0.4, 0.5), 50.0)
	make_music("res://assets/music/retro/big_top.ogg")
	# a circus ring: red and cream sectors, a golden middle and a ring of balloon poles, with bushes and trees behind it
	add_floor(ARENA, 1, [Color(0.93, 0.25, 0.25), Color(0.99, 0.93, 0.80), Color(0.99, 0.93, 0.80), Color(1.0, 0.8, 0.2)], 16.0)
	pole_ring(ARENA + 0.9, 9, 1.9, Color(0.95, 0.95, 0.95), Color(0.95, 0.25, 0.3), Color(0.3, 0.55, 1.0), 195.0, 345.0)
	arc_props(["Bush_Large_Flowers", "Bush_Large"], 12, ARENA + 2.4, 195.0, 345.0, 1.1, 1.4, -0.1, 12, 0.2)
	arc_props(["NormalTree_2", "NormalTree_4", "BirchTree_1", "BirchTree_3"], 8, ARENA + 5.0, 205.0, 335.0, 1.3, 1.8, -0.4, 13, 0.6)
	fence_arc(ARENA + 1.6, 200.0, 340.0, 13)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.3
	pc.bottom_radius = 0.38
	pc.height = 1.5
	pc.material = toon(Color(0.2, 0.25, 0.7))
	pole.mesh = pc
	pole.position.y = 0.75
	add_child(pole)
	var cap := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.42
	sph.height = 0.84
	sph.material = toon(Color(1.0, 0.8, 0.2))
	cap.mesh = sph
	cap.position.y = 1.55
	add_child(cap)
	# the ropes: long boxes that turn around the pole, striped from a few coloured pieces. More of them join later.
	for k in 3:
		var rope := Node3D.new()
		add_child(rope)
		var pieces := 8
		for i in pieces:
			var piece := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(ROPE_LENGTH / pieces, 0.2, 0.28)
			box.material = toon(Color(0.95, 0.15, 0.2) if i % 2 == 0 else Color(1, 1, 1))
			piece.mesh = box
			piece.position = Vector3(ROPE_LENGTH / pieces * (i + 0.5), 0.32, 0)
			rope.add_child(piece)
		var tip := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.28
		ball.height = 0.56
		ball.material = toon(Color(0.2, 0.25, 0.7))
		tip.mesh = ball
		tip.position = Vector3(ROPE_LENGTH, 0.32, 0)
		rope.add_child(tip)
		rope.visible = k < rope_count
		ropes.append(rope)
	hud = Label.new()
	hud.theme_type_variation = &"HeaderLarge"
	hud.add_theme_font_size_override("font_size", 28)
	hud.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.3))
	hud.add_theme_constant_override("outline_size", 8)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud.offset_left = -500
	hud.offset_right = 500
	hud.offset_top = -80
	hud.offset_bottom = -20
	$Screen.add_child(hud)
	arrow = Label3D.new()
	arrow.text = "!"
	arrow.font_size = 220
	arrow.modulate = Color(1, 0.2, 0.2)
	arrow.outline_size = 40
	arrow.position = Vector3(0, 3.2, 0)
	arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow.no_depth_test = true
	arrow.visible = false
	add_child(arrow)
	decorate(ARENA + 1.5, ARENA + 8.0, 20, ["Bush_Large", "Rock_5", "NormalTree_2", "NormalTree_4", "Bush_Flowers"], 12)
	var slots := [Vector3(-3.4, 0.05, -1.5), Vector3(3.4, 0.05, -1.5), Vector3(-3.4, 0.05, 2.5), Vector3(3.4, 0.05, 2.5)]
	for i in players.size():
		var p := players[i]
		p.position = slots[i]
		p.speed = 3.0
		p.jump_velocity = 8.2
		p.gravity = 24.0
		p.arena_radius = ARENA - 0.4
		p.ai_brain = _ai
		alive.append(p.info.player_id)
		survived[p.info.player_id] = 0.0
		coins[p.info.player_id] = 0.0
		coin_count[p.info.player_id] = 0
		_update_hud()


@rpc func sync_rope(new_angle: float, new_spin: float, new_height: float) -> void:
	angle = new_angle
	spin = new_spin
	rope_h_target = new_height


@rpc func warn_reversal() -> void:
	warn_left = 1.0
	sound("res://assets/sounds/arcade/pass.wav")


@rpc func set_rope_count(count: int) -> void:
	rope_count = count
	sound("res://assets/sounds/arcade/pass.wav")


func world_tick(delta: float) -> void:
	elapsed += delta
	angle += spin * delta
	for k in ropes.size():
		ropes[k].visible = k < rope_count
		ropes[k].rotation.y = -(angle + k * TAU / rope_count)
		ropes[k].position.y = rope_h - 0.55
	rope_h = move_toward(rope_h, rope_h_target, delta * 2.0)
	for id in coin_nodes:
		var cn: Node3D = coin_nodes[id]
		cn.rotation.y += delta * 4.0
		cn.position.y = (1.15 if cn.get_meta("star") else 1.0) + 0.1 * sin(elapsed * 4.0 + id)
	if warn_left > 0.0:
		warn_left -= delta
		arrow.visible = fmod(warn_left * 6.0, 1.0) < 0.6
	else:
		arrow.visible = false


## Is the player under the rope? (a segment from the pole outwards)
func _hit_test(p: ArcadePlayer) -> bool:
	if p.position.y >= rope_h - 0.12:
		return false
	var pos := Vector2(p.position.x, p.position.z)
	for k in rope_count:
		var a := angle + k * TAU / rope_count
		var dir := Vector2(cos(a), sin(a))
		var along := pos.dot(dir)
		if along < 0.0 or along > ROPE_LENGTH + 0.3:
			continue
		if absf(pos.x * dir.y - pos.y * dir.x) < HIT_WIDTH:
			return true
	return false


func _speed_factor() -> float:
	match pattern:
		"surge":
			return 1.7
		"fake_slow":
			return 0.1
		"fake_fast":
			return 2.1
	return 1.0


func _start_pattern() -> void:
	var pool := ["surge", "fake"]
	if elapsed > 14.0:
		pool.append("high")
		pool.append("fake")
	var pick: String = pool.pick_random()
	match pick:
		"surge":
			pattern = "surge"
			pattern_left = 3.2
			accel = 3.5
			announce("SURGE!", Color(1.0, 0.5, 0.2), 0.5)
		"fake":
			pattern = "fake_slow"
			pattern_left = 1.3
			accel = 10.0
			announce("FAKE-OUT!", Color(0.6, 0.9, 1.0), 0.5)
		"high":
			pattern = "high"
			pattern_left = 6.0
			rope_h_target = HIGH_HEIGHT
			announce("HIGH ROPE!", Color(1.0, 0.85, 0.3), 0.6)


func _update_pattern(delta: float) -> void:
	if pattern == "":
		next_pattern -= delta
		if next_pattern <= 0.0 and elapsed > 6.0 and next_pattern > -100.0 and warn_left <= 0.0:
			_start_pattern()
		return
	pattern_left -= delta
	if pattern_left > 0.0:
		return
	match pattern:
		"fake_slow":
			pattern = "fake_fast"
			pattern_left = 1.7
		_:
			pattern = ""
			accel = 2.4
			rope_h_target = ROPE_HEIGHT
			next_pattern = randf_range(6.0, 9.0)


func server_tick(delta: float) -> void:
	if ended:
		return
	# the ramp: faster the longer the game lasts, and now and then the rope turns around or plays a trick
	_update_pattern(delta)
	var target := (1.7 + elapsed * 0.095) * direction * _speed_factor()
	target = clampf(target, -7.0, 7.0)
	spin = move_toward(spin, target, delta * accel)
	if rope_count == 1 and elapsed > 16.0:
		rope_count = 2
		lobby.broadcast(set_rope_count.bind(2))
		announce("DOUBLE ROPE!", Color(1.0, 0.5, 0.3), 0.7)
	elif rope_count == 2 and elapsed > 30.0:
		rope_count = 3
		lobby.broadcast(set_rope_count.bind(3))
		announce("TRIPLE ROPE!", Color(1.0, 0.3, 0.3), 0.7)
	if elapsed > 42.0 and not called_fast:
		called_fast = true
		announce("HURRY UP!", Color(1.0, 0.3, 0.3), 0.6)
	next_reversal -= delta
	if next_reversal <= 1.0 and warn_left <= 0.0 and next_reversal > 0.0 and pattern == "":
		warn_left = 1.0
		lobby.broadcast(warn_reversal)
	if next_reversal <= 0.0:
		direction = -direction
		next_reversal = randf_range(7.0, 11.0)
		announce("REVERSE!", Color(0.6, 0.9, 1.0), 0.5)
	sync_timer -= delta
	if sync_timer <= 0.0:
		sync_timer = 0.1
		lobby.broadcast(sync_rope.bind(angle, spin, rope_h_target))
	_tick_coins(delta)
	for p in players:
		var pid := p.info.player_id
		if not alive.has(pid):
			continue
		survived[pid] += delta
		if _hit_test(p):
			alive.erase(pid)
			var away := Vector3(p.position.x, 0.0, p.position.z)
			if away.length() < 0.1:
				away = Vector3.BACK
			p.knock_out(away)
			p.show_animation("stun")
			lobby.broadcast(hit_sound)
			hit_sound()
			if alive.size() <= 1 and players.size() > 1:
				ended = true
				get_tree().create_timer(1.4).timeout.connect(_finish)
				return
	if elapsed >= MAX_TIME:
		on_time_up()


func _tick_coins(delta: float) -> void:
	coin_timer -= delta
	if coin_timer <= 0.0 and coin_info.size() < 3:
		coin_timer = randf_range(2.2, 3.4)
		var ang := randf() * TAU
		var r := randf_range(2.8, ARENA - 1.0)
		var pos := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var star := elapsed > 10.0 and randf() < 0.18
		var id := next_coin
		next_coin += 1
		coin_info[id] = {"pos": pos, "star": star, "life": COIN_LIFE}
		lobby.broadcast(spawn_coin.bind(id, pos, star))
		spawn_coin(id, pos, star)
	for id in coin_info.keys():
		var c: Dictionary = coin_info[id]
		c.life -= delta
		var taker: ArcadePlayer = null
		for p in players:
			if alive.has(p.info.player_id) and p.position.y > 0.4 and Vector2(p.position.x - c.pos.x, p.position.z - c.pos.z).length() < 1.0:
				taker = p
				break
		if taker == null and c.life > 0.0:
			continue
		coin_info.erase(id)
		if taker == null:
			lobby.broadcast(take_coin.bind(id, -1, 0.0))
			take_coin(id, -1, 0.0)
			continue
		var value := STAR_VALUE if c.star else COIN_VALUE
		coins[taker.info.player_id] += value
		lobby.broadcast(take_coin.bind(id, taker.info.player_id, value))
		take_coin(id, taker.info.player_id, value)
		if c.star:
			taker.boost(3.0)


@rpc func spawn_coin(id: int, pos: Vector3, star: bool) -> void:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5 if star else 0.38
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.9, 1.0) if star else Color(1.0, 0.85, 0.15)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 1.2
	cyl.material = mat
	mesh.mesh = cyl
	mesh.rotation.x = PI / 2.0
	node.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = mat.albedo_color
	light.omni_range = 3.0
	light.light_energy = 0.8
	node.add_child(light)
	node.set_meta("star", star)
	node.position = Vector3(pos.x, 1.0, pos.z)
	node.scale = Vector3.ZERO
	add_child(node)
	coin_nodes[id] = node
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


@rpc func take_coin(id: int, player_id: int, value: float) -> void:
	var node: Node3D = coin_nodes.get(id)
	coin_nodes.erase(id)
	var where := Vector3.ZERO
	if node:
		where = node.position
		node.queue_free()
	if player_id == -1:
		return
	sound("res://assets/sounds/arcade/pass.wav")
	coin_count[player_id] = coin_count.get(player_id, 0) + 1
	var label := Label3D.new()
	label.text = "+%d" % int(value)
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.9, 0.3)
	label.outline_size = 24
	label.outline_modulate = Color(0.1, 0.03, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = where + Vector3(0, 0.8, 0)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 1.3, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
	_update_hud()


func _update_hud() -> void:
	var parts: Array[String] = []
	for p in players:
		parts.append("%s: %d" % [p.info.name, coin_count.get(p.info.player_id, 0)])
	hud.text = "COINS   " + "     ".join(parts)


@rpc func hit_sound() -> void:
	sound("res://assets/sounds/arcade/thud.wav")


func on_time_up() -> void:
	if not ended:
		ended = true
	_finish()


func _finish() -> void:
	if finished:
		return
	var points := []
	for p in players:
		var pid := p.info.player_id
		var t: float = survived[pid] + coins[pid]
		if alive.has(pid):
			t += 8.0                                # the last one standing gets a bonus on top
		points.append(snappedf(t, 0.1))
	finish_by_points(points)


# ----- the bots -----

func _ai(p: ArcadePlayer, _delta: float) -> Dictionary:
	if not running or p.dead:
		return {"dir": Vector2.ZERO}
	var dir := Vector2.ZERO
	var jump := false
	var pos := Vector2(p.position.x, p.position.z)
	# how long until the rope reaches me?
	var my_angle := atan2(pos.y, pos.x)
	var eta := 99.0
	for k in rope_count:
		var diff := fposmod(my_angle - (angle + k * TAU / rope_count), TAU)
		if spin < 0.0:
			diff = TAU - diff
		eta = minf(eta, diff / maxf(absf(spin), 0.1))
	var window_start := 0.20
	var window_end := 0.31
	match p.info.ai_difficulty:
		Lobby.Difficulty.EASY:
			window_start = 0.12
			window_end = 0.34
		Lobby.Difficulty.NORMAL:
			window_start = 0.17
			window_end = 0.32
	if eta > window_start and eta < window_end and p.is_on_floor() and randf() > (0.4 if p.info.ai_difficulty == Lobby.Difficulty.EASY else 0.12):
		jump = true
	# stay in a comfortable place, away from the pole
	if pos.length() < 2.4:
		dir = pos.normalized() if pos.length() > 0.1 else Vector2.RIGHT
	elif pos.length() > ARENA - 1.0:
		dir = -pos.normalized()
	# go for a coin when the rope is not about to arrive, and jump under it
	if p.info.ai_difficulty != Lobby.Difficulty.EASY or randf() < 0.5:
		var best := 5.0
		for id in coin_nodes:
			var cn: Node3D = coin_nodes[id]
			var cp := Vector2(cn.position.x, cn.position.z)
			var d := pos.distance_to(cp)
			if d < best and eta > 0.55:
				best = d
				dir = (cp - pos).normalized() if d > 0.3 else Vector2.ZERO
				if d < 0.9 and eta > 0.8 and p.is_on_floor():
					jump = true
	return {"dir": dir, "jump": jump}

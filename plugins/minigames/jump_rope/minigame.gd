extends ArcadeGame
## Jump Rope: a rope sweeps around the pole in the middle, faster and faster. Jump over it! Whoever is hit is out,
## the one who lasts longest wins.

const ARENA := 5.6
const ROPE_LENGTH := 5.7
const ROPE_HEIGHT := 0.55            # players whose feet are lower than this are hit
const HIT_WIDTH := 0.62
const MAX_TIME := 55.0

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


func build_world() -> void:
	make_sky(Color(0.95, 0.5, 0.45), Color(1.0, 0.85, 0.55), Color(0.7, 0.4, 0.3))
	make_camera(Vector3(0, 9.8, 8.2), Vector3(0, 0.4, 0.5), 50.0)
	make_music("res://assets/music/minigames/haunted dreams.ogg")
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


@rpc func sync_rope(new_angle: float, new_spin: float) -> void:
	angle = new_angle
	spin = new_spin


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
	if warn_left > 0.0:
		warn_left -= delta
		arrow.visible = fmod(warn_left * 6.0, 1.0) < 0.6
	else:
		arrow.visible = false


## Distance of a point on the floor from the rope (a segment from the pole outwards), and how far along it is.
func _hit_test(p: ArcadePlayer) -> bool:
	if p.position.y >= ROPE_HEIGHT - 0.12:
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


func server_tick(delta: float) -> void:
	if ended:
		return
	# the ramp: faster the longer the game lasts, and now and then the rope turns around
	var target := (1.7 + elapsed * 0.095) * direction
	target = clampf(target, -5.4, 5.4)
	spin = move_toward(spin, target, delta * 2.4)
	if rope_count == 1 and elapsed > 16.0:
		rope_count = 2
		lobby.broadcast(set_rope_count.bind(2))
	elif rope_count == 2 and elapsed > 30.0:
		rope_count = 3
		lobby.broadcast(set_rope_count.bind(3))
	next_reversal -= delta
	if next_reversal <= 1.0 and warn_left <= 0.0 and next_reversal > 0.0:
		warn_left = 1.0
		lobby.broadcast(warn_reversal)
	if next_reversal <= 0.0:
		direction = -direction
		next_reversal = randf_range(7.0, 11.0)
	sync_timer -= delta
	if sync_timer <= 0.0:
		sync_timer = 0.1
		lobby.broadcast(sync_rope.bind(angle, spin))
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
		var t: float = survived[p.info.player_id]
		if alive.has(p.info.player_id):
			t += 100.0                              # everybody who is still in beats everybody who was hit
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
	return {"dir": dir, "jump": jump}

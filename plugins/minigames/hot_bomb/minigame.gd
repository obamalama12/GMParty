extends ArcadeGame
## Hot Bomb: one player carries a lit bomb and has to touch somebody else to pass it on. When the fuse is
## burnt up, the player holding the bomb is out. The last one standing wins.

const ARENA := 6.4
const PASS_RADIUS := 1.25
const BOMB_MESH := preload("res://assets/models/Bomb/Bomb.obj")
const HOLDER_SPEED := 1.32

var holder := -1                 # player id of the bomb carrier, -1 = nobody yet
var fuse := 0.0                  # seconds until the bomb goes off
var start_delay := 1.2
var alive: Array[int] = []
var placement: Array = []        # the winner first, filled while players get eliminated
var immune := {}                 # player id -> seconds the player cannot receive the bomb
var pass_cooldown := 0.0
var markers := {}                # player id -> bomb node above the head
var ended := false
var flash_time := 0.0
var ai_wander := {}


func build_world() -> void:
	make_sky(Color(0.16, 0.05, 0.22), Color(0.95, 0.38, 0.18), Color(0.2, 0.05, 0.05))
	make_camera(Vector3(0, 10.5, 9.0), Vector3(0, 0.3, 0.5), 50.0)
	make_music("res://assets/music/retro/volcano_panic.ogg")
	# a cracked rock platform in a lava lake, rocks and dead trees around it, and a glow from below
	add_floor(ARENA, 3, [Color(0.26, 0.19, 0.34), Color(0.0, 0.0, 0.0), Color(0.9, 0.32, 0.06), Color(1.0, 0.45, 0.05)], 7.0)
	var lava := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	var lava_mat := toon(Color(1.0, 0.38, 0.05), load("res://assets/textures/lava.png"))
	lava_mat.emission_enabled = true
	lava_mat.emission = Color(1.0, 0.3, 0.02)
	lava_mat.emission_energy_multiplier = 1.3
	lava_mat.uv1_scale = Vector3(6, 6, 1)
	plane.material = lava_mat
	lava.mesh = plane
	lava.position.y = -0.5
	add_child(lava)
	arc_props(["Rock_2", "Rock_4", "Rock_5", "Rock_1"], 12, ARENA + 2.4, 195.0, 345.0, 2.0, 3.2, -0.6, 9, 0.5)
	arc_props(["DeadTree_1", "DeadTree_3", "DeadTree_5", "DeadTree_7"], 9, ARENA + 3.6, 200.0, 340.0, 1.3, 1.9, -0.6, 11, 0.7)
	for k in 4:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.45, 0.12)
		light.light_energy = 2.2
		light.omni_range = 9.0
		var a := deg_to_rad(210.0 + k * 40.0)
		light.position = Vector3(cos(a) * (ARENA + 1.2), 0.6, sin(a) * (ARENA + 1.2))
		add_child(light)
	var embers := CPUParticles3D.new()
	embers.amount = 60
	embers.lifetime = 4.0
	embers.preprocess = 4.0
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(10, 0.2, 8)
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.gravity = Vector3(0, 1.0, 0)
	embers.initial_velocity_min = 1.0
	embers.initial_velocity_max = 2.5
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.05
	ember_mesh.height = 0.1
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(1.0, 0.7, 0.2)
	ember_mesh.material = ember_mat
	embers.mesh = ember_mesh
	embers.position.y = 0.0
	add_child(embers)
	placement.resize(players.size())
	for i in players.size():
		var p := players[i]
		var ang := TAU * i / players.size() + 0.3
		p.position = Vector3(cos(ang) * 3.4, 0.05, sin(ang) * 3.4)
		p.speed = 4.6
		p.arena_radius = ARENA - 0.45
		p.ai_brain = _ai
		alive.append(p.info.player_id)
		var marker := Node3D.new()
		var mesh := MeshInstance3D.new()
		mesh.mesh = BOMB_MESH
		mesh.scale = Vector3.ONE * 0.2
		mesh.material_override = toon(Color(0.12, 0.12, 0.14))
		marker.add_child(mesh)
		marker.position.y = 1.55
		marker.visible = false
		p.add_child(marker)
		markers[p.info.player_id] = marker
		immune[p.info.player_id] = 0.0


func _process(delta: float) -> void:
	flash_time += delta * (3.0 + (6.0 / maxf(fuse, 0.6)) * 3.0)
	for pid in markers:
		var marker: Node3D = markers[pid]
		if marker.visible:
			var mesh := marker.get_child(0) as MeshInstance3D
			var hot := 0.5 + 0.5 * sin(flash_time)
			(mesh.material_override as StandardMaterial3D).albedo_color = Color(0.12, 0.12, 0.14).lerp(Color(1.0, 0.15, 0.05), hot)
			marker.position.y = 1.55 + 0.08 * sin(flash_time * 0.5)
			marker.scale = Vector3.ONE * (1.0 + 0.08 * hot)


@rpc func set_holder(player_id: int, new_fuse: float) -> void:
	holder = player_id
	fuse = new_fuse
	for p in players:
		var is_holder: bool = p.info.player_id == player_id
		markers[p.info.player_id].visible = is_holder
		p.speed_multiplier = HOLDER_SPEED if is_holder else 1.0
	if player_id != -1:
		sound("res://assets/sounds/arcade/pass.wav")


@rpc func explode(player_id: int) -> void:
	var p := player_by_id(player_id)
	if p == null:
		return
	markers[player_id].visible = false
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat
	flash.mesh = sphere
	flash.position = p.position + Vector3(0, 1.0, 0)
	add_child(flash)
	var tween := create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 0.45)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(flash.queue_free)
	sound("res://assets/sounds/arcade/boom.wav")


func on_go() -> void:
	start_delay = 0.8


func _random_fuse() -> float:
	return randf_range(4.2, 6.6) if alive.size() > 2 else randf_range(3.2, 5.0)


func _give_to_random() -> void:
	var target: int = alive.pick_random()
	fuse = _random_fuse()
	pass_cooldown = 0.7
	immune[target] = 0.6
	lobby.broadcast(set_holder.bind(target, fuse))
	set_holder(target, fuse)


func world_tick(delta: float) -> void:
	# the clients count the fuse down on their own, so the flashing speeds up in time
	if not multiplayer.is_server() and holder != -1:
		fuse = maxf(fuse - delta, 0.0)


func server_tick(delta: float) -> void:
	if ended:
		return
	for pid in immune:
		immune[pid] = maxf(immune[pid] - delta, 0.0)
	pass_cooldown = maxf(pass_cooldown - delta, 0.0)
	if holder == -1:
		start_delay -= delta
		if start_delay <= 0.0:
			_give_to_random()
		return
	fuse -= delta
	var carrier := player_by_id(holder)
	if fuse <= 0.0:
		_blow_up(carrier)
		return
	if pass_cooldown > 0.0 or carrier == null:
		return
	for p in players:
		var pid := p.info.player_id
		if pid == holder or not alive.has(pid) or immune[pid] > 0.0:
			continue
		var d := Vector2(p.position.x - carrier.position.x, p.position.z - carrier.position.z).length()
		if d < PASS_RADIUS:
			immune[holder] = 0.9
			pass_cooldown = 0.35
			holder = pid
			lobby.broadcast(set_holder.bind(pid, fuse))
			set_holder(pid, fuse)
			break


func _blow_up(carrier: ArcadePlayer) -> void:
	var pid := carrier.info.player_id
	placement[alive.size() - 1] = pid
	alive.erase(pid)
	lobby.broadcast(explode.bind(pid))
	explode(pid)
	var away := Vector3(carrier.position.x, 0.0, carrier.position.z)
	if away.length() < 0.1:
		away = Vector3.RIGHT
	carrier.knock_out(away)
	holder = -1
	lobby.broadcast(set_holder.bind(-1, 0.0))
	set_holder(-1, 0.0)
	if alive.size() <= 1:
		ended = true
		placement[0] = alive[0]
		get_tree().create_timer(1.6).timeout.connect(_finish)
	else:
		start_delay = 1.3


func _finish() -> void:
	if not finished:
		finished = true
		lobby.minigame_win_by_position(placement)


func on_time_up() -> void:
	# should never be needed, but a game has to end: whoever is alive shares the win by the order of the list
	if ended:
		return
	ended = true
	var rank := 0
	for pid in alive:
		placement[rank] = pid
		rank += 1
	_finish()


# ----- the bots -----

func _ai(p: ArcadePlayer, delta: float) -> Dictionary:
	if not running or p.dead:
		return {"dir": Vector2.ZERO}
	var pid := p.info.player_id
	var here := Vector2(p.position.x, p.position.z)
	var dir := Vector2.ZERO
	if holder == pid:
		# chase the nearest player who can take the bomb
		var best := 99.0
		for other in players:
			var oid := other.info.player_id
			if oid == pid or not alive.has(oid) or immune.get(oid, 0.0) > 0.0:
				continue
			var d := here.distance_to(Vector2(other.position.x, other.position.z))
			if d < best:
				best = d
				dir = Vector2(other.position.x, other.position.z) - here
	elif holder != -1:
		var carrier := player_by_id(holder)
		if carrier:
			var away := here - Vector2(carrier.position.x, carrier.position.z)
			var dist := away.length()
			if dist < 5.0:
				dir = away.normalized()
				# do not run into the edge: slide along it
				if here.length() > ARENA - 1.8:
					var tangent := Vector2(-here.y, here.x).normalized()
					if tangent.dot(dir) < 0.0:
						tangent = -tangent
					dir = (tangent * 1.3 - here.normalized() * 0.6).normalized()
	return {"dir": dir.normalized() if dir.length() > 0.01 else Vector2.ZERO}

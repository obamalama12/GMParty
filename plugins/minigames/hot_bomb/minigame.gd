extends ArcadeGame
## Hot Bomb: one player carries a lit bomb and has to touch somebody else to pass it on. When the fuse is
## burnt up, the carrier loses a life (two lives each). Speed and shield pickups appear on the rock, and after a while
## the lava rises (the platform shrinks) and fireballs rain down. The last one standing wins.

const ARENA := 6.4
const PASS_RADIUS := 1.25
const BOMB_MESH := preload("res://assets/models/Bomb/Bomb.obj")
const HOLDER_SPEED := 1.32
const LIVES := 2
const SUDDEN_AT := 40.0            # seconds after the start: the platform shrinks and fireballs fall
const SHRINK_TIME := 22.0
const SHRINK_BY := 2.0
const PICKUP_RADIUS := 1.0
const PICKUP_LIFE := 10.0
const FIREBALL_RADIUS := 1.5

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
var elapsed := 0.0
var lives := {}                  # player id -> lives left
var pips := {}                   # player id -> Array of life markers
var shields := {}                # player id -> bool: the next explosion bounces off
var shield_nodes := {}
var last_hit := -1
var floor_body: StaticBody3D
var rim_node: MeshInstance3D
var cam: Camera3D
var cam_base := Vector3.ZERO
var shake := 0.0
var pickup_nodes := {}           # id -> Node3D (every peer)
var pickups := {}                # id -> { "type", "pos", "life" } (server)
var next_pickup_id := 0
var pickup_timer := 3.0
var fireball_nodes := {}
var fireballs := []              # server: { "id", "pos", "t" }
var fireball_timer := 2.0
var next_fireball_id := 0
var near := {}                   # player id -> was close to the carrier
var near_cooldown := {}
var sudden_announced := false


func build_world() -> void:
	make_sky(Color(0.16, 0.05, 0.22), Color(0.95, 0.38, 0.18), Color(0.2, 0.05, 0.05))
	cam = make_camera(Vector3(0, 10.5, 9.0), Vector3(0, 0.3, 0.5), 50.0)
	cam_base = cam.position
	make_music("res://assets/music/retro/volcano_panic.ogg")
	# a cracked rock platform in a lava lake, rocks and dead trees around it, and a glow from below
	floor_body = add_floor(ARENA, 3, [Color(0.26, 0.19, 0.34), Color(0.0, 0.0, 0.0), Color(0.9, 0.32, 0.06), Color(1.0, 0.45, 0.05)], 7.0)
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
	for child in get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is TorusMesh:
			rim_node = child
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
		var heat := OmniLight3D.new()
		heat.light_color = Color(1.0, 0.3, 0.05)
		heat.omni_range = 4.0
		heat.light_energy = 0.0
		marker.add_child(heat)
		marker.visible = false
		p.add_child(marker)
		markers[p.info.player_id] = marker
		immune[p.info.player_id] = 0.0
		lives[p.info.player_id] = LIVES
		shields[p.info.player_id] = false
		near[p.info.player_id] = false
		near_cooldown[p.info.player_id] = 0.0
		var pip_list := []
		for k in LIVES:
			var pip := MeshInstance3D.new()
			var ps := SphereMesh.new()
			ps.radius = 0.13
			ps.height = 0.26
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(1.0, 0.25, 0.3)
			pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ps.material = pm
			pip.mesh = ps
			pip.position = Vector3((k - (LIVES - 1) * 0.5) * 0.4, 2.3, 0)
			p.add_child(pip)
			pip_list.append(pip)
		pips[p.info.player_id] = pip_list
		var bubble := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.9
		sph.height = 1.8
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.4, 0.9, 1.0, 0.35)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sph.material = bm
		bubble.mesh = sph
		bubble.position.y = 0.85
		bubble.visible = false
		p.add_child(bubble)
		shield_nodes[p.info.player_id] = bubble


func _process(delta: float) -> void:
	var urgency := 0.0
	if holder != -1:
		urgency = clampf(1.0 - fuse / 4.0, 0.0, 1.0)
	flash_time += delta * (3.0 + (6.0 / maxf(fuse, 0.6)) * 3.0)
	for pid in markers:
		var marker: Node3D = markers[pid]
		if marker.visible:
			var mesh := marker.get_child(0) as MeshInstance3D
			var hot := 0.5 + 0.5 * sin(flash_time)
			(mesh.material_override as StandardMaterial3D).albedo_color = Color(0.12, 0.12, 0.14).lerp(Color(1.0, 0.15, 0.05), clampf(hot * 0.6 + urgency * 0.6, 0.0, 1.0))
			marker.position.y = 1.55 + 0.08 * sin(flash_time * 0.5)
			marker.scale = Vector3.ONE * (1.0 + 0.08 * hot + 0.35 * urgency)
			(marker.get_child(1) as OmniLight3D).light_energy = (0.5 + 2.5 * urgency) * (0.5 + 0.5 * hot)
	for id in pickup_nodes:
		var node: Node3D = pickup_nodes[id]
		node.rotation.y += delta * 3.0
		node.position.y = 0.9 + 0.15 * sin(flash_time * 0.6 + id)
	for id in fireball_nodes:
		var disc: Node3D = fireball_nodes[id]
		disc.scale = Vector3.ONE * (1.0 + 0.06 * sin(flash_time * 4.0))
	if cam:
		shake = maxf(shake - delta * 2.5, 0.0)
		cam.position = cam_base + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.35


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
	shake = 1.0


func on_go() -> void:
	start_delay = 0.8


func _random_fuse() -> float:
	var f := randf_range(4.0, 6.0) if alive.size() > 2 else randf_range(3.2, 4.8)
	if elapsed > SUDDEN_AT:
		f *= 0.7
	return f


func _give_to_random() -> void:
	var pool: Array[int] = alive.duplicate()
	if pool.size() > 1:
		pool.erase(last_hit)
	var target: int = pool.pick_random()
	fuse = _random_fuse()
	pass_cooldown = 0.7
	immune[target] = 0.6
	lobby.broadcast(set_holder.bind(target, fuse))
	set_holder(target, fuse)


func _arena_now() -> float:
	return ARENA - SHRINK_BY * clampf((elapsed - SUDDEN_AT) / SHRINK_TIME, 0.0, 1.0)


func world_tick(delta: float) -> void:
	elapsed += delta
	# the clients count the fuse down on their own, so the flashing speeds up in time
	if not multiplayer.is_server() and holder != -1:
		fuse = maxf(fuse - delta, 0.0)
	# the bomb makes its carrier faster the shorter the fuse gets
	if holder != -1:
		var carrier := player_by_id(holder)
		if carrier:
			carrier.speed_multiplier = HOLDER_SPEED + 0.3 * clampf(1.0 - fuse / 4.0, 0.0, 1.0)
	# the lava rises: the platform shrinks
	if elapsed > SUDDEN_AT:
		var r := _arena_now()
		var s := r / ARENA
		floor_body.scale = Vector3(s, 1.0, s)
		if rim_node:
			rim_node.scale = Vector3(s, 0.9, s)
		for p in players:
			p.arena_radius = r - 0.45


@rpc func pop_text(pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 24
	label.outline_modulate = Color(0.1, 0.03, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3(0, 2.6, 0)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _pop(pos: Vector3, text: String, color: Color) -> void:
	lobby.broadcast(pop_text.bind(pos, text, color))
	pop_text(pos, text, color)


@rpc func set_lives(player_id: int, count: int) -> void:
	lives[player_id] = count
	var list: Array = pips.get(player_id, [])
	for k in list.size():
		(list[k] as Node3D).visible = k < count


@rpc func set_shield(player_id: int, on: bool) -> void:
	shields[player_id] = on
	if shield_nodes.has(player_id):
		shield_nodes[player_id].visible = on


@rpc func spawn_pickup(id: int, type: int, pos: Vector3) -> void:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if type == 0:
		var cone := PrismMesh.new()           # a yellow bolt-ish arrow
		cone.size = Vector3(0.7, 0.9, 0.5)
		mat.albedo_color = Color(1.0, 0.9, 0.2)
		cone.material = mat
		mesh.mesh = cone
	else:
		var sph := SphereMesh.new()
		sph.radius = 0.4
		sph.height = 0.8
		mat.albedo_color = Color(0.4, 0.9, 1.0)
		sph.material = mat
		mesh.mesh = sph
	node.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = mat.albedo_color
	light.omni_range = 3.0
	node.add_child(light)
	node.position = pos + Vector3(0, 0.9, 0)
	add_child(node)
	pickup_nodes[id] = node
	node.scale = Vector3.ZERO
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


@rpc func remove_pickup(id: int, collector: int, type: int) -> void:
	var node: Node3D = pickup_nodes.get(id)
	pickup_nodes.erase(id)
	if node:
		node.queue_free()
	if collector != -1:
		sound("res://assets/sounds/arcade/pass.wav")
		var p := player_by_id(collector)
		if p:
			var color := Color(1.0, 0.9, 0.2) if type == 0 else Color(0.4, 0.9, 1.0)
			pop_text(p.position, "SPEED!" if type == 0 else "SHIELD!", color)
			if type == 1:
				set_shield(collector, true)


@rpc func warn_fireball(id: int, pos: Vector3) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = FIREBALL_RADIUS
	cyl.bottom_radius = FIREBALL_RADIUS
	cyl.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.05, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat
	disc.mesh = cyl
	disc.position = Vector3(pos.x, 0.06, pos.z)
	add_child(disc)
	fireball_nodes[id] = disc


@rpc func hit_fireball(id: int, pos: Vector3) -> void:
	var disc: Node3D = fireball_nodes.get(id)
	fireball_nodes.erase(id)
	if disc:
		disc.queue_free()
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat
	flash.mesh = sphere
	flash.position = Vector3(pos.x, 0.6, pos.z)
	add_child(flash)
	var tween := create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 3.0, 0.4)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(flash.queue_free)
	sound("res://assets/sounds/arcade/thud.wav")
	shake = maxf(shake, 0.5)


func server_tick(delta: float) -> void:
	if ended:
		return
	for pid in immune:
		immune[pid] = maxf(immune[pid] - delta, 0.0)
		near_cooldown[pid] = maxf(near_cooldown[pid] - delta, 0.0)
	pass_cooldown = maxf(pass_cooldown - delta, 0.0)
	_tick_pickups(delta)
	_tick_fireballs(delta)
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
	if carrier == null:
		return
	for p in players:
		var pid := p.info.player_id
		if pid == holder or not alive.has(pid):
			continue
		var d := Vector2(p.position.x - carrier.position.x, p.position.z - carrier.position.z).length()
		# near miss: somebody slipped away right in front of the carrier
		if d < 1.8:
			near[pid] = true
		elif near[pid] and d > 2.1:
			near[pid] = false
			if near_cooldown[pid] <= 0.0 and immune[pid] <= 0.0:
				near_cooldown[pid] = 2.0
				_pop(p.position, "CLOSE!", Color(1.0, 0.85, 0.3))
		if pass_cooldown > 0.0 or immune[pid] > 0.0:
			continue
		if d < PASS_RADIUS:
			immune[holder] = 0.9
			pass_cooldown = 0.35
			holder = pid
			lobby.broadcast(set_holder.bind(pid, fuse))
			set_holder(pid, fuse)
			_pop(p.position, "TAG!", Color(1.0, 0.4, 0.2))
			break


func _tick_pickups(delta: float) -> void:
	pickup_timer -= delta
	if pickup_timer <= 0.0 and pickups.size() < 2 and holder != -1:
		pickup_timer = randf_range(5.0, 7.5)
		var ang := randf() * TAU
		var r := sqrt(randf()) * (_arena_now() - 1.2)
		var pos := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var type := 0 if randf() < 0.5 else 1
		var id := next_pickup_id
		next_pickup_id += 1
		pickups[id] = {"type": type, "pos": pos, "life": PICKUP_LIFE}
		lobby.broadcast(spawn_pickup.bind(id, type, pos))
		spawn_pickup(id, type, pos)
	for id in pickups.keys():
		var info: Dictionary = pickups[id]
		info.life -= delta
		var taker: ArcadePlayer = null
		for p in players:
			if alive.has(p.info.player_id) and not p.dead and Vector2(p.position.x - info.pos.x, p.position.z - info.pos.z).length() < PICKUP_RADIUS:
				taker = p
				break
		if taker == null and info.life > 0.0:
			continue
		pickups.erase(id)
		if taker == null:
			lobby.broadcast(remove_pickup.bind(id, -1, info.type))
			remove_pickup(id, -1, info.type)
			continue
		var tid := taker.info.player_id
		lobby.broadcast(remove_pickup.bind(id, tid, info.type))
		remove_pickup(id, tid, info.type)
		if info.type == 0:
			taker.boost(3.5)


func _tick_fireballs(delta: float) -> void:
	if elapsed > SUDDEN_AT:
		if not sudden_announced:
			sudden_announced = true
			announce("SUDDEN DEATH!", Color(1.0, 0.3, 0.15), 1.0)
		fireball_timer -= delta
		if fireball_timer <= 0.0 and holder != -1 and alive.size() > 0:
			fireball_timer = randf_range(1.2, 2.0)
			var victim := player_by_id(alive.pick_random())
			var pos := Vector3(victim.position.x, 0, victim.position.z) + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
			var id := next_fireball_id
			next_fireball_id += 1
			fireballs.append({"id": id, "pos": pos, "t": 1.3})
			lobby.broadcast(warn_fireball.bind(id, pos))
			warn_fireball(id, pos)
	for fb in fireballs.duplicate():
		fb.t -= delta
		if fb.t > 0.0:
			continue
		fireballs.erase(fb)
		lobby.broadcast(hit_fireball.bind(fb.id, fb.pos))
		hit_fireball(fb.id, fb.pos)
		for p in players:
			var pid := p.info.player_id
			if not alive.has(pid) or p.dead:
				continue
			if Vector2(p.position.x - fb.pos.x, p.position.z - fb.pos.z).length() < FIREBALL_RADIUS:
				if shields[pid]:
					lobby.broadcast(set_shield.bind(pid, false))
					set_shield(pid, false)
					_pop(p.position, "BLOCKED!", Color(0.4, 0.9, 1.0))
				else:
					p.stun(1.1)


func _blow_up(carrier: ArcadePlayer) -> void:
	var pid := carrier.info.player_id
	lobby.broadcast(explode.bind(pid))
	explode(pid)
	# a shield eats the blast and the bomb jumps to the nearest player with a shorter fuse
	if shields[pid] and alive.size() > 1:
		lobby.broadcast(set_shield.bind(pid, false))
		set_shield(pid, false)
		_pop(carrier.position, "BLOCKED!", Color(0.4, 0.9, 1.0))
		var best := -1
		var best_d := INF
		for p in players:
			var oid := p.info.player_id
			if oid == pid or not alive.has(oid):
				continue
			var d := p.position.distance_to(carrier.position)
			if d < best_d:
				best_d = d
				best = oid
		immune[pid] = 1.5
		pass_cooldown = 0.6
		immune[best] = 0.3
		fuse = _random_fuse() * 0.7
		holder = best
		lobby.broadcast(set_holder.bind(best, fuse))
		set_holder(best, fuse)
		return
	lives[pid] -= 1
	lobby.broadcast(set_lives.bind(pid, lives[pid]))
	set_lives(pid, lives[pid])
	holder = -1
	lobby.broadcast(set_holder.bind(-1, 0.0))
	set_holder(-1, 0.0)
	if lives[pid] > 0:
		# hurt, not out: stunned for a moment, and the next bomb goes to somebody else
		carrier.stun(1.3)
		last_hit = pid
		immune[pid] = 2.5
		start_delay = 1.4
		_pop(carrier.position, "OUCH!", Color(1.0, 0.3, 0.3))
		return
	placement[alive.size() - 1] = pid
	alive.erase(pid)
	last_hit = -1
	var away := Vector3(carrier.position.x, 0.0, carrier.position.z)
	if away.length() < 0.1:
		away = Vector3.RIGHT
	carrier.knock_out(away)
	if alive.size() <= 1:
		ended = true
		placement[0] = alive[0]
		var champ := player_by_id(alive[0])
		if champ:
			champ.show_animation("happy")
		announce("%s WINS!" % champ.info.name.to_upper() if champ else "WINNER!", Color(1.0, 0.88, 0.25), 1.3)
		get_tree().create_timer(2.2).timeout.connect(_finish)
	else:
		start_delay = 1.3


func _finish() -> void:
	if not finished:
		finished = true
		lobby.minigame_win_by_position(placement)


func on_time_up() -> void:
	# whoever has the most lives left is ahead; a game has to end
	if ended:
		return
	ended = true
	var order: Array[int] = alive.duplicate()
	order.sort_custom(func(a, b): return lives[a] > lives[b])
	var rank := 0
	for pid in order:
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
	# get out of a fireball's circle first
	for fb in fireballs:
		var c := Vector2(fb.pos.x, fb.pos.z)
		if here.distance_to(c) < FIREBALL_RADIUS + 0.6 and not shields[pid]:
			var out := here - c
			dir = out.normalized() if out.length() > 0.05 else Vector2.RIGHT
			return {"dir": _keep_inside(here, dir)}
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
			if dist < 3.3:
				dir = away.normalized()
				# do not run into the edge: slide along it
				if here.length() > _arena_now() - 1.8:
					var tangent := Vector2(-here.y, here.x).normalized()
					if tangent.dot(dir) < 0.0:
						tangent = -tangent
					dir = (tangent * 1.3 - here.normalized() * 0.6).normalized()
			else:
				# far enough from the bomb: collect a pickup
				var best := 99.0
				for id in pickups:
					var pk: Dictionary = pickups[id]
					var pp := Vector2(pk.pos.x, pk.pos.z)
					var d := here.distance_to(pp)
					# not through the carrier
					if d < best and pp.distance_to(Vector2(carrier.position.x, carrier.position.z)) > 2.5:
						best = d
						dir = pp - here
				if dir == Vector2.ZERO and dist < 5.0:
					dir = away.normalized()
					if here.length() > _arena_now() - 1.8:
						dir = -here.normalized()
	return {"dir": dir.normalized() if dir.length() > 0.01 else Vector2.ZERO}


func _keep_inside(here: Vector2, dir: Vector2) -> Vector2:
	if here.length() > _arena_now() - 1.0 and here.normalized().dot(dir) > 0.0:
		var tangent := Vector2(-here.y, here.x).normalized()
		return tangent if tangent.dot(dir) >= 0.0 else -tangent
	return dir

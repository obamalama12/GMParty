extends ArcadeGame
## Cookie Catch: cookies rain from the sky, catch as many as you can. Golden cookies are worth three, bombs stun you.

const ARENA := 7.0
const FALL_SPEED := 6.5
const START_HEIGHT := 9.5
const CATCH_HEIGHT := 1.35
const CATCH_RADIUS := 0.85
const COOKIE_TEXTURE := preload("res://common/scenes/board_logic/controller/icons/cookie.png")
const BOMB_MESH := preload("res://assets/models/Bomb/Bomb.obj")

enum Kind { COOKIE, GOLD, BOMB }

var items := {}              # id -> { "node": Node3D, "shadow": MeshInstance3D, "kind": int, "age": float, "x": float, "z": float }
var next_id := 0
var spawn_timer := 0.0
var scores := {}             # player id -> score, kept by the server
var ai_targets := {}         # player id -> { "id": item id, "time": float }


func build_world() -> void:
	make_sky(Color(0.35, 0.62, 0.95), Color(0.85, 0.93, 1.0), Color(0.5, 0.7, 0.4))
	make_camera(Vector3(0, 12.2, 10.6), Vector3(0, 0.4, 0.6), 50.0)
	make_music("res://assets/music/minigames/harvest food.ogg")
	# a picnic: the checked cloth in the middle of a mown lawn, a fence and a row of trees behind it
	add_floor(ARENA, 2, [Color(0.52, 0.80, 0.34), Color(0.45, 0.73, 0.29), Color(0.90, 0.22, 0.22), Color(0.96, 0.82, 0.45)], 14.0)
	fence_arc(ARENA + 0.9, 196.0, 344.0, 15)
	arc_props(["Bush_Large_Flowers", "Bush_Flowers"], 13, ARENA + 1.7, 200.0, 340.0, 1.0, 1.25, -0.1, 3, 0.15)
	arc_props(["NormalTree_1", "NormalTree_3", "NormalTree_5", "BirchTree_2"], 9, ARENA + 4.2, 205.0, 335.0, 1.3, 1.7, -0.4, 4, 0.5)
	arc_props(["NormalTree_2", "NormalTree_4", "BirchTree_4"], 7, ARENA + 8.0, 212.0, 328.0, 1.6, 2.1, -0.6, 5, 0.8)
	arc_props(["Flower_2_Clump", "Flower_4_Clump"], 14, ARENA - 0.9, 190.0, 350.0, 1.3, 1.8, 0.0, 6, 0.1)
	pole_ring(ARENA + 0.2, 8, 2.2, Color(0.95, 0.95, 0.95), Color(0.95, 0.25, 0.3), Color(1.0, 0.85, 0.25), 200.0, 340.0)
	var corners := [Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(-3, 0, 3), Vector3(3, 0, 3)]
	for i in players.size():
		var p := players[i]
		p.position = corners[i]
		p.speed = 5.4
		p.arena_radius = ARENA - 0.4
		p.ai_brain = _ai
		scores[p.info.player_id] = 0


func on_go() -> void:
	spawn_timer = 0.4


func _make_item(kind: int) -> Node3D:
	var root := Node3D.new()
	if kind == Kind.BOMB:
		var m := MeshInstance3D.new()
		m.mesh = BOMB_MESH
		m.scale = Vector3.ONE * 0.2
		root.add_child(m)
	else:
		var s := Sprite3D.new()
		s.texture = COOKIE_TEXTURE
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 0.016 if kind == Kind.COOKIE else 0.022
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.shaded = false
		if kind == Kind.GOLD:
			s.modulate = Color(1.0, 0.85, 0.2)
		root.add_child(s)
	return root


@rpc func spawn_item(id: int, kind: int, x: float, z: float) -> void:
	var node := _make_item(kind)
	node.position = Vector3(x, START_HEIGHT, z)
	add_child(node)
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.05, 0.2, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = mat
	shadow.mesh = disc
	shadow.position = Vector3(x, 0.03, z)
	add_child(shadow)
	items[id] = {"node": node, "shadow": shadow, "kind": kind, "age": 0.0, "x": x, "z": z}


@rpc func remove_item(id: int, caught: bool) -> void:
	var item = items.get(id)
	if item == null:
		return
	if caught and item.kind == Kind.BOMB:
		_boom(item.node.global_position)
	items.erase(id)
	item.node.queue_free()
	item.shadow.queue_free()
	if caught and item.kind != Kind.BOMB:
		sound("res://assets/sounds/correct.wav")


func _boom(at: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.15, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat
	flash.mesh = sphere
	flash.position = at
	add_child(flash)
	var tween := create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 3.2, 0.35)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(flash.queue_free)
	sound("res://assets/sounds/arcade/boom.wav")


func world_tick(delta: float) -> void:
	for id in items.keys():
		var item = items[id]
		item.age += delta
		var y: float = START_HEIGHT - FALL_SPEED * item.age
		item.node.position.y = y
		if item.kind == Kind.BOMB:
			item.node.rotation.y += delta * 3.0
		# the shadow on the floor grows as the item comes down
		var closeness := clampf(1.0 - (y - CATCH_HEIGHT) / START_HEIGHT, 0.0, 1.0)
		var mat := (item.shadow.mesh as CylinderMesh).material as StandardMaterial3D
		mat.albedo_color.a = closeness * 0.55
		if item.kind == Kind.BOMB:
			mat.albedo_color = Color(0.9, 0.1, 0.1, closeness * 0.6)
		item.shadow.scale = Vector3.ONE * (0.6 + closeness * 0.7)
		if y < -1.0 and not multiplayer.is_server():
			items.erase(id)
			item.node.queue_free()
			item.shadow.queue_free()


func server_tick(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		var progress := 1.0 - time_left / duration
		spawn_timer = lerpf(0.55, 0.26, progress)
		var roll := randf()
		var kind := Kind.COOKIE
		if roll < 0.16:
			kind = Kind.BOMB
		elif roll < 0.26:
			kind = Kind.GOLD
		var ang := randf() * TAU
		var r := sqrt(randf()) * (ARENA - 1.0)
		var x := cos(ang) * r
		var z := sin(ang) * r
		var id := next_id
		next_id += 1
		lobby.broadcast(spawn_item.bind(id, kind, x, z))
		spawn_item(id, kind, x, z)
	for id in items.keys():
		var item = items[id]
		var y: float = START_HEIGHT - FALL_SPEED * item.age
		if y > CATCH_HEIGHT:
			continue
		var taken := false
		for p in players:
			if p.dead:
				continue
			if Vector2(p.position.x - item.x, p.position.z - item.z).length() < CATCH_RADIUS:
				_caught(p, item.kind)
				taken = true
				break
		if taken or y < 0.0:
			lobby.broadcast(remove_item.bind(id, taken))
			remove_item(id, taken)


func _caught(p: ArcadePlayer, kind: int) -> void:
	var pid := p.info.player_id
	match kind:
		Kind.COOKIE:
			scores[pid] += 1
		Kind.GOLD:
			scores[pid] += 3
		Kind.BOMB:
			scores[pid] = maxi(scores[pid] - 2, 0)
			p.stun(1.3)
	$Screen/ScoreOverlay.set_score(pid, scores[pid])


func on_time_up() -> void:
	var points := []
	for p in players:
		points.append(scores[p.info.player_id])
	finish_by_points(points)


# ----- the bots -----

func _ai(p: ArcadePlayer, delta: float) -> Dictionary:
	if not running:
		return {"dir": Vector2.ZERO}
	var pid := p.info.player_id
	var memory: Dictionary = ai_targets.get(pid, {"id": -1, "time": 0.0})
	memory.time -= delta
	var refresh := 0.25
	match p.info.ai_difficulty:
		Lobby.Difficulty.EASY:
			refresh = 0.9
		Lobby.Difficulty.NORMAL:
			refresh = 0.5
	var here := Vector2(p.position.x, p.position.z)
	# keep away from bombs that are about to land close by
	var flee := Vector2.ZERO
	for id in items:
		var item = items[id]
		if item.kind == Kind.BOMB:
			var d := Vector2(item.x, item.z) - here
			if d.length() < 2.0 and START_HEIGHT - FALL_SPEED * item.age < 6.0:
				flee -= d.normalized() * (2.0 - d.length())
	if memory.time <= 0.0 or not items.has(memory.id):
		memory.time = refresh
		var best := -1
		var best_value := 0.0
		for id in items:
			var item = items[id]
			if item.kind == Kind.BOMB:
				continue
			var land_in: float = (START_HEIGHT - FALL_SPEED * item.age - CATCH_HEIGHT) / FALL_SPEED
			var dist := Vector2(item.x, item.z).distance_to(here)
			if dist / p.speed > land_in + 0.25:
				continue
			# leave a cookie to somebody who is clearly closer, so the bots spread out
			var rival_closer := false
			for other in players:
				if other != p and not other.dead and Vector2(other.position.x, other.position.z).distance_to(Vector2(item.x, item.z)) < dist - 0.9:
					rival_closer = true
					break
			if rival_closer:
				continue
			var value := (3.0 if item.kind == Kind.GOLD else 1.0) / (dist + 1.0)
			if value > best_value:
				best_value = value
				best = id
		memory.id = best
	ai_targets[pid] = memory
	var dir := Vector2.ZERO
	if memory.id != -1 and items.has(memory.id):
		var item = items[memory.id]
		var to := Vector2(item.x, item.z) - here
		if to.length() > 0.25:
			dir = to.normalized()
	return {"dir": (dir + flee * 0.8).limit_length(1.0)}

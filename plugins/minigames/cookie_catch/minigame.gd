extends ArcadeGame
## Cookie Catch: cookies rain from the sky, catch as many as you can. Golden cookies are worth three, bombs stun you,
## stars make you fast, magnets pull cookies in, shields block a bomb. Consecutive catches build a combo, a golden rain
## falls in the middle of the game, the last seconds are a cookie storm and fast players can steal cookies by bumping.

const ARENA := 7.0
const FALL_SPEED := 6.5
const START_HEIGHT := 9.5
const CATCH_HEIGHT := 1.35
const CATCH_RADIUS := 0.85
const COOKIE_TEXTURE := preload("res://common/scenes/board_logic/controller/icons/cookie.png")
const BOMB_MESH := preload("res://assets/models/Bomb/Bomb.obj")

enum Kind { COOKIE, GOLD, BOMB, STAR, MAGNET, SHIELD }

const STORM_TIME := 14.0       # seconds left when the storm starts
const RAIN_TIME := 37.0        # seconds left when the golden rain starts
const RAIN_LENGTH := 5.0
const MAGNET_TIME := 7.0
const MAGNET_RADIUS := 2.1
const COMBO_WINDOW := 2.2
const STEAL_COOLDOWN := 2.0
var storm := false
var rain_left := 0.0
var rain_done := false
var combo := {}              # player id -> consecutive catches (server)
var combo_time := {}         # player id -> seconds left to continue the combo (server)
var magnet := {}             # player id -> seconds of magnet left (server)
var shield := {}             # player id -> bool (server)
var last_pos := {}           # player id -> Vector2 (server)
var speed_of := {}           # player id -> measured speed (server)
var steal_cd := {}           # "a_b" -> seconds (server)
var fx := {}                 # player id -> { "shield": Node3D, "magnet": Node3D } (every peer)

var items := {}              # id -> { "node": Node3D, "shadow": MeshInstance3D, "kind": int, "age": float, "x": float, "z": float }
var next_id := 0
var spawn_timer := 0.0
var scores := {}             # player id -> score, kept by the server
var ai_targets := {}         # player id -> { "id": item id, "time": float }


func build_world() -> void:
	make_sky(Color(0.35, 0.62, 0.95), Color(0.85, 0.93, 1.0), Color(0.5, 0.7, 0.4))
	make_camera(Vector3(0, 12.2, 10.6), Vector3(0, 0.4, 0.6), 50.0)
	make_music("res://assets/music/retro/cookie_rush.ogg")
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
		var pid := p.info.player_id
		scores[pid] = 0
		combo[pid] = 0
		combo_time[pid] = 0.0
		magnet[pid] = 0.0
		shield[pid] = false
		speed_of[pid] = 0.0
		last_pos[pid] = Vector2(p.position.x, p.position.z)


func on_go() -> void:
	spawn_timer = 0.4
	storm = false
	rain_done = false
	rain_left = 0.0


static var _star_tex: ImageTexture

# A little pixel-art star: bright cyan with a dark blue outline
func _star_texture() -> ImageTexture:
	if _star_tex:
		return _star_tex
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var pts := PackedVector2Array()
	for i in 10:
		var r := 22.0 if i % 2 == 0 else 9.5
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(Vector2(24.0 + cos(a) * r, 25.0 + sin(a) * r))
	for y in size:
		for x in size:
			var v := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(v, pts):
				var inner := Geometry2D.offset_polygon(pts, -3.0)
				var core := false
				for poly in inner:
					if Geometry2D.is_point_in_polygon(v, poly):
						core = true
				img.set_pixel(x, y, Color(0.45, 0.95, 1.0) if core else Color(0.1, 0.2, 0.6))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_item(kind: int) -> Node3D:
	var root := Node3D.new()
	if kind == Kind.MAGNET:
		var t := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.16
		torus.outer_radius = 0.38
		torus.material = toon(Color(0.95, 0.15, 0.2))
		t.mesh = torus
		t.rotation.x = PI / 2.0
		root.add_child(t)
		var tip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 0.14, 0.14)
		box.material = toon(Color(0.9, 0.9, 0.95))
		tip.mesh = box
		tip.position.y = -0.28
		root.add_child(tip)
	elif kind == Kind.SHIELD:
		var b := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.38
		sph.height = 0.76
		sph.material = _glow(Color(0.3, 0.6, 1.0, 0.65))
		b.mesh = sph
		root.add_child(b)
		var core := MeshInstance3D.new()
		var cs := SphereMesh.new()
		cs.radius = 0.18
		cs.height = 0.36
		cs.material = _glow(Color(0.9, 1.0, 1.0, 1.0))
		core.mesh = cs
		root.add_child(core)
	elif kind == Kind.BOMB:
		var m := MeshInstance3D.new()
		m.mesh = BOMB_MESH
		m.scale = Vector3.ONE * 0.2
		root.add_child(m)
	elif kind == Kind.STAR:
		var star := Sprite3D.new()
		star.texture = _star_texture()
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.pixel_size = 0.014
		star.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		star.shaded = false
		root.add_child(star)
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
	if caught and item.kind != Kind.BOMB:
		sound("res://assets/sounds/correct.wav")
		_burst(item.node.global_position, _kind_color(item.kind))
	item.node.queue_free()
	item.shadow.queue_free()


func _kind_color(kind: int) -> Color:
	match kind:
		Kind.GOLD:
			return Color(1.0, 0.85, 0.2)
		Kind.STAR:
			return Color(0.45, 0.95, 1.0)
		Kind.MAGNET:
			return Color(1.0, 0.3, 0.3)
		Kind.SHIELD:
			return Color(0.4, 0.7, 1.0)
	return Color(0.85, 0.6, 0.3)


func _burst(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.material = _glow(color)
	p.mesh = mesh
	p.amount = 12
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -12, 0)
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


@rpc func popup(at: Vector3, text: String, color: Color, big := false) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.012 if big else 0.008
	label.font_size = 96
	label.outline_size = 24
	label.modulate = color
	label.outline_modulate = Color(0.1, 0.05, 0.3)
	label.position = at + Vector3(0, 1.4, 0)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + (1.9 if big else 1.3), 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)


func _show_popup(at: Vector3, text: String, color: Color, big := false) -> void:
	lobby.broadcast(popup.bind(at, text, color, big))
	popup(at, text, color, big)


## Shows the shield bubble and the magnet ring around a player on every peer.
@rpc func set_status(pid: int, has_shield: bool, has_magnet: bool) -> void:
	var p := player_by_id(pid)
	if p == null:
		return
	var entry: Dictionary = fx.get(pid, {})
	if has_shield and not entry.has("shield"):
		var b := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.95
		sph.height = 1.9
		sph.material = _glow(Color(0.35, 0.65, 1.0, 0.28))
		b.mesh = sph
		b.position.y = 0.9
		p.add_child(b)
		entry["shield"] = b
	elif not has_shield and entry.has("shield"):
		entry["shield"].queue_free()
		entry.erase("shield")
	if has_magnet and not entry.has("magnet"):
		var r := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = MAGNET_RADIUS - 0.08
		torus.outer_radius = MAGNET_RADIUS
		torus.material = _glow(Color(1.0, 0.3, 0.35, 0.45))
		r.mesh = torus
		r.position.y = 0.08
		p.add_child(r)
		entry["magnet"] = r
	elif not has_magnet and entry.has("magnet"):
		entry["magnet"].queue_free()
		entry.erase("magnet")
	fx[pid] = entry


func _sync_status(pid: int) -> void:
	lobby.broadcast(set_status.bind(pid, shield[pid], magnet[pid] > 0.0))
	set_status(pid, shield[pid], magnet[pid] > 0.0)


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
	for pid in fx:
		var entry: Dictionary = fx[pid]
		if entry.has("magnet") and is_instance_valid(entry["magnet"]):
			var s := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.06
			entry["magnet"].scale = Vector3(s, 1.0, s)
	for id in items.keys():
		var item = items[id]
		item.age += delta
		var y: float = START_HEIGHT - FALL_SPEED * item.age
		item.node.position.y = y
		if item.kind == Kind.BOMB or item.kind == Kind.MAGNET or item.kind == Kind.SHIELD:
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
	if not storm and time_left <= STORM_TIME:
		storm = true
		rain_left = 0.0
		announce("COOKIE STORM!", Color(1.0, 0.75, 0.2), 1.3)
	if not rain_done and not storm and time_left <= RAIN_TIME:
		rain_done = true
		rain_left = RAIN_LENGTH
		announce("GOLDEN RAIN!", Color(1.0, 0.85, 0.2), 1.1)
	rain_left = maxf(rain_left - delta, 0.0)
	_tick_players(delta)
	if spawn_timer <= 0.0:
		var progress := 1.0 - time_left / duration
		spawn_timer = lerpf(0.55, 0.3, progress)
		if storm:
			spawn_timer *= 0.42
		var roll := randf()
		var kind := Kind.COOKIE
		if rain_left > 0.0:
			spawn_timer *= 0.5
			kind = Kind.GOLD if roll < 0.7 else Kind.COOKIE
		elif roll < (0.13 if storm else 0.16):
			kind = Kind.BOMB
		elif roll < (0.13 if storm else 0.16) + (0.25 if storm else 0.10):
			kind = Kind.GOLD
		elif roll > 0.955:
			kind = Kind.STAR
		elif roll > 0.93:
			kind = Kind.MAGNET
		elif roll > 0.905:
			kind = Kind.SHIELD
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
			var reach := MAGNET_RADIUS if magnet[p.info.player_id] > 0.0 and item.kind != Kind.BOMB else CATCH_RADIUS
			if Vector2(p.position.x - item.x, p.position.z - item.z).length() < reach:
				_caught(p, item.kind, Vector3(item.x, 0.0, item.z))
				taken = true
				break
		if taken or y < 0.0:
			lobby.broadcast(remove_item.bind(id, taken))
			remove_item(id, taken)


func _same_team(a: ArcadePlayer, b: ArcadePlayer) -> bool:
	if lobby.minigame_state.minigame_type != Lobby.MINIGAME_TYPES.TWO_VS_TWO:
		return false
	return players.find(a) / 2 == players.find(b) / 2


## Combos, power-up timers and the bump-to-steal rule.
func _tick_players(delta: float) -> void:
	for p in players:
		var pid := p.info.player_id
		var here := Vector2(p.position.x, p.position.z)
		speed_of[pid] = lerpf(speed_of[pid], here.distance_to(last_pos[pid]) / maxf(delta, 0.0001), 0.3)
		last_pos[pid] = here
		if combo_time[pid] > 0.0:
			combo_time[pid] -= delta
			if combo_time[pid] <= 0.0:
				combo[pid] = 0
		if magnet[pid] > 0.0:
			magnet[pid] -= delta
			if magnet[pid] <= 0.0:
				_sync_status(pid)
	for key in steal_cd.keys():
		steal_cd[key] -= delta
		if steal_cd[key] <= 0.0:
			steal_cd.erase(key)
	for i in players.size():
		for j in range(i + 1, players.size()):
			var a := players[i]
			var b := players[j]
			if a.dead or b.dead or _same_team(a, b):
				continue
			if Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length() > 1.0:
				continue
			var key := "%d_%d" % [i, j]
			if steal_cd.has(key):
				continue
			var ia := a.info.player_id
			var ib := b.info.player_id
			var thief := a
			var victim := b
			if speed_of[ib] > speed_of[ia]:
				thief = b
				victim = a
			var ti := thief.info.player_id
			var vi := victim.info.player_id
			if speed_of[ti] < 2.0 or speed_of[ti] < speed_of[vi] + 0.8 or scores[vi] <= 0:
				continue
			steal_cd[key] = STEAL_COOLDOWN
			var mid := (thief.position + victim.position) / 2.0
			if shield[vi]:
				shield[vi] = false
				_sync_status(vi)
				_show_popup(victim.position, "BLOCKED!", Color(0.5, 0.8, 1.0))
				continue
			scores[vi] -= 1
			scores[ti] += 1
			combo[vi] = 0
			_show_popup(mid, "STOLEN +1", Color(1.0, 0.45, 0.8), true)
			$Screen/ScoreOverlay.set_score(ti, scores[ti])
			$Screen/ScoreOverlay.set_score(vi, scores[vi])


func _caught(p: ArcadePlayer, kind: int, at: Vector3) -> void:
	var pid := p.info.player_id
	match kind:
		Kind.COOKIE, Kind.GOLD:
			combo[pid] += 1
			combo_time[pid] = COMBO_WINDOW
			var bonus := mini(combo[pid] / 5, 3)
			var gain := (1 if kind == Kind.COOKIE else 3) + bonus
			scores[pid] += gain
			var text := "+%d" % gain
			if bonus > 0:
				text += "  x%d" % combo[pid]
			_show_popup(at, text, Color(1.0, 0.85, 0.2) if kind == Kind.GOLD else Color(1, 1, 1), kind == Kind.GOLD or bonus > 0)
			if combo[pid] % 5 == 0:
				_show_popup(p.position + Vector3(0, 0.6, 0), "COMBO!", Color(1.0, 0.5, 0.2), true)
		Kind.BOMB:
			if shield[pid]:
				shield[pid] = false
				_sync_status(pid)
				_show_popup(p.position, "BLOCKED!", Color(0.5, 0.8, 1.0), true)
			else:
				var lost := mini(scores[pid], 2)
				scores[pid] -= lost
				combo[pid] = 0
				p.stun(1.3)
				_show_popup(p.position, "-%d" % lost, Color(1.0, 0.3, 0.3), true)
		Kind.STAR:
			p.boost(5.0)
			_show_popup(p.position, "SPEED!", Color(0.45, 0.95, 1.0), true)
		Kind.MAGNET:
			magnet[pid] = MAGNET_TIME
			_sync_status(pid)
			_show_popup(p.position, "MAGNET!", Color(1.0, 0.4, 0.4), true)
		Kind.SHIELD:
			shield[pid] = true
			_sync_status(pid)
			_show_popup(p.position, "SHIELD!", Color(0.5, 0.8, 1.0), true)
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
			var worth := 3.0 if item.kind == Kind.GOLD else (2.0 if item.kind != Kind.COOKIE else 1.0)
			var value := worth / (dist + 1.0)
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

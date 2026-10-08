extends ArcadeGame
## Color Clash: a floor of coloured tiles. A colour is called, everybody runs onto a tile of that colour and when the
## time is up every other tile drops away. Every round is faster. The last player standing wins.

const GRID := 6
const TILE := 2.0
const COLORS := [Color(0.93, 0.28, 0.30), Color(0.30, 0.52, 0.96), Color(0.34, 0.80, 0.42), Color(0.99, 0.85, 0.25), Color(0.72, 0.42, 0.92), Color(0.08, 0.06, 0.1)]
const COLOR_NAMES := ["RED", "BLUE", "GREEN", "YELLOW", "PURPLE"]
const TRAP := 5                 # colour index of a trap tile (never a safe tile)
const FALL_Y := -2.5
const DROP_HOLD := 1.5          # seconds the floor stays gone
const BREAK := 1.0              # pause after the floor is back
const POWER_RADIUS := 1.0

enum Phase { START, THINK, DROP, BREAK }
enum Kind { NORMAL, RARE, TRAPS, DOUBLE, SHRINK, QUICK }

var tiles: Array = []           # { "body", "shape", "mesh", "mat", "color": int, "pos": Vector3, "idx": int, "gone": bool }
var target := 0
var kind := Kind.NORMAL
var think_total := 3.0
var phase := Phase.START
var phase_left := 0.0
var round_number := 0
var survived := {}              # player id -> rounds survived, kept by the server
var alive := {}                 # player id -> bool, kept by the server
var shields := {}               # player id -> bool: survives the next drop
var shield_nodes := {}
var ended := false
var call_label: Label
var lights: Array[OmniLight3D] = []
var pulse := 0.0
var power_tile := -1            # index of the tile with the shield star, -1 = none
var power_node: Node3D
var traps: Array = []           # tile indices of this round's trap tiles
var traps_permanent := false
var traps_dropped := true
var double_pending := false
var shrink_stage := 0


func _tile_layer(idx: int) -> int:
	var ix := idx / GRID
	var iz := idx % GRID
	return mini(mini(ix, GRID - 1 - ix), mini(iz, GRID - 1 - iz))


func _active() -> Array:
	var out: Array = []
	for t in tiles:
		if not t.gone:
			out.append(t.idx)
	return out


func build_world() -> void:
	make_sky(Color(0.10, 0.07, 0.25), Color(0.45, 0.20, 0.55), Color(0.05, 0.03, 0.12))
	make_camera(Vector3(0, 12.2, 9.6), Vector3(0, 0, 0.1), 50.0)
	make_music("res://assets/music/retro/disco_floor.ogg")
	# a dark void under the floor with a glowing haze
	var void_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 40.0
	disc.bottom_radius = 40.0
	disc.height = 0.1
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.25, 0.08, 0.45)
	vm.emission_enabled = true
	vm.emission = Color(0.35, 0.1, 0.65)
	vm.emission_energy_multiplier = 0.7
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = vm
	void_mesh.mesh = disc
	void_mesh.position.y = -7.0
	add_child(void_mesh)
	# the floor
	var floor_holder := Node3D.new()
	add_child(floor_holder)
	for ix in GRID:
		for iz in GRID:
			var body := StaticBody3D.new()
			var pos := Vector3((ix - (GRID - 1) * 0.5) * TILE, -0.15, (iz - (GRID - 1) * 0.5) * TILE)
			body.position = pos
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(TILE - 0.1, 0.3, TILE - 0.1)
			shape.shape = box
			body.add_child(shape)
			var mesh := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(TILE - 0.1, 0.3, TILE - 0.1)
			var mat := toon(COLORS[0])
			mat.emission_enabled = true
			bm.material = mat
			mesh.mesh = bm
			body.add_child(mesh)
			floor_holder.add_child(body)
			tiles.append({"body": body, "shape": shape, "mesh": mesh, "mat": mat, "color": 0, "pos": pos, "idx": tiles.size(), "gone": false})
	# disco lights circling over the floor
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = COLORS[i]
		l.light_energy = 1.3
		l.omni_range = 11.0
		l.position = Vector3(0, 4.5, 0)
		add_child(l)
		lights.append(l)
	# the shield star that waits on a tile in some rounds
	power_node = Node3D.new()
	var star := MeshInstance3D.new()
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.7, 0.7, 0.7)
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1.0, 0.85, 0.2)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1.0, 0.8, 0.1)
	star_mat.emission_energy_multiplier = 1.5
	star_mesh.material = star_mat
	star.mesh = star_mesh
	star.rotation = Vector3(0.6, 0.0, 0.6)
	power_node.add_child(star)
	var star_light := OmniLight3D.new()
	star_light.light_color = Color(1.0, 0.85, 0.3)
	star_light.omni_range = 3.5
	power_node.add_child(star_light)
	power_node.visible = false
	add_child(power_node)
	# HUD: the called colour
	call_label = Label.new()
	call_label.theme_type_variation = &"HeaderLarge"
	call_label.add_theme_font_size_override("font_size", 54)
	call_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.3))
	call_label.add_theme_constant_override("outline_size", 16)
	call_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	call_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	call_label.offset_left = -400
	call_label.offset_right = 400
	call_label.offset_top = 78
	call_label.offset_bottom = 150
	$Screen.add_child(call_label)
	var spots := [tiles[GRID * 1 + 1].pos, tiles[GRID * 4 + 1].pos, tiles[GRID * 1 + 4].pos, tiles[GRID * 4 + 4].pos]
	for i in players.size():
		var p := players[i]
		p.position = spots[i] + Vector3(0, 0.25, 0)
		p.speed = 5.4
		p.ai_brain = _ai
		survived[p.info.player_id] = 0
		alive[p.info.player_id] = true
		shields[p.info.player_id] = false
		var bubble := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.85
		sph.height = 1.7
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.4, 0.9, 1.0, 0.35)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sph.material = bm
		bubble.mesh = sph
		bubble.position.y = 0.8
		bubble.visible = false
		p.add_child(bubble)
		shield_nodes[p.info.player_id] = bubble
	var all: Array = []
	for t in tiles:
		all.append(t.idx)
	var first := _plan_colors(all, [], -1, Kind.NORMAL)
	_recolor(first.colors, first.called)
	call_label.text = ""


## Picks the colours of the tiles. `active` are the tile indices still in the game, `trap_list` become trap tiles.
## Returns { "colors": Array (36 ints, -1 for tiles that are gone), "called": int }.
func _plan_colors(active: Array, trap_list: Array, want_called: int, round_kind: int) -> Dictionary:
	var colors: Array = []
	colors.resize(GRID * GRID)
	colors.fill(-1)
	var bag: Array = []
	for i in active.size():
		bag.append(i % 5)
	bag.shuffle()
	for i in active.size():
		colors[active[i]] = bag[i]
	for idx in trap_list:
		colors[idx] = TRAP
	# which colours can be called? the ones on at least one safe tile
	var counts := [0, 0, 0, 0, 0]
	for idx in active:
		if colors[idx] >= 0 and colors[idx] < 5:
			counts[colors[idx]] += 1
	var choices: Array = []
	for c in 5:
		if counts[c] > 0:
			choices.append(c)
	var called: int = choices.pick_random()
	if want_called >= 0 and choices.has(want_called):
		called = want_called
	if round_kind == Kind.RARE:
		# only two tiles keep the called colour, the rest becomes another colour
		var mine: Array = []
		for idx in active:
			if colors[idx] == called:
				mine.append(idx)
		mine.shuffle()
		while mine.size() > 2:
			var idx: int = mine.pop_back()
			var other: int = (called + 1 + randi() % 4) % 5
			colors[idx] = other
	return {"colors": colors, "called": called}


func _recolor(colors: Array, called: int) -> void:
	target = called
	for i in tiles.size():
		var t = tiles[i]
		t.color = colors[i]
		if colors[i] < 0:
			continue
		t.mat.albedo_color = COLORS[colors[i]]
		t.mat.emission = COLORS[colors[i]] if colors[i] != TRAP else Color(1.0, 0.1, 0.05)
		t.mat.emission_energy_multiplier = 0.04


func on_go() -> void:
	phase = Phase.BREAK
	phase_left = 0.8


func _kind_text(k: int) -> String:
	match k:
		Kind.RARE:
			return "RARE COLOUR!"
		Kind.TRAPS:
			return "TRAP TILES!"
		Kind.DOUBLE:
			return "DOUBLE DROP!"
		Kind.SHRINK:
			return "FLOOR SHRINKS!"
		Kind.QUICK:
			return "AGAIN, QUICK!"
	return ""


@rpc func start_round(colors: Array, called: int, think: float, number: int, round_kind: int, trap_list: Array, permanent: bool, power: int) -> void:
	_recolor(colors, called)
	phase = Phase.THINK
	phase_left = think
	think_total = think
	round_number = number
	kind = round_kind
	traps = trap_list
	traps_permanent = permanent
	traps_dropped = trap_list.is_empty()
	power_tile = power
	power_node.visible = power >= 0
	if power >= 0:
		power_node.position = tiles[power].pos + Vector3(0, 1.0, 0)
	call_label.text = ""
	call_label.add_theme_color_override("font_color", COLORS[called])
	sound("res://assets/sounds/countdown.wav")


@rpc func drop_traps(list: Array, permanent: bool) -> void:
	traps_dropped = true
	for idx in list:
		var t = tiles[idx]
		if t.gone:
			continue
		var tween := create_tween()
		tween.tween_property(t.body, "position:y", -9.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.shape.set_deferred("disabled", true)
		t.color = -2          # not a safe tile any more
		if permanent:
			t.gone = true
	if power_tile in list:
		power_tile = -1
		power_node.visible = false
	sound("res://assets/sounds/arcade/thud.wav")


@rpc func drop_tiles(saved: Array) -> void:
	phase = Phase.DROP
	phase_left = DROP_HOLD
	call_label.text = ""
	power_node.visible = false
	power_tile = -1
	var any := false
	for t in tiles:
		if t.gone or t.color == target:
			continue
		if saved.has(t.idx):
			t.mat.emission_energy_multiplier = 1.6
			t.mat.emission = Color(0.4, 0.9, 1.0)
			continue
		var tween := create_tween()
		tween.tween_property(t.body, "position:y", -9.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.shape.set_deferred("disabled", true)
		any = true
	if any:
		sound("res://assets/sounds/arcade/thud.wav")


@rpc func restore_tiles(brk: float) -> void:
	phase = Phase.BREAK
	phase_left = brk
	for t in tiles:
		if t.gone:
			continue
		t.body.position = t.pos
		t.shape.set_deferred("disabled", false)


@rpc func take_power(player_id: int) -> void:
	power_tile = -1
	power_node.visible = false
	set_shield(player_id, true)
	sound("res://assets/sounds/arcade/pass.wav")


@rpc func set_shield(player_id: int, on: bool) -> void:
	shields[player_id] = on
	if shield_nodes.has(player_id):
		shield_nodes[player_id].visible = on


func _think_time() -> float:
	return maxf(3.6 - 0.26 * round_number, 1.6)


func world_tick(delta: float) -> void:
	pulse += delta
	phase_left = maxf(phase_left - delta, 0.0)
	for i in lights.size():
		var a := pulse * 0.9 + i * TAU / lights.size()
		lights[i].position = Vector3(cos(a) * 6.0, 4.5, sin(a) * 6.0)
	if power_node.visible:
		power_node.rotation.y += delta * 3.0
		power_node.position.y = 1.0 + 0.15 * sin(pulse * 4.0)
	if phase == Phase.THINK:
		var prefix := "STAND ON %s" % COLOR_NAMES[target]
		call_label.text = "%s   %.1f" % [prefix, phase_left]
		var glow := 0.5 + 0.5 * sin(pulse * 12.0)
		for t in tiles:
			if t.gone or t.color == -2:
				continue
			if t.color == target:
				t.mat.emission_energy_multiplier = 0.45 + 0.55 * glow
			elif t.color == TRAP:
				t.mat.emission_energy_multiplier = 0.2 + 1.2 * (0.5 + 0.5 * sin(pulse * 22.0))
			else:
				t.mat.emission_energy_multiplier = 0.02
	elif phase == Phase.BREAK:
		for t in tiles:
			t.mat.emission_energy_multiplier = 0.04
			if not t.gone and t.color >= 0:
				t.mat.emission = COLORS[t.color] if t.color != TRAP else Color(1.0, 0.1, 0.05)


func server_tick(delta: float) -> void:
	if ended:
		return
	# who has fallen?
	for p in players:
		var pid := p.info.player_id
		if alive[pid] and p.position.y < FALL_Y:
			alive[pid] = false
			if shields[pid]:
				lobby.broadcast(set_shield.bind(pid, false))
				set_shield(pid, false)
			p.knock_out(Vector3(0.01, 0, 0.01))
			sound("res://assets/sounds/wrong.wav")
	if phase == Phase.THINK:
		# the trap tiles fall away half way through the round
		if not traps_dropped and phase_left <= think_total * 0.5:
			traps_dropped = true
			lobby.broadcast(drop_traps.bind(traps, traps_permanent))
			drop_traps(traps, traps_permanent)
		# the shield star
		if power_tile >= 0:
			for p in players:
				var pid := p.info.player_id
				if not alive[pid] or shields[pid] or p.position.y < -0.5:
					continue
				var tpos: Vector3 = tiles[power_tile].pos
				if Vector2(p.position.x - tpos.x, p.position.z - tpos.z).length() < POWER_RADIUS:
					lobby.broadcast(take_power.bind(pid))
					take_power(pid)
					break
	if phase_left > 0.0:
		return
	match phase:
		Phase.START:
			pass
		Phase.BREAK:
			_end_check()
			if ended:
				return
			_begin_round()
		Phase.THINK:
			var saved := _shield_saves()
			lobby.broadcast(drop_tiles.bind(saved))
			drop_tiles(saved)
		Phase.DROP:
			# the floor comes back: everybody still alive has survived this round
			for p in players:
				if alive[p.info.player_id]:
					survived[p.info.player_id] += 1
			var brk := BREAK
			if kind == Kind.DOUBLE:
				brk = 0.45
			lobby.broadcast(restore_tiles.bind(brk))
			restore_tiles(brk)


## The tiles that stay because a shielded player stands on them when the floor drops. The shields are used up.
func _shield_saves() -> Array:
	var saved: Array = []
	for p in players:
		var pid := p.info.player_id
		if not alive[pid] or not shields[pid] or p.position.y < -0.5:
			continue
		for t in tiles:
			if t.gone or t.color == target or t.color == -2:
				continue
			if absf(p.position.x - t.pos.x) < TILE * 0.5 and absf(p.position.z - t.pos.z) < TILE * 0.5:
				saved.append(t.idx)
				lobby.broadcast(set_shield.bind(pid, false))
				set_shield(pid, false)
				break
	return saved


func _pick_kind() -> int:
	if double_pending:
		double_pending = false
		return Kind.QUICK
	if (round_number >= 5 and shrink_stage == 0) or (round_number >= 9 and shrink_stage == 1):
		return Kind.SHRINK
	if round_number <= 1:
		return Kind.NORMAL
	var pool := [Kind.NORMAL, Kind.RARE, Kind.RARE]
	if round_number >= 3:
		pool.append_array([Kind.TRAPS, Kind.TRAPS, Kind.DOUBLE])
	return pool.pick_random()


func _begin_round() -> void:
	round_number += 1
	var active := _active()
	var round_kind := _pick_kind()
	var trap_list: Array = []
	var permanent := false
	var think := _think_time()
	match round_kind:
		Kind.RARE:
			think += 0.5
		Kind.TRAPS:
			var pool := active.duplicate()
			pool.shuffle()
			trap_list = pool.slice(0, mini(3 + round_number / 6, maxi(active.size() / 4, 1)))
			think += 0.4
		Kind.SHRINK:
			for idx in active:
				if _tile_layer(idx) == shrink_stage:
					trap_list.append(idx)
			permanent = true
			shrink_stage += 1
			think += 0.7
		Kind.DOUBLE:
			double_pending = true
		Kind.QUICK:
			think = 1.7
	var plan := _plan_colors(active, trap_list, -1, round_kind)
	# a shield star on a tile that is NOT safe: grab it and risk the run, or play it safe
	var power := -1
	if round_number >= 2 and randf() < 0.5 and round_kind != Kind.QUICK:
		var spots: Array = []
		for idx in active:
			if plan.colors[idx] != plan.called and plan.colors[idx] != TRAP:
				spots.append(idx)
		if not spots.is_empty():
			power = spots.pick_random()
	lobby.broadcast(start_round.bind(plan.colors, plan.called, think, round_number, round_kind, trap_list, permanent, power))
	start_round(plan.colors, plan.called, think, round_number, round_kind, trap_list, permanent, power)
	var text := _kind_text(round_kind)
	if text != "":
		announce(text, Color(1.0, 0.55, 0.3) if round_kind in [Kind.TRAPS, Kind.SHRINK] else Color(0.5, 0.9, 1.0), 0.6)


func _alive_players() -> Array:
	return players.filter(func(p): return alive[p.info.player_id])


func _end_check() -> void:
	var left := _alive_players()
	var over := left.size() <= 1
	if lobby.minigame_state.minigame_type == Lobby.MINIGAME_TYPES.TWO_VS_TWO and not over:
		var team_of := func(p): return 0 if p in [players[0], players[1]] else 1
		over = left.all(func(p): return team_of.call(p) == team_of.call(left[0]))
	if not over:
		return
	ended = true
	var winner_text := "NOBODY WINS"
	if left.size() >= 1:
		winner_text = "%s WINS!" % left[0].info.name.to_upper() if lobby.minigame_state.minigame_type != Lobby.MINIGAME_TYPES.TWO_VS_TWO else "TEAM WINS!"
		for p in left:
			p.show_animation("happy")
	announce(winner_text, Color(1.0, 0.88, 0.25), 1.6)
	get_tree().create_timer(2.4).timeout.connect(_finish_game)


func _finish_game() -> void:
	var points := []
	for p in players:
		var pid := p.info.player_id
		points.append(survived[pid] + (100 if alive[pid] else 0))
	finish_by_points(points)


func on_time_up() -> void:
	if ended:
		return
	ended = true
	_finish_game()


# ----- the bots -----

func _safe_tile_at(pos: Vector3, tile) -> bool:
	return absf(pos.x - tile.pos.x) < TILE * 0.4 and absf(pos.z - tile.pos.z) < TILE * 0.4


func _nearest_target_tile(from: Vector3, skip: Array = []):
	var best = null
	var best_d := INF
	for t in tiles:
		if t.gone or t.color != target or skip.has(t.idx):
			continue
		var d := Vector2(t.pos.x - from.x, t.pos.z - from.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


func _ai(p: ArcadePlayer, _delta: float) -> Dictionary:
	if not running or phase == Phase.DROP or p.dead:
		return {"dir": Vector2.ZERO}
	var pid := p.info.player_id
	# slower bots wait a moment before they react to the call
	var reaction := 0.25
	match p.info.ai_difficulty:
		Lobby.Difficulty.EASY:
			reaction = 0.9
		Lobby.Difficulty.NORMAL:
			reaction = 0.55
	if phase == Phase.THINK and phase_left > think_total - reaction:
		return {"dir": Vector2.ZERO}
	var tile = _nearest_target_tile(p.position)
	if tile == null:
		return {"dir": Vector2.ZERO}
	var here := Vector2(p.position.x, p.position.z)
	# a shield star is worth a detour if there is time to get to a safe tile afterwards
	if phase == Phase.THINK and power_tile >= 0 and not shields[pid] and p.info.ai_difficulty != Lobby.Difficulty.EASY:
		var ppos: Vector3 = tiles[power_tile].pos
		var after = _nearest_target_tile(ppos)
		if after != null:
			var route := here.distance_to(Vector2(ppos.x, ppos.z)) + Vector2(ppos.x, ppos.z).distance_to(Vector2(after.pos.x, after.pos.z))
			if route < p.speed * (phase_left - 0.35):
				var to_star := Vector2(ppos.x - p.position.x, ppos.z - p.position.z)
				if to_star.length() > 0.3:
					return {"dir": to_star.normalized()}
	# already on a safe tile: stay put
	if _safe_tile_at(p.position, tile) or (tile.color == target and _on_any_target(p.position)):
		return {"dir": Vector2.ZERO}
	var to := Vector2(tile.pos.x - p.position.x, tile.pos.z - p.position.z)
	if to.length() < 0.4:
		return {"dir": Vector2.ZERO}
	return {"dir": to.normalized()}


func _on_any_target(pos: Vector3) -> bool:
	for t in tiles:
		if not t.gone and t.color == target and _safe_tile_at(pos, t):
			return true
	return false

extends ArcadeGame
## Color Clash: a floor of coloured tiles. A colour is called, everybody runs onto a tile of that colour and when the
## time is up every other tile drops away. Every round is faster. The last player standing wins.

const GRID := 6
const TILE := 2.0
const COLORS := [Color(0.93, 0.28, 0.30), Color(0.30, 0.52, 0.96), Color(0.34, 0.80, 0.42), Color(0.99, 0.85, 0.25), Color(0.72, 0.42, 0.92)]
const COLOR_NAMES := ["RED", "BLUE", "GREEN", "YELLOW", "PURPLE"]
const FALL_Y := -2.5
const DROP_HOLD := 1.5          # seconds the floor stays gone
const BREAK := 1.0              # pause after the floor is back

enum Phase { START, THINK, DROP, BREAK }

var tiles: Array = []           # { "body": StaticBody3D, "mesh": MeshInstance3D, "mat": StandardMaterial3D, "color": int, "pos": Vector3 }
var target := 0
var phase := Phase.START
var phase_left := 0.0
var round_number := 0
var survived := {}              # player id -> rounds survived, kept by the server
var alive := {}                 # player id -> bool, kept by the server
var ended := false
var call_label: Label
var lights: Array[OmniLight3D] = []
var pulse := 0.0


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
			tiles.append({"body": body, "shape": shape, "mesh": mesh, "mat": mat, "color": 0, "pos": pos})
	# disco lights circling over the floor
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = COLORS[i]
		l.light_energy = 1.3
		l.omni_range = 11.0
		l.position = Vector3(0, 4.5, 0)
		add_child(l)
		lights.append(l)
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
	var spots := [Vector3(-8.5, 0.05, -1), Vector3(8.5, 0.05, -1), Vector3(-8.5, 0.05, 2.5), Vector3(8.5, 0.05, 2.5)]
	spots = [tiles[GRID * 1 + 1].pos, tiles[GRID * 4 + 1].pos, tiles[GRID * 1 + 4].pos, tiles[GRID * 4 + 4].pos]
	for i in players.size():
		var p := players[i]
		p.position = spots[i] + Vector3(0, 0.25, 0)
		p.speed = 5.4
		p.ai_brain = _ai
		survived[p.info.player_id] = 0
		alive[p.info.player_id] = true
	_recolor(_make_colors(), 0)
	call_label.text = ""


func _make_colors() -> Array:
	# every colour shows up often enough that the called one is never a tiny island
	var colors: Array = []
	for i in GRID * GRID:
		colors.append(i % COLORS.size())
	colors.shuffle()
	return colors


func _recolor(colors: Array, called: int) -> void:
	target = called
	for i in tiles.size():
		var t = tiles[i]
		t.color = colors[i]
		t.mat.albedo_color = COLORS[colors[i]]
		t.mat.emission = COLORS[colors[i]]
		t.mat.emission_energy_multiplier = 0.04


func on_go() -> void:
	phase = Phase.BREAK
	phase_left = 0.8


@rpc func start_round(colors: Array, called: int, think: float, number: int) -> void:
	_recolor(colors, called)
	phase = Phase.THINK
	phase_left = think
	round_number = number
	call_label.text = ""
	call_label.add_theme_color_override("font_color", COLORS[called])
	sound("res://assets/sounds/countdown.wav")


@rpc func drop_tiles() -> void:
	phase = Phase.DROP
	phase_left = DROP_HOLD
	call_label.text = ""
	var any := false
	for t in tiles:
		if t.color != target:
			var tween := create_tween()
			tween.tween_property(t.body, "position:y", -9.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.shape.set_deferred("disabled", true)
			any = true
	if any:
		sound("res://assets/sounds/arcade/thud.wav")


@rpc func restore_tiles() -> void:
	phase = Phase.BREAK
	phase_left = BREAK
	for t in tiles:
		t.body.position = t.pos
		t.shape.set_deferred("disabled", false)


func _think_time() -> float:
	return maxf(3.6 - 0.28 * round_number, 1.55)


func world_tick(delta: float) -> void:
	pulse += delta
	phase_left = maxf(phase_left - delta, 0.0)
	for i in lights.size():
		var a := pulse * 0.9 + i * TAU / lights.size()
		lights[i].position = Vector3(cos(a) * 6.0, 4.5, sin(a) * 6.0)
	if phase == Phase.THINK:
		call_label.text = "STAND ON %s   %.1f" % [COLOR_NAMES[target], phase_left]
		var glow := 0.5 + 0.5 * sin(pulse * 12.0)
		for t in tiles:
			t.mat.emission_energy_multiplier = (0.45 + 0.55 * glow) if t.color == target else 0.02
	elif phase == Phase.BREAK:
		for t in tiles:
			t.mat.emission_energy_multiplier = 0.04


func server_tick(delta: float) -> void:
	if ended:
		return
	# who has fallen?
	for p in players:
		var pid := p.info.player_id
		if alive[pid] and p.position.y < FALL_Y:
			alive[pid] = false
			p.knock_out(Vector3(0.01, 0, 0.01))
			sound("res://assets/sounds/wrong.wav")
	if phase_left > 0.0:
		return
	match phase:
		Phase.START:
			pass
		Phase.BREAK:
			_end_check()
			if ended:
				return
			round_number += 1
			var called := randi() % COLORS.size()
			var colors := _make_colors()
			var think := _think_time()
			lobby.broadcast(start_round.bind(colors, called, think, round_number))
			start_round(colors, called, think, round_number)
		Phase.THINK:
			lobby.broadcast(drop_tiles)
			drop_tiles()
		Phase.DROP:
			# the floor comes back: everybody still alive has survived this round
			for p in players:
				if alive[p.info.player_id]:
					survived[p.info.player_id] += 1
			lobby.broadcast(restore_tiles)
			restore_tiles()


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

func _nearest_target_tile(from: Vector3):
	var best = null
	var best_d := INF
	for t in tiles:
		if t.color != target:
			continue
		var d := Vector2(t.pos.x - from.x, t.pos.z - from.z).length()
		if d < best_d:
			best_d = d
			best = t
	return best


func _ai(p: ArcadePlayer, _delta: float) -> Dictionary:
	if not running or phase == Phase.DROP:
		return {"dir": Vector2.ZERO}
	var pid := p.info.player_id
	# slower bots wait a moment before they react to the call
	var reaction := 0.25
	match p.info.ai_difficulty:
		Lobby.Difficulty.EASY:
			reaction = 0.9
		Lobby.Difficulty.NORMAL:
			reaction = 0.55
	if phase == Phase.THINK and phase_left > _think_time() - reaction:
		return {"dir": Vector2.ZERO}
	var tile = _nearest_target_tile(p.position)
	if tile == null:
		return {"dir": Vector2.ZERO}
	# an easy bot sometimes heads for the wrong colour and has to scramble
	var to := Vector2(tile.pos.x - p.position.x, tile.pos.z - p.position.z)
	if to.length() < 0.4:
		return {"dir": Vector2.ZERO}
	return {"dir": to.normalized()}

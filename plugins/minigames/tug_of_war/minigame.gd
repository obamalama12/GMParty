extends ArcadeGame
## Tug of War: two teams pull a rope. Mash the action button as fast as you can! The team that drags the other
## over the line (or pulls harder when the time is up) wins. In the 1 vs 3 version the single player pulls with
## the strength of two players. A match is the best of three rounds. A pulse ring marks the beat: a press right on the
## beat is a perfect pull (stronger, and it builds a streak). The last seconds of a round are a final push, the team that
## lost the last round gets a power pull, and a tied match ends in a sudden-death round.

const TEAM_SIDE := 4.6
const DRAG := 3.1
const SOLO_STRENGTH := 2.0
const PULL_FORCE := 0.0105
const ROPE_RANGE := 1.0

var rope_pos := 0.0              # > 0: the rope moves towards team 0 (the left side)
var teams: Array = [[], []]      # player nodes per team
var force := [0.0, 0.0]          # decaying pull of each team, server only
var pull_timers := {}            # player id -> seconds the player shows the pulling animation
var base_positions := {}         # player id -> Vector3
var flag: MeshInstance3D
var rope_mesh: MeshInstance3D
var ai_timers := {}
var ended := false
var press_count := {}
var round_wins := [0, 0]
var round_number := 1
var round_label: Label
const ROUNDS := 3
const BEAT := 0.75               # seconds between two beats of the pulse ring
const PERFECT_WINDOW := 0.13     # seconds around the beat that count as perfect
const FINAL_PUSH := 6.0          # seconds left in a round when the final push starts
const POWER_TIME := 6.0
const POWER_FACTOR := 1.35
var camera: Camera3D
var cam_base := Vector3.ZERO
var shake := 0.0
var streaks := {}                # player id -> perfect presses in a row (server)
var round_presses := [0, 0]      # presses per team in this round (server)
var power_left := [0.0, 0.0]     # seconds of power pull left per team (server)
var power_team := -1             # team that has the power pull (every peer, for the visuals)
var final_push := false
var sudden := false
var last_loser := -1
var ring: MeshInstance3D
var ring_mat: StandardMaterial3D
var crowd: Array = []            # { "node": Node3D, "team": int, "phase": float }
var cheer := [0.0, 0.0]          # how excited the crowd of each side is


func build_world() -> void:
	make_sky(Color(0.35, 0.62, 0.95), Color(0.85, 0.93, 1.0), Color(0.5, 0.7, 0.4))
	camera = make_camera(Vector3(0, 5.8, 8.6), Vector3(0, 0.8, 0), 56.0)
	cam_base = camera.position
	make_music("res://assets/music/retro/tug_march.ogg")
	# a sports field: red team on the left, blue team on the right, the mud pit in the middle, a fence and a crowd of trees behind
	add_floor(11.0, 4, [Color(0.93, 0.42, 0.38), Color(0.40, 0.58, 0.95), Color(0.97, 0.9, 0.55), Color(1, 1, 1)])
	var pit := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 0.06
	cyl.material = toon(Color(0.40, 0.26, 0.14))
	pit.mesh = cyl
	pit.position.y = 0.035
	add_child(pit)
	for x in [-3.0, 3.0]:
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 0.03, 5.0)
		box.material = toon(Color(1, 1, 1))
		line.mesh = box
		line.position = Vector3(x, 0.05, 0)
		add_child(line)
	fence_arc(11.5, 203.0, 337.0, 20)
	arc_props(["Bush_Large_Flowers", "Bush_Flowers", "Bush_Large"], 16, 12.4, 200.0, 340.0, 1.1, 1.4, -0.1, 21, 0.2)
	arc_props(["NormalTree_1", "NormalTree_3", "NormalTree_5", "BirchTree_2", "BirchTree_4"], 12, 15.0, 203.0, 337.0, 1.5, 2.0, -0.5, 22, 0.6)
	pole_ring(11.0, 5, 3.2, Color(0.95, 0.95, 0.95), Color(0.95, 0.3, 0.3), Color(0.3, 0.45, 1.0), 180.0, 360.0)
	_build_ring()
	_build_crowd()
	# rope and flag
	rope_mesh = MeshInstance3D.new()
	var rope_box := BoxMesh.new()
	rope_box.size = Vector3(TEAM_SIDE * 2.0 + 1.5, 0.12, 0.12)
	rope_box.material = toon(Color(0.85, 0.65, 0.35))
	rope_mesh.mesh = rope_box
	rope_mesh.position.y = 1.0
	rope_mesh.name = "Rope"
	add_child(rope_mesh)
	flag = MeshInstance3D.new()
	var flag_box := BoxMesh.new()
	flag_box.size = Vector3(0.25, 0.55, 0.06)
	flag_box.material = toon(Color(1.0, 0.2, 0.25))
	flag.mesh = flag_box
	flag.position = Vector3(0, 1.45, 0)
	add_child(flag)
	var knot := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.2
	ball.height = 0.4
	ball.material = toon(Color(1.0, 0.85, 0.2))
	knot.mesh = ball
	flag.add_child(knot)
	knot.position.y = -0.45
	# teams: the lobby fills Player1.. in team order
	var state := lobby.minigame_state
	var index := 0
	for team_index in state.minigame_teams.size():
		for _id in state.minigame_teams[team_index]:
			if index < players.size():
				teams[team_index if state.minigame_type != Lobby.MINIGAME_TYPES.FREE_FOR_ALL else 0].append(players[index])
			index += 1
	for t in 2:
		var members: Array = teams[t]
		var spacing := 1.7
		for i in members.size():
			var p: ArcadePlayer = members[i]
			var z := (i - (members.size() - 1) * 0.5) * spacing
			var x := -TEAM_SIDE if t == 0 else TEAM_SIDE
			p.position = Vector3(x, 0.05, z)
			p.can_move = false
			p.sync_position = false
			p.auto_animation = false
			p.rotation.y = PI / 2.0 if t == 0 else -PI / 2.0
			base_positions[p.info.player_id] = p.position
			pull_timers[p.info.player_id] = 0.0
			press_count[p.info.player_id] = 0
			streaks[p.info.player_id] = 0
			p.action_pressed.connect(_on_local_press.bind(p))
			p.ai_brain = Callable()
	duration = 18.0
	round_label = Label.new()
	round_label.theme_type_variation = &"HeaderMedium"
	round_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.3))
	round_label.add_theme_constant_override("outline_size", 8)
	round_label.add_theme_font_size_override("font_size", 36)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	round_label.offset_left = -300
	round_label.offset_right = 300
	round_label.offset_top = 66
	$Screen.add_child(round_label)
	_update_round_label()


func _team_of(player_id: int) -> int:
	for t in 2:
		for p: ArcadePlayer in teams[t]:
			if p.info.player_id == player_id:
				return t
	return 0


func _strength(player_id: int) -> float:
	# in 1 vs 3 the single player (the one in the team of one) is stronger
	if lobby.minigame_state.minigame_type == Lobby.MINIGAME_TYPES.ONE_VS_THREE:
		if teams[_team_of(player_id)].size() == 1:
			return SOLO_STRENGTH
	return 1.0


func _on_local_press(p: ArcadePlayer) -> void:
	if not running or finished:
		return
	press.rpc_id(1)


@rpc("any_peer", "call_local") func press() -> void:
	if not multiplayer.is_server() or not running or ended:
		return
	var sender := multiplayer.get_remote_sender_id()
	for p in players:
		if p.info.addr.peer_id == sender and not p.info.is_ai():
			_register_press(p.info.player_id)
			return


func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# The pulse ring: a ring shrinks onto the target ring on the beat. Press when they meet!
func _build_ring() -> void:
	var target := MeshInstance3D.new()
	var t_mesh := TorusMesh.new()
	t_mesh.inner_radius = 0.9
	t_mesh.outer_radius = 1.0
	t_mesh.material = _glow(Color(1, 1, 1, 0.8))
	target.mesh = t_mesh
	target.position = Vector3(0, 0.1, 2.3)
	target.scale = Vector3(1, 0.1, 1)
	add_child(target)
	ring = MeshInstance3D.new()
	var r_mesh := TorusMesh.new()
	r_mesh.inner_radius = 0.9
	r_mesh.outer_radius = 1.0
	ring_mat = _glow(Color(1.0, 0.85, 0.2, 0.0))
	r_mesh.material = ring_mat
	ring.mesh = r_mesh
	ring.position = target.position
	add_child(ring)


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 16:
		var team := 0 if i < 8 else 1
		var node := Node3D.new()
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 0.9
		var base := Color(0.93, 0.35, 0.3) if team == 0 else Color(0.35, 0.55, 0.95)
		cap.material = toon(base.lerp(Color(1, 1, 1), rng.randf() * 0.35))
		body.mesh = cap
		body.position.y = 0.55
		node.add_child(body)
		var head := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.22
		sph.height = 0.44
		sph.material = toon(Color(0.98, 0.82, 0.65))
		head.mesh = sph
		head.position.y = 1.2
		node.add_child(head)
		var slot := i % 8
		var x := (-9.0 + slot * 1.15) if team == 0 else (0.9 + slot * 1.15)
		node.position = Vector3(x, 0.0, -7.3 + rng.randf_range(-0.4, 0.4) + (0.0 if slot % 2 == 0 else -0.8))
		add_child(node)
		crowd.append({"node": node, "team": team, "phase": rng.randf() * TAU})


func _beat_phase() -> float:
	return fmod(maxf(duration - time_left, 0.0), BEAT) / BEAT


func _is_perfect_now() -> bool:
	var phase := _beat_phase() * BEAT
	return minf(phase, BEAT - phase) < PERFECT_WINDOW


func _register_press(player_id: int, forced_perfect := false) -> void:
	var team := _team_of(player_id)
	var perfect := forced_perfect or _is_perfect_now()
	if perfect:
		streaks[player_id] += 1
	else:
		streaks[player_id] = 0
	var mult := 1.0
	if perfect:
		mult = 2.0 + 0.2 * mini(streaks[player_id], 5)
	if final_push:
		mult *= 1.35
	if power_left[team] > 0.0:
		mult *= POWER_FACTOR
	force[team] += _strength(player_id) * mult
	press_count[player_id] += 1
	round_presses[team] += 1
	lobby.broadcast(pulled.bind(player_id, perfect, streaks[player_id]))
	pulled(player_id, perfect, streaks[player_id])


func _pitched(path: String, pitch: float) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Effects"
	player.pitch_scale = pitch
	player.volume_db = -4.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _popup(at: Vector3, text: String, color: Color, big := false) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.011 if big else 0.007
	label.font_size = 96
	label.outline_size = 24
	label.modulate = color
	label.outline_modulate = Color(0.1, 0.05, 0.3)
	label.position = at + Vector3(0, 2.0, 0)
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


@rpc func pulled(player_id: int, perfect := false, streak := 0) -> void:
	pull_timers[player_id] = 0.22
	if perfect:
		shake = maxf(shake, 0.05 + 0.01 * mini(streak, 5))
		_pitched("res://assets/sounds/correct.wav", 1.0 + 0.1 * mini(streak, 8))
		var p := player_by_id(player_id)
		if p:
			_popup(p.position, "PERFECT!" if streak < 3 else "PERFECT x%d" % streak, Color(1.0, 0.9, 0.3), streak >= 3)
	else:
		shake = maxf(shake, 0.012)


@rpc("unreliable") func sync_rope(pos: float) -> void:
	rope_pos = pos


@rpc func sync_phase(push: bool, is_sudden: bool, power: int) -> void:
	final_push = push
	sudden = is_sudden
	power_team = power
	_update_round_label()


func server_tick(delta: float) -> void:
	if ended:
		return
	# the bots mash at a speed that depends on their difficulty
	for t in 2:
		for p: ArcadePlayer in teams[t]:
			if not p.info.is_ai():
				continue
			var pid := p.info.player_id
			var rate := 5.0
			match p.info.ai_difficulty:
				Lobby.Difficulty.EASY:
					rate = 3.6
				Lobby.Difficulty.HARD:
					rate = 6.6
			ai_timers[pid] = ai_timers.get(pid, randf() * 0.2) - delta
			if ai_timers[pid] <= 0.0:
				ai_timers[pid] = (1.0 / rate) * randf_range(0.7, 1.3)
				var skill := 0.2
				match p.info.ai_difficulty:
					Lobby.Difficulty.EASY:
						skill = 0.08
					Lobby.Difficulty.HARD:
						skill = 0.32
				_register_press(pid, randf() < skill)
	for t in 2:
		power_left[t] = maxf(power_left[t] - delta, 0.0)
	if power_team >= 0 and power_left[power_team] <= 0.0:
		power_team = -1
		lobby.broadcast(sync_phase.bind(final_push, sudden, -1))
	if not final_push and not sudden and time_left <= FINAL_PUSH:
		final_push = true
		lobby.broadcast(sync_phase.bind(true, sudden, power_team))
		announce("FINAL PUSH!", Color(1.0, 0.5, 0.2), 0.8)
	var push: float = (force[0] - force[1]) * PULL_FORCE * (1.7 if sudden else 1.0)
	rope_pos = clampf(rope_pos + push, -ROPE_RANGE, ROPE_RANGE)
	force[0] *= pow(0.5, delta * 6.0)
	force[1] *= pow(0.5, delta * 6.0)
	if Engine.get_physics_frames() % 4 == 0:
		lobby.broadcast(sync_rope.bind(rope_pos))
	if absf(rope_pos) >= ROPE_RANGE:
		_end(0 if rope_pos > 0 else 1)


func on_time_up() -> void:
	if ended:
		return
	if sudden and absf(rope_pos) < 0.04:
		# sudden death must have a winner: the team that pressed more, or a coin flip
		if round_presses[0] != round_presses[1]:
			_end(0 if round_presses[0] > round_presses[1] else 1)
		else:
			_end(randi() % 2)
	elif absf(rope_pos) < 0.04:
		_end(-1)
	else:
		_end(0 if rope_pos > 0 else 1)


func _update_round_label() -> void:
	var dots := func(wins: int) -> String:
		return "●".repeat(wins) + "○".repeat(maxi(ROUNDS / 2 + 1 - wins, 0))
	var title := "SUDDEN DEATH" if sudden else "ROUND %d" % round_number
	round_label.text = "%s   %s   %s" % [dots.call(round_wins[0]), title, dots.call(round_wins[1])]


@rpc func sync_round(wins0: int, wins1: int, number: int) -> void:
	round_wins = [wins0, wins1]
	round_number = number
	_update_round_label()


# A round is over. The match goes on until a team has two round wins or three rounds have been played.
func _end(winner: int) -> void:
	if ended:
		return
	ended = true
	final_push = false
	power_left = [0.0, 0.0]
	lobby.broadcast(sync_phase.bind(false, sudden, -1))
	sync_phase(false, sudden, -1)
	lobby.broadcast(sync_rope.bind(rope_pos))
	lobby.broadcast(end_fx.bind(winner))
	end_fx(winner)
	for p in players:
		var won := winner == _team_of(p.info.player_id)
		p.show_animation("happy" if won else "sad")
	last_loser = (1 - winner) if winner >= 0 else -1
	if winner >= 0:
		round_wins[winner] += 1
	var decided: bool = round_wins[0] > ROUNDS / 2 or round_wins[1] > ROUNDS / 2 or (round_number >= ROUNDS and round_wins[0] != round_wins[1])
	if sudden:
		decided = winner >= 0
	var match_winner := -1
	if round_wins[0] > round_wins[1]:
		match_winner = 0
	elif round_wins[1] > round_wins[0]:
		match_winner = 1
	if decided:
		lobby.broadcast(sync_round.bind(round_wins[0], round_wins[1], round_number))
		sync_round(round_wins[0], round_wins[1], round_number)
		announce("TEAM %s WINS!" % ("RED" if match_winner == 0 else "BLUE") if match_winner >= 0 else "DRAW!", Color(1.0, 0.88, 0.25), 1.4)
		get_tree().create_timer(2.2).timeout.connect(_finish.bind(match_winner))
	else:
		announce("ROUND %d: %s" % [round_number, ("RED" if winner == 0 else "BLUE") if winner >= 0 else "DRAW"], Color(0.9, 0.95, 1.0), 0.9)
		get_tree().create_timer(2.4).timeout.connect(_next_round)


@rpc func end_fx(winner: int) -> void:
	shake = 0.3
	_pitched("res://assets/sounds/ui/round_win.wav", 1.0)
	if winner >= 0:
		cheer[winner] = 3.0
		# the losers are dragged into the mud: splash!
		for p: ArcadePlayer in teams[1 - winner]:
			_splash(Vector3(p.position.x, 0.1, p.position.z))
		_splash(Vector3(0, 0.1, 0), 24)


func _splash(at: Vector3, amount := 14) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.material = toon(Color(0.40, 0.26, 0.14))
	p.mesh = mesh
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -14, 0)
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _next_round() -> void:
	round_number += 1
	rope_pos = 0.0
	force = [0.0, 0.0]
	round_presses = [0, 0]
	sudden = round_number > ROUNDS
	duration = 15.0 if sudden else 18.0
	time_left = duration
	final_push = false
	var power := -1
	if not sudden and last_loser >= 0:
		power = last_loser
		power_left[power] = POWER_TIME
	lobby.broadcast(sync_phase.bind(false, sudden, power))
	sync_phase(false, sudden, power)
	for p in players:
		p.show_animation("idle")
	lobby.broadcast(sync_rope.bind(0.0))
	lobby.broadcast(sync_round.bind(round_wins[0], round_wins[1], round_number))
	sync_round(round_wins[0], round_wins[1], round_number)
	if sudden:
		announce("SUDDEN DEATH!", Color(1.0, 0.3, 0.3), 1.0)
	elif power >= 0:
		announce("%s: POWER PULL!" % ("RED" if power == 0 else "BLUE"), Color(1.0, 0.85, 0.3), 0.9)
	else:
		announce("GO!", Color(0.4, 1.0, 0.5), 0.5)
	ended = false


func _finish(winner: int) -> void:
	if finished:
		return
	finished = true
	match lobby.minigame_state.minigame_type:
		Lobby.MINIGAME_TYPES.DUEL:
			lobby.minigame_win_by_points([1 if winner == 0 else 0, 1 if winner == 1 else 0])
		Lobby.MINIGAME_TYPES.ONE_VS_THREE:
			# team 0 are the three, team 1 the single player
			if winner == -1:
				lobby.minigame_1v3_draw()
			elif winner == 0:
				lobby.minigame_1v3_win_team_players()
			else:
				lobby.minigame_1v3_win_solo_player()
		_:
			if winner == -1:
				lobby.minigame_team_draw()
			else:
				lobby.minigame_team_win(winner)


func world_tick(delta: float) -> void:
	_visuals(delta)
	# everything on the rope moves together: the winners step back, the losers are dragged towards the pit
	flag.position.x = -rope_pos * DRAG
	rope_mesh.position.x = flag.position.x
	for t in 2:
		for p: ArcadePlayer in teams[t]:
			var pid := p.info.player_id
			pull_timers[pid] = maxf(pull_timers[pid] - delta, 0.0)
			var base: Vector3 = base_positions[pid]
			p.position.x = lerpf(p.position.x, base.x - rope_pos * DRAG, minf(delta * 8.0, 1.0))
			if not p.dead and not ended:
				p.play("run" if pull_timers[pid] > 0.0 else "idle")


func _visuals(delta: float) -> void:
	# camera shake: kicks decay, a close fight rumbles a little
	shake = maxf(shake - delta * 0.6, 0.0)
	var amp := shake + (0.015 if absf(rope_pos) > 0.6 and not ended else 0.0) + (0.01 if final_push else 0.0)
	camera.position = cam_base + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * amp
	# the pulse ring
	var phase := _beat_phase()
	var live := running and not ended and not finished
	var grow := 1.0 + (1.0 - phase) * 1.5
	ring.scale = Vector3(grow, 0.1, grow)
	ring_mat.albedo_color = Color(1.0, 0.85, 0.2, (0.2 + 0.7 * phase) if live else 0.0)
	# the crowd cheers louder for the team that is winning
	var lead := clampf(rope_pos, -1.0, 1.0)
	for t in 2:
		cheer[t] = maxf(cheer[t] - delta, 0.0)
	var now := Time.get_ticks_msec() * 0.001
	for c in crowd:
		var excitement: float = clampf(0.15 + (lead if c.team == 0 else -lead) * 0.6, 0.0, 1.0) + (0.8 if cheer[c.team] > 0.0 else 0.0)
		var hop := absf(sin(now * (4.0 + excitement * 5.0) + c.phase)) * (0.08 + excitement * 0.45)
		c.node.position.y = hop

extends ArcadeGame
## Tug of War: two teams pull a rope. Mash the action button as fast as you can! The team that drags the other
## over the line (or pulls harder when the time is up) wins. In the 1 vs 3 version the single player pulls with
## the strength of two players.

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


func build_world() -> void:
	make_environment(Color(0.6, 0.85, 1.0), Color(0.95, 0.95, 1.0))
	make_camera(Vector3(0, 5.8, 8.6), Vector3(0, 0.8, 0), 56.0)
	make_music("res://assets/music/minigames/harvest food.ogg")
	add_disc(11.0, Color(0.5, 0.8, 0.35), load("res://assets/models/nature/Textures/Grass.png"))
	# the mud pit in the middle
	var pit := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 1.5
	cyl.height = 0.05
	cyl.material = toon(Color(0.4, 0.27, 0.15))
	pit.mesh = cyl
	pit.position.y = 0.03
	add_child(pit)
	var lines := [-3.0, 3.0]
	for x in lines:
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.03, 5.0)
		box.material = toon(Color(1, 1, 1))
		line.mesh = box
		line.position = Vector3(x, 0.04, 0)
		add_child(line)
	decorate(8.0, 16.0, 26, ["NormalTree_1", "NormalTree_3", "NormalTree_5", "Bush_Large", "Rock_2", "Bush_Flowers"], 21)
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
			p.action_pressed.connect(_on_local_press.bind(p))
			p.ai_brain = Callable()
	duration = 26.0


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


func _register_press(player_id: int) -> void:
	var team := _team_of(player_id)
	force[team] += _strength(player_id)
	press_count[player_id] += 1
	lobby.broadcast(pulled.bind(player_id))
	pulled(player_id)


@rpc func pulled(player_id: int) -> void:
	pull_timers[player_id] = 0.22


@rpc("unreliable") func sync_rope(pos: float) -> void:
	rope_pos = pos


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
				_register_press(pid)
	var push: float = (force[0] - force[1]) * PULL_FORCE
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
	if absf(rope_pos) < 0.04:
		_end(-1)
	else:
		_end(0 if rope_pos > 0 else 1)


func _end(winner: int) -> void:
	if ended:
		return
	ended = true
	lobby.broadcast(sync_rope.bind(rope_pos))
	for p in players:
		var won := winner == _team_of(p.info.player_id)
		p.show_animation("happy" if won else "sad")
	get_tree().create_timer(1.6).timeout.connect(_finish.bind(winner))


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

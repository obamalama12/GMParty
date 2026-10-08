extends Node3D

const Plant := preload("res://plugins/minigames/harvest_food/plant.gd")
const Pumpkin := preload("res://plugins/minigames/harvest_food/pumpkin.gd")
const Player := preload("res://plugins/minigames/harvest_food/player.gd")

const PUMPKIN_MASS: float = 10.0

const GAME_TIME := 45.0
# Golden rush: all new pumpkins are golden
const RUSH_START := 28.0
const RUSH_END := 20.0
# Fever time at the end: double points and faster growth
const FEVER_TIME := 12.0

const SND_RUSH := preload("res://assets/sounds/ui/turn_start.wav")
const SND_FEVER := preload("res://assets/sounds/ui/round_win.wav")
const SND_SCORE := preload("res://assets/sounds/correct.wav")
const SND_STEAL := preload("res://assets/sounds/wrong.wav")

var rush := false
var fever := false
var msg_tween: Tween

@onready var plants: Array[Plant] = [
	$Plant1,
	$Plant2,
	$Plant3,
	$Plant4,
	$Plant5,
	$Plant6,
	$Plant7,
	$Plant8,
	$Plant9,
]
var lobby: Lobby

func _enter_tree() -> void:
	self.lobby = Lobby.get_lobby(self)

func _ready():
	var groups := [
		[$Area1, $Player1],
		[$Area2, $Player2],
	]
	plants[0].point_value = 1.0
	plants[0].active = true
	plants[1].point_value = 1.0
	plants[1].active = true
	if lobby.minigame_state.minigame_type != Lobby.MINIGAME_TYPES.DUEL:
		groups.append_array([
			[$Area3, $Player3],
			[$Area4, $Player4]
		])
		plants[2].point_value = 1.0
		plants[2].active = true
		plants[3].point_value = 1.0
		plants[3].active = true
	else:
		$Area3.queue_free()
		$Area4.queue_free()
	
	for nodes in groups:
		# Set up event handler for each plot area
		nodes[0].body_entered.connect(_on_area_body_entered.bind(nodes[1]))
		nodes[0].body_exited.connect(_on_area_body_exited.bind(nodes[1]))
		
		# Show player icon on each plot area
		var material: StandardMaterial3D = nodes[0].get_node(^"MeshInstance3D").get_surface_override_material(0)
		material.albedo_texture = PluginSystem.character_loader.load_character_icon(nodes[1].info.character)
	
	# Restart so that the game takes longer than the default of the scene
	$Timer.start(GAME_TIME)
	$Screen/Message.text = ""
	
	if multiplayer.is_server():
		# Start the game timer on the server
		$Timer.timeout.connect(_on_Timer_timeout)

func growth_multiplier() -> float:
	return 2.0 if fever else 1.0

func _play(stream: AudioStream):
	# The server has no audio
	if multiplayer.is_server():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _show_message(text: String, color: Color, duration: float):
	var msg: Label = $Screen/Message
	if msg_tween:
		msg_tween.kill()
	msg.text = text
	msg.modulate = color
	msg.pivot_offset = msg.size / 2.0
	msg.scale = Vector2(1.6, 1.6)
	msg_tween = create_tween()
	msg_tween.tween_property(msg, "scale", Vector2.ONE, 0.2)
	msg_tween.tween_interval(duration)
	msg_tween.tween_callback(msg.set.bind("text", ""))

# Phases of the game are derived from the timer on every peer
func _process(_delta: float) -> void:
	var left: float = $Timer.time_left
	if $Timer.is_stopped():
		return
	var new_rush := left <= RUSH_START and left > RUSH_END
	if new_rush != rush:
		rush = new_rush
		if rush:
			_show_message(tr("HARVEST_GOLDEN_RUSH"), Color(1, 0.85, 0.2), 2.0)
			_play(SND_RUSH)
			if multiplayer.is_server():
				for plant in plants:
					if plant.active and not plant.special:
						lobby.broadcast(plant.make_golden)
						plant.make_golden()
		else:
			_show_message("", Color.WHITE, 0.0)
	if left <= FEVER_TIME and not fever:
		fever = true
		_show_message(tr("HARVEST_FEVER"), Color(1, 0.4, 0.2), 2.5)
		_play(SND_FEVER)
		if multiplayer.is_server():
			# More pumpkins to harvest
			grow_new_plant()
			grow_new_plant()

@rpc func _popup(pos: Vector3, text: String, color: Color, sound: int):
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 96
	label.pixel_size = 0.006
	label.outline_size = 24
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3(0, 2.0, 0)
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", pos.y + 4.0, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)
	if sound == 1:
		_play(SND_SCORE)
	elif sound == 2:
		_play(SND_STEAL)

func popup(pos: Vector3, text: String, color: Color, sound: int = 0):
	lobby.broadcast(_popup.bind(pos, text, color, sound))
	_popup(pos, text, color, sound)

func same_team(a: Player, b: Player) -> bool:
	for team in lobby.minigame_state.minigame_teams:
		if a.info.player_id in team and b.info.player_id in team:
			return true
	return false

func _on_Timer_timeout():
	match lobby.minigame_state.minigame_type:
		Lobby.MINIGAME_TYPES.FREE_FOR_ALL:
			lobby.minigame_win_by_points([$Player1.score, $Player2.score, $Player3.score, $Player4.score])
		Lobby.MINIGAME_TYPES.DUEL:
			lobby.minigame_win_by_points([$Player1.score, $Player2.score])
		Lobby.MINIGAME_TYPES.TWO_VS_TWO:
			lobby.minigame_team_win_by_points([$Player1.score + $Player2.score, $Player3.score + $Player4.score])

func _client_process(_delta):
	$Screen/Time.text = "%.1f" % $Timer.time_left

# Guarantees consistent names on the client and the server
var pumpkin_counter := 0
@rpc func _spawn_pumpkin(size: float, special: bool, pos: Vector3, forward: Vector3):
	var p: Pumpkin = preload("res://plugins/minigames/harvest_food/pumpkin.tscn").instantiate()
	add_child(p)
	p.name = "Pumpkin" + str(pumpkin_counter)
	pumpkin_counter += 1
	p.position = pos
	p.linear_velocity = forward * 5 + Vector3(0, 2, 0)
	p.mass = size * PUMPKIN_MASS
	p.point_value = size
	p.special = special

func throw(size: float, special: bool, pos: Vector3, forward: Vector3):
	lobby.broadcast(_spawn_pumpkin.bind(size, special, pos, forward))
	_spawn_pumpkin(size, special, pos, forward)

func grow_new_plant() -> void:
	var valid: Array[Plant] = []
	for plant in plants:
		if not plant.active:
			valid.append(plant)
	if valid.is_empty():
		return
	var target: Plant = valid.pick_random()
	var special := rush or randf() < 0.12
	lobby.broadcast(target.activate.bind(special))
	target.activate(special)

func get_value(body: Pumpkin) -> float:
	var modifier := 2.0 if body.special else 1.0
	if fever:
		modifier *= 2.0
	return body.point_value * modifier

func _on_area_body_entered(body: Pumpkin, player: Player) -> void:
	# Collision layers are set up so that only plants are registered
	if not multiplayer.is_server():
		return
	
	var value := get_value(body)
	body.set_meta(&"scored_value", value)
	body.set_meta(&"scorer", player)
	player.score += value
	var text := "+%.1f" % value
	var color := Color(1, 0.85, 0.2) if body.special else Color.WHITE
	popup(body.global_position, text, color, 1)
	$Screen/ScoreOverlay.set_score(player.info.player_id, player.score)

func _on_area_body_exited(body: Pumpkin, player: Player) -> void:
	# Collision layers are set up so that only plants are registered
	if not multiplayer.is_server():
		return
	
	# Remove exactly what was awarded, even if the fever state changed meanwhile
	player.score -= body.get_meta(&"scored_value", get_value(body))
	if body.get_meta(&"scorer", null) == player:
		body.remove_meta(&"scorer")
	$Screen/ScoreOverlay.set_score(player.info.player_id, player.score)

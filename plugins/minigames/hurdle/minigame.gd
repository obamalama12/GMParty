extends Node3D

const MAX_CONSECUTIVE_HURDLES := 1

var players_alive := 4
var players_finished := 0
var placement := [ null, null, null, null ]

var speedup_timeout := 10.0

var direction := 0.05
var time_to_direction_change := 1.0

var stop := false

# Seconds before a reversal during which the warning is shown
const WARN_TIME := 0.9
const SURGE_DURATION := 2.5
const SURGE_BOOST := 0.4

var warned := false
var boost := 0.0
var surge_left := 0.0
var time_to_surge := 12.0
var elapsed := 0.0
var msg_tween: Tween

const SND_WARN := preload("res://assets/sounds/wrong.wav")
const SND_SURGE := preload("res://assets/sounds/ui/turn_start.wav")
const SND_OUT := preload("res://assets/sounds/arcade/boom.wav")

var lobby: Lobby
@onready var players = Utility.get_nodes_in_group(self, "players")

func _enter_tree() -> void:
	lobby = Lobby.get_lobby(self)

func _ready() -> void:
	var msg: Label = $Environment/Screen/Message
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.text = ""

# The speed of the belt including temporary surges
func belt() -> float:
	return direction * (1.0 + boost)

func update_speed(delta: float):
	elapsed += delta
	if surge_left > 0.0:
		surge_left = max(surge_left - delta, 0.0)
		boost = SURGE_BOOST * clamp(min(surge_left, 0.3) / 0.3, 0.0, 1.0)
	else:
		boost = 0.0
	if abs(direction) < 1.0:
		direction += sign(direction) * delta * 0.2
		direction = clamp(direction, -1.0, 1.0)
	elif speedup_timeout == 0.0:
		direction += sign(direction) * delta * 0.05
		direction = clamp(direction, -8, 8)
	else:
		speedup_timeout -= delta
		if speedup_timeout <= 0.0:
			speedup_timeout = 0.0

@rpc func change_direction():
	direction = -direction
	_show_message("", Color.WHITE, 0.0)

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
	var msg: Label = $Environment/Screen/Message
	if msg_tween:
		msg_tween.kill()
	msg.text = text
	msg.modulate = color
	msg.scale = Vector2.ONE
	if text.is_empty():
		return
	msg.pivot_offset = Vector2(msg.size.x / 2.0, msg.size.y / 2.0)
	msg_tween = create_tween()
	msg.scale = Vector2(1.6, 1.6)
	msg_tween.tween_property(msg, "scale", Vector2.ONE, 0.2)
	if duration > 0.0:
		msg_tween.tween_interval(duration)
		msg_tween.tween_callback(msg.set.bind("text", ""))

@rpc func warn_reverse():
	_show_message(tr("HURDLE_REVERSE_WARNING"), Color(1, 0.35, 0.25), 1.0)
	_play(SND_WARN)

@rpc func start_surge():
	surge_left = SURGE_DURATION
	boost = SURGE_BOOST
	_show_message(tr("HURDLE_SURGE"), Color(1, 0.85, 0.2), 1.5)
	_play(SND_SURGE)

@rpc func player_out_msg(player_id: int):
	var info := lobby.get_player_by_id(player_id)
	_show_message(tr("HURDLE_PLAYER_OUT_MSG").format({"player": info.name}), Color.WHITE, 1.5)
	_play(SND_OUT)

func _client_process(delta: float):
	if stop:
		return
	update_speed(delta)
	$conveyor_belt/AnimationPlayer.speed_scale = belt()

func _server_process(delta: float):
	if stop:
		return
	update_speed(delta)
	time_to_direction_change -= delta
	if not warned and time_to_direction_change <= WARN_TIME:
		warned = true
		lobby.broadcast(warn_reverse)
	if time_to_direction_change <= 0.0:
		direction = -direction
		warned = false
		lobby.broadcast(change_direction)
		time_to_direction_change += randf_range(2.5, 6.0)
	# Occasionally the belt surges, more often the longer the game lasts
	time_to_surge -= delta
	if time_to_surge <= 0.0:
		time_to_surge = randf_range(9.0, 15.0) * clamp(1.4 - elapsed / 60.0, 0.6, 1.0)
		if time_to_direction_change > WARN_TIME + 1.0:
			surge_left = SURGE_DURATION
			lobby.broadcast(start_surge)
	for player in players:
		if not player.dead and player.position.y < -10:
			player.dead = true
			player.hide()
			lobby.broadcast(player_out_msg.bind(player.info.player_id))
			placement[players_alive - 1] = player.info.player_id
			players_alive -= 1
			if players_alive <= 1:
				stop = true
				lobby.broadcast(do_stop)
				get_tree().create_timer(1).timeout.connect(finished)

@rpc func do_stop():
	stop = true

func finished():
	for player in Utility.get_nodes_in_group(self, "players"):
		if not player.dead:
			placement[players_alive - 1] = player.info.player_id
			players_alive -= 1
	lobby.minigame_win_by_position(placement)

class_name ArcadePlayer
extends CharacterBody3D
## The player of the small arcade minigames (Cookie Catch, Hot Bomb, Jump Rope, Tug of War).
##
## The peer that owns the player (the machine of the human, or the server for bots) moves the character and tells
## everybody else where it is. The game script on the server decides everything that matters (scores, who is out).

signal action_pressed

@export var speed := 4.0
@export var jump_velocity := 0.0          # 0 = this game has no jumping
@export var gravity := 24.0
@export var arena_radius := 0.0           # > 0: the player cannot leave this circle around the origin
@export var can_move := true
@export var sync_position := true         # false: the game script places the player (Tug of War)
@export var auto_animation := true         # false: the game script chooses the animation

var info: Lobby.PlayerInfo
var speed_multiplier := 1.0
var stunned := 0.0
var boosted := 0.0                         # seconds of speed boost left
const BOOST_FACTOR := 1.55
var dead := false
var frozen := false                        # set by games that pause the players for a moment

## Bots: a Callable(player, delta) -> Dictionary with "dir": Vector2 (x, z) and optionally "jump": bool
var ai_brain: Callable

var _animation := ""
var _fling := Vector3.ZERO


func _ready() -> void:
	add_to_group("players")
	play("idle")


func play(name: String) -> void:
	if name == _animation:
		return
	_animation = name
	var model := get_node_or_null("Model")
	if model and model.has_method("play_animation"):
		model.play_animation(name)


func _read_input() -> Dictionary:
	if info.is_ai():
		if ai_brain.is_valid():
			return ai_brain.call(self, get_physics_process_delta_time())
		return {"dir": Vector2.ZERO}
	var pid := info.player_id
	var dir := Vector2(
		Input.get_axis("player%d_left" % pid, "player%d_right" % pid),
		Input.get_axis("player%d_up" % pid, "player%d_down" % pid))
	if Input.is_action_just_pressed("player%d_action1" % pid):
		action_pressed.emit()
	return {"dir": dir, "jump": Input.is_action_pressed("player%d_action1" % pid)}


func _physics_process(delta: float) -> void:
	if dead:
		_fling.y -= 18.0 * delta
		position += _fling * delta
		rotation.x += delta * 9.0
		return
	if not info or not info.is_local():
		return
	stunned = maxf(stunned - delta, 0.0)
	boosted = maxf(boosted - delta, 0.0)
	var dir := Vector2.ZERO
	var jump := false
	if not frozen:
		var input := _read_input()
		dir = input.get("dir", Vector2.ZERO)
		jump = input.get("jump", false)
	if stunned > 0.0 or not can_move:
		dir = Vector2.ZERO
	if dir.length() > 1.0:
		dir = dir.normalized()
	if jump and jump_velocity > 0.0 and is_on_floor() and stunned <= 0.0:
		velocity.y = jump_velocity
	velocity.y -= gravity * delta
	var factor := speed_multiplier * (BOOST_FACTOR if boosted > 0.0 else 1.0)
	velocity.x = dir.x * speed * factor
	velocity.z = dir.y * speed * factor
	move_and_slide()
	if arena_radius > 0.0:
		var flat := Vector2(position.x, position.z)
		if flat.length() > arena_radius:
			flat = flat.normalized() * arena_radius
			position.x = flat.x
			position.z = flat.y
	if dir.length_squared() > 0.01:
		rotation.y = atan2(dir.x, dir.y)
	if auto_animation:
		if stunned > 0.0:
			play("stun")
		elif not is_on_floor():
			play("jump")
		elif dir.length_squared() > 0.01:
			play("run")
		else:
			play("idle")
	if sync_position:
		info.lobby.broadcast(position_updated.bind(position, rotation.y, _animation))


@rpc("unreliable_ordered", "any_peer") func position_updated(pos: Vector3, yaw: float, animation: String) -> void:
	if dead or not sync_position or multiplayer.get_remote_sender_id() != info.addr.peer_id:
		return
	position = pos
	rotation.y = yaw
	play(animation)


## Plays an animation on every peer, for scripted moments (the game script calls this on the server).
func show_animation(animation: String) -> void:
	info.lobby.broadcast(_show_animation.bind(animation))
	_show_animation(animation)


@rpc func _show_animation(animation: String) -> void:
	play(animation)


## Stuns the player for a moment. The server calls this.
func stun(duration: float) -> void:
	info.lobby.broadcast(_stun.bind(duration))
	_stun(duration)


@rpc func _stun(duration: float) -> void:
	stunned = maxf(stunned, duration)
	play("stun")


## Speeds the player up for a while. The server calls this.
func boost(duration: float) -> void:
	info.lobby.broadcast(_boost.bind(duration))
	_boost(duration)


@rpc func _boost(duration: float) -> void:
	boosted = maxf(boosted, duration)


## The player is out: it is flung away and hidden. The server calls this.
func knock_out(direction: Vector3) -> void:
	info.lobby.broadcast(_knock_out.bind(direction))
	_knock_out(direction)


@rpc func _knock_out(direction: Vector3) -> void:
	if dead:
		return
	dead = true
	play("stun")
	_fling = direction.normalized() * 6.0 + Vector3(0, 8.0, 0)
	get_tree().create_timer(1.1).timeout.connect(hide)

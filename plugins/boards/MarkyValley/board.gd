extends Node3D

signal animation_finished

enum State {
	None,
	Fly_out,
	Fly_in,
}

## Green spaces are warps: a space name maps to the space the player is carried to.
## The pairs are filled in by tools/board_builder/build_board.gd.
@export var warps: Dictionary = {}

var player_to_animate: Node3D
var next_space: NodeBoard
var state: int = State.None
var destination: Vector3


func _process(delta: float):
	match state:
		State.Fly_out:
			if player_to_animate.position.y < player_to_animate.space.position.y + 5:
				player_to_animate.position.y += 10 * delta
			else:
				state = State.Fly_in
				player_to_animate.position = next_space.position
				destination = player_to_animate.position
				player_to_animate.position += Vector3(0, 5, 0)
				$Controller.camera_focus = next_space
				next_space = null
		State.Fly_in:
			if player_to_animate.position.y > destination.y:
				player_to_animate.position.y -= 10 * delta
			else:
				player_to_animate.position = destination
				state = State.None
				player_to_animate = null
				destination = Vector3()
				animation_finished.emit()


func handle_event(player: Node3D, space: Node3D):
	var target := get_node_or_null("Nodes/" + str(warps.get(space.name, ""))) as NodeBoard
	if target == null:
		$Controller.board_continue()
		return

	$Controller.lobby.broadcast(_warp_animation.bind(player.info.player_id, get_path_to(target)))
	await _warp_animation(player.info.player_id, get_path_to(target))

	if multiplayer.is_server():
		player.teleport_to(target)
		await get_tree().create_timer(0.5).timeout
		$Controller.board_continue()


@rpc func _warp_animation(id: int, target_path: NodePath):
	var player = $Controller.get_player_by_player_id(id)
	next_space = get_node(target_path)
	player_to_animate = player
	state = State.Fly_out
	await animation_finished

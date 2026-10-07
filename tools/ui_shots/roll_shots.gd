## Dev tool: starts a game and records screenshots around the first dice roll of the human player.
##   SHOTS_DIR=/tmp/roll godot --path . res://tools/ui_shots/roll_shots.tscn
extends Node


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func press(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
		await wait(0.12)


func _ready() -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	await wait(1.0)
	var game := Global.create_local_server()
	await game.multiplayer.connected_to_server
	var lobby = await game.create_lobby()
	await wait(1.0)
	lobby.set_player_name(0, "Tester")
	lobby.select_character(0, "Businessman")
	lobby.select_board("RetroValley")
	await wait(1.0)
	lobby.start()
	await wait(24.0)
	var i := 0
	for step in 60:
		if step % 6 == 3:
			await press("player1_ok")
		await wait(0.3)
		get_viewport().get_texture().get_image().save_png("%s/r%02d.png" % [dir, i])
		i += 1
	get_tree().quit()

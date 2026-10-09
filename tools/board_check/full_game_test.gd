## Dev tool: plays a whole one-turn game (one human who only presses OK, three bots) up to the victory screen and
## takes screenshots of it. SHOTS_DIR=/tmp/x godot --path . res://tools/board_check/full_game_test.tscn
extends Node

var dir := ""


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func press_ok_forever() -> void:
	while true:
		# every few presses also a random direction, so path forks and menus can be passed
		var actions := ["player1_ok", "ui_accept"]
		if randi() % 3 == 0:
			actions.append(["player1_left", "player1_right", "player1_up", "player1_down"].pick_random())
		for action in actions:
			var e := InputEventAction.new()
			e.action = action
			e.pressed = true
			Input.parse_input_event(e)
		await wait(0.1)
		for action in actions:
			var e := InputEventAction.new()
			e.action = action
			e.pressed = false
			Input.parse_input_event(e)
		await wait(0.7)


func find_scene(path: String) -> Node:
	var root := get_node_or_null("/root/Client")
	if root == null:
		return null
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.scene_file_path == path and not n.is_queued_for_deletion():
			return n
		stack.append_array(n.get_children())
	return null


func snap(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(n + ".png"))
	print("FG ", n)


func _ready() -> void:
	dir = OS.get_environment("SHOTS_DIR")
	await wait(1.0)
	var game := Global.create_local_server()
	await game.multiplayer.connected_to_server
	var lobby = await game.create_lobby()
	await wait(1.0)
	lobby.set_player_name(0, "Tester")
	lobby.select_character(0, "Businessman")
	lobby.select_board("RetroValley")
	lobby.update_setting("main/turns", 1)
	await wait(1.0)
	lobby.start()
	press_ok_forever()
	var started := Time.get_ticks_msec()
	var victory: Node = null
	var shots := 0
	while victory == null and (Time.get_ticks_msec() - started) < 2400000:
		await wait(2.0)
		victory = find_scene("res://client/menus/victory_screen/victory_screen.tscn")
		if (Time.get_ticks_msec() - started) / 60000 > shots:
			shots += 1
			snap("progress%d" % shots)
	print("FG victory screen: ", victory != null, " after ", (Time.get_ticks_msec() - started) / 1000, " s")
	if victory != null:
		for i in 10:
			await wait(3.0)
			snap("victory%d" % i)
	print("FG ALL DONE")
	get_tree().quit()

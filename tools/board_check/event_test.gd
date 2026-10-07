## Dev tool: lands a player on a "?" space once for every board event and checks that the event finishes.
##
##   godot --path . res://tools/board_check/event_test.tscn
extends Node


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func press_ok_forever() -> void:
	while true:
		Input.action_press("player1_ok")
		await wait(0.1)
		Input.action_release("player1_ok")
		await wait(0.5)


func _run_landing(ctrl: Node, player: Node, done: Array) -> void:
	await ctrl.land_on_space(player)
	done[0] = true


func _ready() -> void:
	await wait(1.0)
	var game := Global.create_local_server()
	await game.multiplayer.connected_to_server
	var lobby = await game.create_lobby()
	await wait(1.0)
	lobby.set_player_name(0, "Tester")
	lobby.select_character(0, "Joy")
	lobby.select_board("RetroValley")
	await wait(1.0)
	lobby.start()
	var ctrl: Node = null
	var t := 0.0
	while ctrl == null and t < 90:
		await wait(0.5)
		t += 0.5
		for n in get_tree().get_nodes_in_group("Controller"):
			if get_node("/root/Server").is_ancestor_of(n) and n.players.size() == 4:
				ctrl = n
	await wait(8.0)
	press_ok_forever()
	var board: Node = ctrl.get_parent()
	var event_space: NodeBoard = null
	for s: NodeBoard in board.get_node("Nodes").get_children():
		if s.type == NodeBoard.NODE_TYPES.EVENT:
			event_space = s
			break
	print("EVT found space ", event_space.name if event_space else "NONE")
	var player: PlayerBoard = ctrl.players[1]   # a bot: its dialogs are accepted automatically
	var wanted: PackedStringArray = OS.get_environment("ONLY_EVENTS").split(",", false)
	for name in BoardEvents.EVENTS:
		if not wanted.is_empty() and not (name in wanted):
			continue
		OS.set_environment("BOARD_EVENT", name)
		var before := []
		for p in ctrl.players:
			before.append(p.cookies)
		player.teleport_to(event_space)
		await wait(0.5)
		var started := Time.get_ticks_msec()
		print("EVT landing, player space ", player.space.name, " type ", player.space.type)
		var done := [false]
		_run_landing(ctrl, player, done)
		var waited := 0.0
		while waited < 60.0 and not done[0]:
			await wait(0.25)
			waited += 0.25
			if OS.get_environment("EVT_DEBUG") != "" and int(waited * 4) % 40 == 0:
				var cd: Control = null
				for n in get_tree().get_nodes_in_group("Controller"):
					if get_node("/root/Client").is_ancestor_of(n):
						cd = n.get_node("Screen/SpeechDialog")
				print("EVT dbg server dialog ", ctrl.get_node("Screen/SpeechDialog").visible, " client dialog ", cd.visible if cd else "none", " focus ", get_viewport().gui_get_focus_owner(), " player_turn ", ctrl.player_turn)
		print("EVT finished: ", done[0])
		var after := []
		for p in ctrl.players:
			after.append(p.cookies)
		print("EVT %s: done in %.1f s, cookies %s -> %s, items %d, modifiers %s" % [name, (Time.get_ticks_msec() - started) / 1000.0, before, after, player.items.size(), player.roll_modifiers])
		await wait(0.5)
	print("EVT ALL DONE")
	get_tree().quit()

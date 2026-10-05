## Dev tool: starts a local game and takes screenshots of the board from a few camera angles.
##
## godot --path . res://tools/board_tour/board_tour.tscn
## Environment: BOARD (default KDEValley), SHOTS_DIR (default user://board_tour)
extends Node

var shots_dir := ""


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func find_by_scene(root: Node, path: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.scene_file_path == path:
			return n
		stack.append_array(n.get_children())
	return null


func bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.visible and n.mesh:
			var b: AABB = n.global_transform * n.get_aabb()
			# skip the huge water plane and sky-like meshes
			if b.size.x > 150 or b.size.z > 150:
				continue
			box = b if first else box.merge(b)
			first = false
	return box


func shot(cam: Camera3D, name: String, pos: Vector3, target: Vector3, fov := 50.0) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target)
	cam.make_current()
	await wait(1.0)
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))
	print("TOUR ", name)


func _ready() -> void:
	shots_dir = OS.get_environment("SHOTS_DIR") if OS.get_environment("SHOTS_DIR") != "" else "user://board_tour"
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var board_name := OS.get_environment("BOARD") if OS.get_environment("BOARD") != "" else "KDEValley"
	await wait(1.0)
	var game := Global.create_local_server()
	await game.multiplayer.connected_to_server
	var lobby = await game.create_lobby()
	await wait(1.0)
	lobby.set_player_name(0, "Tester")
	lobby.select_character(0, "Businessman")
	lobby.select_board(board_name)
	await wait(1.0)
	lobby.start()
	var board: Node = null
	var t := 0.0
	while board == null and t < 60:
		await wait(0.5)
		t += 0.5
		board = find_by_scene(get_node("/root/Client"), "res://plugins/boards/%s/board.tscn" % board_name)
	print("TOUR board found after ", t, " s: ", board)
	await wait(8.0)

	# PLAY=<seconds>: just play, pressing the ok button of player 1 now and then (this rolls the dice,
	# picks the highlighted path and accepts dialogs), and log where the players are
	if OS.get_environment("PLAY") != "":
		var ctrl: Node = null
		for n in get_tree().get_nodes_in_group("Controller"):
			if get_node("/root/Client").is_ancestor_of(n):
				ctrl = n
		var total := float(OS.get_environment("PLAY"))
		var elapsed := 0.0
		var shot_every := 12.0
		var next_shot := 6.0
		while elapsed < total:
			var press := InputEventAction.new()
			press.action = "player1_ok"
			press.pressed = true
			Input.parse_input_event(press)
			await wait(0.15)
			var release := InputEventAction.new()
			release.action = "player1_ok"
			release.pressed = false
			Input.parse_input_event(release)
			await wait(0.9)
			elapsed += 1.05
			if elapsed >= next_shot:
				next_shot += shot_every
				get_viewport().get_texture().get_image().save_png(shots_dir.path_join("play_%03d.png" % int(elapsed)))
				var where := []
				for pl in ctrl.players:
					where.append("%s:%s(c%d,k%d)" % [pl.info.name, pl.space.name, pl.cookies, pl.cakes])
				print("PLAY t=%d turn=%d %s" % [int(elapsed), server_lobby_turn(), " ".join(where)])
		print("TOUR DONE")
		get_tree().quit()
		return

	# WARPTEST=1: trigger the event of every green space on the server and check where the player ends up
	if OS.get_environment("WARPTEST") == "1":
		var server_board: Node = find_by_scene(get_node("/root/Server"), "res://plugins/boards/%s/board.tscn" % board_name)
		var player = server_board.get_node("Controller").players[0]
		var ok_count := 0
		for key in server_board.warps.keys():
			var space: Node3D = server_board.get_node("Nodes/" + key)
			player.teleport_to(space)
			await wait(0.5)
			server_board.handle_event(player, space)
			await server_board.get_node("Controller")._event_completed
			await wait(0.3)
			var expected: String = server_board.warps[key]
			var good: bool = player.space.name == expected
			ok_count += int(good)
			print("WARP ", key, " (", space.get("type"), ") -> ", player.space.name, " expected ", expected, " ", "OK" if good else "WRONG")
		print("WARPTEST ", ok_count, "/", server_board.warps.size())
		print("TOUR DONE")
		get_tree().quit()
		return

	# hide the HUD so the map is easy to see
	for n in get_tree().get_nodes_in_group("Controller"):
		if get_node("/root/Client").is_ancestor_of(n):
			for c in n.get_children():
				if c is CanvasLayer or c is Control:
					c.visible = false

	var box := bounds(board)
	var center := box.get_center()
	var size := maxf(box.size.x, box.size.z)
	print("TOUR bounds ", box)
	# use the game camera, because it has the board's sky lighting; stop the controller from moving it
	var controller: Node = null
	for n in get_tree().get_nodes_in_group("Controller"):
		if get_node("/root/Client").is_ancestor_of(n):
			controller = n
	var cam: Camera3D = controller.get_node("Camera3D")
	controller.set_process(false)
	cam.far = 1000.0
	cam.top_level = true
	await shot(cam, "map_top", center + Vector3(0, size * 1.15, size * 0.02), center, 55.0)
	await shot(cam, "map_overview", center + Vector3(size * 0.05, size * 0.75, size * 0.8), center, 50.0)
	await shot(cam, "map_corner_a", center + Vector3(size * 0.7, size * 0.45, size * 0.7), center, 55.0)
	await shot(cam, "map_corner_b", center + Vector3(-size * 0.7, size * 0.45, size * 0.55), center, 55.0)
	await shot(cam, "map_low", center + Vector3(0, size * 0.18, size * 0.75), center + Vector3(0, 0, 0), 60.0)
	# optional close views: VIEWS="name:x:z;name:x:z" gives a gameplay-style shot (like the game camera)
	# and a wider one for each spot
	if OS.get_environment("VIEWS") != "":
		var spaces: Array = board.get_node("Nodes").get_children()
		for view in OS.get_environment("VIEWS").split(";"):
			var parts := view.split(":")
			var target := Vector3(float(parts[1]), 0, float(parts[2]))
			var best: Node3D = spaces[0]
			for sp in spaces:
				if sp.global_position.distance_to(Vector3(target.x, sp.global_position.y, target.z)) < best.global_position.distance_to(Vector3(target.x, best.global_position.y, target.z)):
					best = sp
			var p0: Vector3 = best.global_position
			await shot(cam, "view_" + parts[0] + "_game", p0 + Vector3(0, 4, 4), p0, 75.0)
			await shot(cam, "view_" + parts[0] + "_wide", p0 + Vector3(0, 14, 18), p0 + Vector3(0, 0, -4), 55.0)
	print("TOUR DONE")
	get_tree().quit()


func server_lobby_turn() -> int:
	var l = get_node_or_null("/root/Server/Game")
	if l == null:
		return -1
	for c in l.get_children():
		if "turn" in c:
			return c.turn
	return -1

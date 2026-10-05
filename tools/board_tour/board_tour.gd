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
	var cam := Camera3D.new()
	cam.far = 1000.0
	add_child(cam)
	await shot(cam, "map_top", center + Vector3(0, size * 1.15, size * 0.02), center, 55.0)
	await shot(cam, "map_overview", center + Vector3(size * 0.05, size * 0.75, size * 0.8), center, 50.0)
	await shot(cam, "map_corner_a", center + Vector3(size * 0.7, size * 0.45, size * 0.7), center, 55.0)
	await shot(cam, "map_corner_b", center + Vector3(-size * 0.7, size * 0.45, size * 0.55), center, 55.0)
	await shot(cam, "map_low", center + Vector3(0, size * 0.18, size * 0.75), center + Vector3(0, 0, 0), 60.0)
	print("TOUR DONE")
	get_tree().quit()

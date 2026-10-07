## Dev tool: checks that every space of a board sits on the ground (not sunk in, not floating, not outside the map).
##
##   BOARD=RetroValley godot --headless --path . --script res://tools/board_check/space_check.gd
##
## Builds collision from the terrain, the bridge and other floor meshes of the board, then drops rays onto the
## top surface of every space. Prints SPACECHECK lines and a summary; exit code 1 when a space is bad.
extends SceneTree

const SINK_LIMIT := 0.005        # the top surface may not be lower than the ground by more than this
const FLOAT_LIMIT := 0.45        # nor hover higher than this above the ground (at the lowest point)


func _initialize() -> void:
	_run()


func _floor_meshes(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c.name in ["Nodes", "Controller", "Water"] or c is Camera3D:
			continue
		if c.name.begins_with("Player"):
			continue
		if c is MeshInstance3D and c.mesh:
			# only large floor-like meshes: terrain, bridge pieces, islands; skip small scenery
			var box: AABB = c.mesh.get_aabb()
			if box.size.x * c.scale.x > 6.0 or box.size.z * c.scale.z > 6.0:
				out.append(c)
		_floor_meshes(c, out)


func _run() -> void:
	var board_name := OS.get_environment("BOARD") if OS.get_environment("BOARD") != "" else "RetroValley"
	var board: Node3D = load("res://plugins/boards/%s/board.tscn" % board_name).instantiate()
	root.add_child(board)
	await process_frame
	await process_frame
	var floors: Array = []
	_floor_meshes(board, floors)
	for m: MeshInstance3D in floors:
		m.create_trimesh_collision()
		for c in m.get_children():
			if c is StaticBody3D:
				c.collision_layer = 1
				c.collision_mask = 0
	for i in 3:
		await physics_frame
	var space := board.get_viewport().world_3d.direct_space_state
	var bad_sunk := []
	var bad_float := []
	var bad_missing := []
	var total := 0
	for nd: Node3D in board.get_node("Nodes").get_children():
		if not nd.get("_visible") and nd.name == "Start":
			pass
		var model: Node3D = nd.get_node("Model")
		var gt := model.global_transform
		var up := gt.basis.y.normalized()
		# the hexagon is 0.1 thick: the model origin is 0.05 below its top surface, at the middle of the mesh height
		var top_c := gt.origin + gt.basis.y * 0.05
		var worst_sink := -99.0
		var lowest_gap := 99.0
		var missing := false
		total += 1
		for k in 61:
			var rr := 0.0 if k == 0 else 0.85 * sqrt(float(k) / 60.0)
			var ang := k * 2.399
			var px := top_c.x + rr * cos(ang)
			var pz := top_c.z + rr * sin(ang)
			var yy := top_c.y - (up.x * (px - top_c.x) + up.z * (pz - top_c.z)) / up.y
			var q := PhysicsRayQueryParameters3D.create(Vector3(px, top_c.y + 6.0, pz), Vector3(px, top_c.y - 8.0, pz))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				missing = true
				continue
			var ground: float = hit.position.y
			worst_sink = maxf(worst_sink, ground - yy)
			lowest_gap = minf(lowest_gap, yy - ground)
		if OS.get_environment("VERBOSE") != "":
			print("SPACE ", nd.name, " top ", snappedf(top_c.y, 0.01), " lowest gap ", snappedf(lowest_gap, 0.01), " sink ", snappedf(worst_sink, 0.01))
		if missing:
			bad_missing.append(nd.name)
		elif worst_sink > SINK_LIMIT:
			bad_sunk.append("%s(%.2f)" % [nd.name, worst_sink])
		elif lowest_gap > FLOAT_LIMIT:
			bad_float.append("%s(%.2f)" % [nd.name, lowest_gap])
	print("SPACECHECK board ", board_name, " spaces ", total, " floors ", floors.size())
	print("SPACECHECK sunk ", bad_sunk.size(), " ", bad_sunk.slice(0, 20))
	print("SPACECHECK floating ", bad_float.size(), " ", bad_float.slice(0, 20))
	print("SPACECHECK no ground ", bad_missing.size(), " ", bad_missing.slice(0, 20))
	quit(1 if (bad_sunk.size() + bad_float.size() + bad_missing.size()) > 0 else 0)

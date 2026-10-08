## Dev tool: loads every shop item, prints what it does and uses the action items on a running board.
##
##   godot --path . res://tools/board_check/item_test.tscn
extends Node


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
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
	var ctrl: Node = null
	var t := 0.0
	while ctrl == null and t < 90:
		await wait(0.5)
		t += 0.5
		for n in get_tree().get_nodes_in_group("Controller"):
			if get_node("/root/Server").is_ancestor_of(n) and n.players.size() == 4:
				ctrl = n
	await wait(6.0)
	var player = ctrl.players[0]
	for path in PluginSystem.item_loader.get_loaded_items():
		var item: Item = load(path).new()
		print("ITM %s: type %d cost %d icon %s | %s" % [item.name, item.type, item.item_cost, item.icon != null, item.get_description()])
		match item.type:
			Item.TYPES.DICE:
				var lo := 99
				var hi := 0
				for i in 300:
					var v: int = item.activate(player, ctrl)
					lo = mini(lo, v)
					hi = maxi(hi, v)
				print("ITM   rolls ", lo, "..", hi)
			Item.TYPES.ACTION:
				for p in ctrl.players:
					p.cookies = 10 + p.info.player_id * 2
				var before: Array = ctrl.players.map(func(p): return p.cookies)
				var space_before: Array = ctrl.players.map(func(p): return p.space.name)
				var result = item.activate(player, ctrl)
				print("ITM   result ", result, " cookies ", before, " -> ", ctrl.players.map(func(p): return p.cookies),
						" spaces ", space_before, " -> ", ctrl.players.map(func(p): return p.space.name))
				if result is Dictionary:
					print("ITM   text: ", tr(result.text).format(result.args))
	print("ITM ALL DONE")
	get_tree().quit()

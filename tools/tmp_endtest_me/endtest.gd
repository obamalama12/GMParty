## Dev tool: plays minigames to the end with bots (the human player stays idle or mashes buttons) and reports how
## they finished. Use it for the arcade minigames, which decide their own end.
##
##   GAMES=cookie_catch,hot_bomb MASH=1 godot --path . res://tools/arcade_test/arcade_test.tscn
##
## Lines starting with TEST are the report; MINIGAME_RESULT lines show the placement the game sent to the lobby.
extends Node

const TYPES := {"Duel": 0, "1v3": 1, "2v2": 2, "FFA": 3, "NolokSolo": 4, "NolokCoop": 5, "GnuSolo": 6, "GnuCoop": 7}
var client_lobby
var server_lobby


func log_(m) -> void:
	print("TEST ", m)


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func find_server_lobby():
	for c in get_node("/root/Server/Game").get_children():
		if "minigame_queue" in c:
			return c


func _ready() -> void:
	OS.set_environment("MINIGAME_RESULT_LOG", "1")
	await wait(1.0)
	var game := Global.create_local_server()
	await game.multiplayer.connected_to_server
	client_lobby = await game.create_lobby()
	await wait(1.0)
	client_lobby.set_player_name(0, "Tester")
	client_lobby.select_character(0, "Businessman")
	client_lobby.select_board("RetroValley")
	await wait(1.0)
	client_lobby.start()
	server_lobby = find_server_lobby()
	var t := 0.0
	while get_tree().get_nodes_in_group("Controller").size() < 2 and t < 60:
		await wait(0.5)
		t += 0.5
	await wait(6.0)
	var only: PackedStringArray = OS.get_environment("GAMES").split(",", false)
	var types_only: PackedStringArray = OS.get_environment("TYPES").split(",", false)
	for cfg in PluginSystem.minigame_loader.get_minigames():
		var mname: String = cfg.scene_path.get_base_dir().get_file()
		if not only.is_empty() and not (mname in only):
			continue
		for ty in cfg.type:
			if not types_only.is_empty() and not (ty in types_only):
				continue
			await run_minigame(cfg, mname, ty)
	log_("ALL DONE")
	get_tree().quit()


func run_minigame(cfg, mname: String, ty: String) -> void:
	var type: int = TYPES[ty]
	var label := mname + "_" + ty
	var state = Lobby.MinigameState.new()
	state.minigame_config = cfg
	state.minigame_type = type
	state.is_try = true
	match type:
		0:
			state.minigame_teams = [[1], [2]]
		1:
			state.minigame_teams = [[1, 2, 3], [4]]
		2:
			state.minigame_teams = [[1, 3], [2, 4]]
		3, 5, 7:
			state.minigame_teams = [[1, 2, 3, 4], []]
		4, 6:
			state.minigame_teams = [[1], []]
	if type == 6:
		var items: Array = PluginSystem.item_loader.get_buyable_items()
		server_lobby.minigame_reward = Lobby.MinigameReward.new()
		server_lobby.minigame_reward.gnu_solo_item_reward = load(items[0]).new()
	if type == 0:
		server_lobby.minigame_reward = Lobby.MinigameReward.new()
		server_lobby.minigame_reward.duel_reward = Lobby.MINIGAME_DUEL_REWARDS.TEN_COOKIES
	server_lobby.minigame_state = state
	var ctrl = Utility.get_nodes_in_group(server_lobby, "Controller")[0]
	ctrl.has_rolled = true
	server_lobby.broadcast(ctrl.splash_ended)
	server_lobby.broadcast(ctrl.show_minigame.bind(state.encode()))
	await wait(5.0)
	client_lobby.goto_minigame(true)
	await wait(4.0)
	var started := Time.get_ticks_msec()
	await apply_test_mode(cfg)
	var elapsed := 0.0
	var mash := OS.get_environment("MASH") == "1"
	var shots := OS.get_environment("SHOTS_DIR")
	var shot_times := []
	for part in OS.get_environment("SHOT_TIMES").split(",", false):
		shot_times.append(float(part))
	if shot_times.is_empty():
		shot_times = [6.0, 16.0]
	while elapsed < 100.0 and Utility.get_nodes_in_group(server_lobby, "Controller").size() == 0:
		if shots != "" and not shot_times.is_empty() and (Time.get_ticks_msec() - started) / 1000.0 >= shot_times[0]:
			shot_times.remove_at(0)
			DirAccess.make_dir_recursive_absolute(shots)
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [shots, label, int((Time.get_ticks_msec() - started) / 1000.0)])
		if mash:
			Input.action_press("player1_action1")
			await wait(0.07)
			Input.action_release("player1_action1")
			await wait(0.07)
			elapsed += 0.14
		else:
			await wait(0.5)
			elapsed += 0.5
	if orig_peer != -1:
		server_lobby.player_info[0].addr.peer_id = orig_peer
		orig_peer = -1
	var ok := Utility.get_nodes_in_group(server_lobby, "Controller").size() > 0
	log_("%s: %s after %.1f s of play" % [label, "FINISHED" if ok else "DID NOT FINISH", (Time.get_ticks_msec() - started) / 1000.0])
	await wait(4.0)


var orig_peer := -1

func find_scene(root: Node, path: String):
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.scene_file_path == path and not n.is_queued_for_deletion():
			return n
		stack.append_array(n.get_children())
	return null


func apply_test_mode(cfg) -> void:
	var mode := OS.get_environment("TESTMODE")
	if mode == "":
		return
	var srv = find_scene(get_node("/root/Server"), cfg.scene_path)
	var w := 0.0
	while srv == null and w < 30:
		await wait(1.0)
		w += 1.0
		srv = find_scene(get_node("/root/Server"), cfg.scene_path)
	var cli = find_scene(get_node("/root/Client"), cfg.scene_path)
	log_("test mode %s server scene=%s client scene=%s" % [mode, srv, cli])
	if srv == null:
		return
	match mode:
		"report":
			generic_report(srv)
		"bot":
			if cli:
				cli.get_node("Player1").set_physics_process(false)
			var p = srv.get_node("Player1")
			orig_peer = p.info.addr.peer_id
			p.info.addr.peer_id = 1
			p.set_multiplayer_authority(1)
			p.ai_current_waypoint = srv.get_node("Ground/Waypoint")
			p.ai_rand_start = 0.0
			bot_report(srv)
		"win":
			await wait(3.0)
			var fin = srv.get_node("Finish")
			srv.get_node("Player1").position = fin.position + Vector3(-1, 0.2, 0)
		"hit3":
			for i in 3:
				await wait(2.5)
				log_("hit, lives before %d" % srv.lives)
				srv.on_player_hit()
		"fall":
			await wait(3.0)
			var p = srv.get_node("Player1")
			var cp = cli.get_node("Player1")
			log_("fall from %s" % p.position)
			cp.position.y = -10
			p.position.y = -10
			await wait(2.0)
			log_("after fall: pos %s lives %d" % [p.position, srv.lives])
			p.position = srv.get_node("Finish").position + Vector3(-1, 0.2, 0)
		"timeout":
			srv.get_node("Timer2").start(3.0)


func bot_report(srv) -> void:
	for i in 40:
		await wait(2.0)
		if not is_instance_valid(srv) or srv.is_queued_for_deletion():
			return
		log_("t=%d pos=%s lives=%s boost=%s" % [i * 2, srv.get_node("Player1").position, srv.get("lives"), srv.get_node("Player1").boost_time])


func generic_report(srv) -> void:
	for i in 60:
		await wait(2.0)
		if not is_instance_valid(srv) or srv.is_queued_for_deletion():
			return
		var info := ""
		for prop in ["elapsed", "lives", "wave", "kills", "boost_time", "shield", "finished", "position"]:
			if prop in srv:
				info += " %s=%s" % [prop, srv.get(prop)]
		log_("t=%d ghosts=%d%s" % [i * 2, Utility.get_nodes_in_group(srv, "ghost").size(), info])

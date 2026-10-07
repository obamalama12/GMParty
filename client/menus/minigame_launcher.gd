extends Node
## Starts a local game on the first board and jumps straight into one minigame,
## so every minigame can be tried without playing through the board.
## Lives under the root node because the main menu is replaced while the game loads.

const TYPES := {"Duel": 0, "1v3": 1, "2v2": 2, "FFA": 3, "NolokSolo": 4, "NolokCoop": 5, "GnuSolo": 6, "GnuCoop": 7}
const TYPE_LABELS := {"NolokSolo": "Nolok Solo", "NolokCoop": "Nolok Co-op", "GnuSolo": "Joy Solo", "GnuCoop": "Joy Co-op"}

var config: MinigameLoader.MinigameConfigFile
var type_name := ""

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _find_server_lobby():
	var game := get_node_or_null("/root/Server/Game")
	if game == null:
		return null
	for c in game.get_children():
		if "minigame_queue" in c:
			return c
	return null

func run() -> void:
	var game := Global.create_local_server()
	if game == null:
		queue_free()
		return
	await game.multiplayer.connected_to_server
	var lobby = await game.create_lobby()
	if not lobby:
		Global.destroy_local_server()
		queue_free()
		return
	await _wait(0.5)
	lobby.set_player_name(0, "Player")
	var characters := PluginSystem.character_loader.get_loaded_characters()
	lobby.select_character(0, characters[0])
	lobby.select_board(PluginSystem.board_loader.get_loaded_boards()[0])
	await _wait(0.5)
	lobby.start()
	var server_lobby = _find_server_lobby()
	var waited := 0.0
	while get_tree().get_nodes_in_group("Controller").size() < 2 and waited < 60.0:
		await _wait(0.5)
		waited += 0.5
	await _wait(4.0)

	# The Mayor's opening dialog would cover the info screen's buttons
	for c in get_tree().get_nodes_in_group("Controller"):
		c.get_node("Screen/SpeechDialog").hide()
	var type: int = TYPES[type_name]
	var state := Lobby.MinigameState.new()
	state.minigame_config = config
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
	if type == 0:
		server_lobby.minigame_reward = Lobby.MinigameReward.new()
		server_lobby.minigame_reward.duel_reward = Lobby.MINIGAME_DUEL_REWARDS.TEN_COOKIES
	if type == 6:
		var items: Array = PluginSystem.item_loader.get_buyable_items()
		server_lobby.minigame_reward = Lobby.MinigameReward.new()
		server_lobby.minigame_reward.gnu_solo_item_reward = load(items[0]).new()
	server_lobby.minigame_state = state
	var ctrl = Utility.get_nodes_in_group(server_lobby, "Controller")[0]
	ctrl.has_rolled = true
	server_lobby.broadcast(ctrl.splash_ended)
	server_lobby.broadcast(ctrl.show_minigame.bind(state.encode()))
	queue_free()

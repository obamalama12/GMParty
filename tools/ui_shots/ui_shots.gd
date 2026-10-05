## Dev tool: screenshots of the menus and the board HUD.
##
## SHOTS_DIR=/tmp/ui godot --path . res://tools/ui_shots/ui_shots.tscn
extends Node

var dir := ""


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func snap(name: String) -> void:
	await wait(0.8)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("UI ", name)


func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await wait(0.12)
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await wait(0.4)


func _ready() -> void:
	dir = OS.get_environment("SHOTS_DIR") if OS.get_environment("SHOTS_DIR") != "" else "user://ui"
	DirAccess.make_dir_recursive_absolute(dir)
	var only := OS.get_environment("ONLY")
	await wait(2.0)
	# the main menu is the scene the game starts with: load it here as a child
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var menu: Node = load("res://client/menus/main_menu.tscn").instantiate()
	holder.add_child(menu)
	await snap("main_menu")
	menu._on_Options_pressed()
	await wait(1.5)
	await snap("options")
	menu.queue_free()
	await wait(0.5)
	var pause: PopupPanel = load("res://client/menus/pause_menu.tscn").instantiate()
	holder.add_child(pause)
	pause.popup_centered(Vector2i(420, 480))
	await snap("pause")
	pause.queue_free()
	var loading: Node = load("res://client/menus/loading_screen.tscn").instantiate()
	holder.add_child(loading)
	await snap("loading")
	loading.queue_free()
	await wait(0.5)

	var menu2: Node = load("res://client/menus/main_menu.tscn").instantiate()
	holder.add_child(menu2)
	await wait(1.0)
	menu2._on_Play_pressed()
	await wait(3.0)
	await snap("lobby")
	await press("player1_ok")
	await press("player1_ok")
	await snap("lobby_2")
	var lobby = menu2.lobby
	lobby.set_player_name(0, "Tester")
	lobby.select_character(0, "Businessman")
	await wait(1.0)
	lobby.select_board("MarkyValley")
	await snap("lobby_board")
	lobby.start()
	await wait(25.0)
	await snap("board_hud_1")
	await press("player1_ok")
	await wait(3.0)
	await snap("board_hud_2")
	var ctrl: Node = null
	for n in get_tree().get_nodes_in_group("Controller"):
		if get_node("/root/Server").is_ancestor_of(n):
			ctrl = n
	ctrl.prepare_minigame()
	await wait(2.5)
	await snap("minigame_intro")
	await wait(4.0)
	await snap("minigame_info")
	get_tree().quit()

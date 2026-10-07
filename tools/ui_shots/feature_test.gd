## Dev tool: screenshots of the lobby, the minigame test room, minigame launch and board zoom.
## SHOTS_DIR=/tmp/f godot --path . res://tools/ui_shots/feature_test.tscn
extends Node

var dir := ""

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func snap(n: String) -> void:
	await wait(0.8)
	get_viewport().get_texture().get_image().save_png(dir.path_join(n + ".png"))
	print("FT ", n)

func _ready() -> void:
	dir = OS.get_environment("SHOTS_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var menu: Node = load("res://client/menus/main_menu.tscn").instantiate()
	add_child(menu)
	await wait(1.5)
	await snap("main")
	menu._on_Minigames_pressed()
	await wait(1.0)
	await snap("minigames")
	var mg = menu.get_child(menu.get_child_count() - 1)
	var waited := 0.0
	var btn: Button
	for b in mg.find_children("*", "Button", true, false):
		if b.text == "Joy Solo":
			btn = b
			break
	if OS.get_environment("ZOOM") == "1":
		menu.get_child(menu.get_child_count() - 1).back.emit()
		await wait(0.5)
		menu._on_Play_pressed()
		await wait(3.0)
		var lb = menu.lobby
		lb.set_player_name(0, "Tester")
		lb.select_character(0, "Businessman")
		await wait(1.0)
		await snap("lobby")
		lb.start()
		waited = 0.0
		while get_tree().get_nodes_in_group("Controller").size() < 2 and waited < 90:
			await wait(1.0)
			waited += 1.0
		await wait(14.0)
		var ct
		for c in get_tree().get_nodes_in_group("Controller"):
			if not c.server:
				ct = c
		await snap("zoom0")
		ct._set_zoom(8.0)
		await wait(2.5)
		await snap("zoom1")
		ct._set_zoom(ct.ZOOM_OVERVIEW)
		await wait(2.5)
		await snap("zoom2")
		get_tree().quit()
		return
	btn.pressed.emit()
	waited = 0.0
	while get_tree().get_nodes_in_group("Controller").size() < 2 and waited < 90:
		await wait(1.0)
		waited += 1.0
	await wait(3.0)
	await snap("board_normal")
	var ctrl = get_tree().get_nodes_in_group("Controller")[0]
	for c in get_tree().get_nodes_in_group("Controller"):
		if not c.server:
			ctrl = c
	ctrl._set_zoom(ctrl.ZOOM_OVERVIEW)
	await wait(2.5)
	await snap("board_zoomed")
	await wait(8.0)
	await snap("info")
	print("FT DONE")
	get_tree().quit()

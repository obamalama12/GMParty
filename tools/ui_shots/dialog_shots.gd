## Dev tool: shows the speech dialog with every speaker and a very long text, and reports clipping.
extends Node


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var holder := Control.new()
	holder.theme = load("res://assets/defaults/default_theme.tres")
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var bg := ColorRect.new()
	bg.color = Color(0.4, 0.6, 0.4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var dlg: Control = load("res://common/scenes/speech_dialog/speech_dialog.tscn").instantiate()
	holder.add_child(dlg)
	var cases := [
		["CONTEXT_SPEAKER_SARA", "res://common/scenes/board_logic/controller/icons/host.png", "Mayor Pixel takes 8 cookies from Kit Bot and gives them to Timber Bot. Fair is fair!"],
		["CONTEXT_GNU_NAME", "res://common/scenes/board_logic/controller/icons/gnu_icon.png", "CONTEXT_GNU_SOLO_VICTORY"],
		["CONTEXT_NOLOK_NAME", "res://common/scenes/board_logic/controller/icons/nolokicon.png", "CONTEXT_NOLOK_EVENT_START"],
		["Averyveryverylongspeakername", "res://common/scenes/board_logic/controller/icons/host.png", "A very long text. " .repeat(12)],
	]
	for i in cases.size():
		var c: Array = cases[i]
		dlg._setup(c[0], load(c[1]), c[2], {"player": "Tester", "amount": 5}, 1)
		dlg.get_node("HBoxContainer/NinePatchRect/Name").text = tr(c[0])
		await wait(0.6)
		get_viewport().get_texture().get_image().save_png("%s/dialog%d.png" % [dir, i])
	get_tree().quit()

## Dev tool: screenshots of the "your turn" banner. SHOTS_DIR=/tmp/t godot --path . res://tools/ui_shots/banner_turn_test.tscn
extends Node

func _ready() -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.62, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var b := Control.new()
	b.set_script(load("res://common/scenes/board_logic/controller/turn_banner.gd"))
	add_child(b)
	await get_tree().process_frame
	var tex = PluginSystem.character_loader.load_character_splash("Businessman")
	b.play("Tester", tex, 3)
	for k in 5:
		await get_tree().create_timer(0.25).timeout
		get_viewport().get_texture().get_image().save_png("%s/b%d.png" % [dir, k])
	await get_tree().create_timer(1.0).timeout
	b.dismiss()
	await get_tree().create_timer(0.15).timeout
	get_viewport().get_texture().get_image().save_png("%s/b_out.png" % dir)
	get_tree().quit()

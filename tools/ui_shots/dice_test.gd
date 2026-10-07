extends Node
func _ready():
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.5, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var d = load("res://common/scenes/board_logic/controller/dice_roll.tscn").instantiate()
	add_child(d)
	for n in [5, 2, 4, 6, 1, 3]:
		d.play(n)
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png("%s/d%d_a.png" % [OS.get_environment("OUT"), n])
		await get_tree().create_timer(1.15).timeout
		get_viewport().get_texture().get_image().save_png("%s/d%d_b.png" % [OS.get_environment("OUT"), n])
		await d.finished
	get_tree().quit()

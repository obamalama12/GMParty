extends Node
func _ready():
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.55, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var holder := Control.new()
	holder.theme = load("res://assets/defaults/default_theme.tres")
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	holder.size = Vector2(1280, 720)
	var b = load("res://common/scenes/board_logic/controller/board_event_banner.gd").new()
	holder.add_child(b)
	b.size = Vector2(1280, 720)
	b.play("EVENT_ROBIN_HOOD", tr("EVENT_ROBIN_HOOD_TEXT").format({"from": "Kit Bot", "to": "Timber Bot", "amount": 8}))
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/banner.png")
	get_tree().quit()

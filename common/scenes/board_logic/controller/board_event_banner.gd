extends Control
## A banner with the title of a board event that pops in the middle of the screen.

var _panel: PanelContainer
var _title: Label
var _sub: Label


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(620, 200)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(box)
	var kicker := Label.new()
	kicker.text = "?  EVENT  ?"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override("font_color", Color("#ffe04a"))
	kicker.add_theme_font_size_override("font_size", 28)
	box.add_child(kicker)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLarge"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 26)
	box.add_child(_sub)


func play(title: String, sub: String) -> void:
	_title.text = tr(title)
	_sub.text = sub
	show()
	await get_tree().process_frame
	_panel.pivot_offset = _panel.size / 2
	_panel.scale = Vector2.ZERO
	_panel.rotation = deg_to_rad(-6)
	var pop := create_tween().set_parallel()
	pop.tween_property(_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_panel, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.7).timeout
	var out := create_tween().set_parallel()
	out.tween_property(_panel, "scale", Vector2(1.1, 0.0), 0.22)
	await out.finished
	hide()

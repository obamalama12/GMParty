extends PanelContainer

const PLACEMENT_COLORS := [Color("#FFE04A"), Color("#E9EEF5"), Color("#FFA95A"), Color("#BFC6E6")]

## One card colour per player slot, like the controller colours of the old consoles.
const CARDS := [
	preload("res://assets/ui/card_red.png"),
	preload("res://assets/ui/card_blue.png"),
	preload("res://assets/ui/card_green.png"),
	preload("res://assets/ui/card_yellow.png"),
]

var _style_slot := -1
var _bounce: Tween = null
var _highlighted := false


func _set_highlight(on: bool) -> void:
	if on == _highlighted and (_bounce != null or not on):
		return
	_highlighted = on
	pivot_offset = size / 2
	if _bounce:
		_bounce.kill()
		_bounce = null
	if on:
		_bounce = create_tween().set_loops()
		_bounce.tween_property(self, "scale", Vector2(1.07, 1.07), 0.45).set_trans(Tween.TRANS_SINE)
		_bounce.tween_property(self, "scale", Vector2(1.0, 1.0), 0.45).set_trans(Tween.TRANS_SINE)
	else:
		scale = Vector2.ONE
	modulate = Color.WHITE if on else Color(0.85, 0.85, 0.92)


func update(p: PlayerBoard, placement: int, highlighted: bool) -> void:
	var slot: int = (p.info.player_id - 1) % CARDS.size()
	if slot != _style_slot:
		_style_slot = slot
		var box := StyleBoxTexture.new()
		box.texture = CARDS[slot]
		box.texture_margin_left = 38
		box.texture_margin_top = 38
		box.texture_margin_right = 38
		box.texture_margin_bottom = 38
		box.content_margin_left = 22
		box.content_margin_top = 14
		box.content_margin_right = 18
		box.content_margin_bottom = 14
		add_theme_stylebox_override("panel", box)
	_set_highlight(highlighted)

	%Position.text = str(placement)
	%Position.set("theme_override_colors/font_color", PLACEMENT_COLORS[placement - 1])
	%Name.text = p.info.name

	if p.cookies_gui == p.cookies:
		%Cookies.text = str(p.cookies)
	elif p.destination.size() > 0:
		%Cookies.text = str(p.cookies_gui)
	elif p.cookies_gui > p.cookies:
		var diff := p.cookies_gui - p.cookies
		%Cookies.text = "-" + str(diff) + "  " + str(p.cookies_gui)
	else:
		var diff := p.cookies - p.cookies_gui
		%Cookies.text = "+" + str(diff) + "  " + str(p.cookies_gui)

	var character_loader := PluginSystem.character_loader
	var icon := character_loader.load_character_icon(p.info.character)
	%Icon.texture = icon
	%Cakes.text = str(p.cakes)
	for i in PlayerBoard.MAX_ITEMS:
		var item: Item = null
		if i < p.items.size():
			item = p.items[i]
		var texture_rect: TextureRect = %Items.get_child(i + 1)
		if item != null:
			texture_rect.texture = item.icon
		else:
			texture_rect.texture = null

		i += 1

extends Control
## "Your turn" banner: a slanted band in the player's colour that sweeps in from the left with the
## character portrait popping out of it, and sweeps out to the right again.

const PLAYER_COLORS := [Color("#e8483f"), Color("#3f84e8"), Color("#3fbf5f"), Color("#f2c030")]
const BAND_H := 150.0
const SLANT := 46.0
const SCALE := 0.7          # smaller than the full-size design
const BAND_W := 900.0

var _band: Control
var _poly_dark: Polygon2D
var _poly_accent: Polygon2D
var _poly_shine: Polygon2D
var _portrait: TextureRect
var _name: Label
var _title: Label
var _tween: Tween


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.size = Vector2(1000, BAND_H)
	add_child(_band)
	_poly_accent = Polygon2D.new()
	_band.add_child(_poly_accent)
	_poly_dark = Polygon2D.new()
	_band.add_child(_poly_dark)
	_poly_shine = Polygon2D.new()
	_band.add_child(_poly_shine)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(250, 250)
	_portrait.size = Vector2(250, 250)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = Vector2(60, BAND_H - 250.0 + 14.0)
	_band.add_child(_portrait)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 30)
	_name.add_theme_color_override("font_color", Color("#ffe04a"))
	_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name.add_theme_constant_override("outline_size", 6)
	_name.position = Vector2(330, 22)
	_name.size = Vector2(520, 40)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_band.add_child(_name)

	_title = Label.new()
	_title.theme_type_variation = &"HeaderLarge"
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_title.add_theme_constant_override("outline_size", 10)
	_title.position = Vector2(330, 56)
	_title.size = Vector2(700, 80)
	_title.clip_text = true
	_band.add_child(_title)


func _shape(w: float, h: float, inset: float = 0.0) -> PackedVector2Array:
	return PackedVector2Array([Vector2(SLANT + inset, inset), Vector2(w, inset), Vector2(w - SLANT, h - inset), Vector2(inset, h - inset)])


func play(player_name: String, texture: Texture2D, player_index: int) -> void:
	var color: Color = PLAYER_COLORS[(player_index - 1) % PLAYER_COLORS.size()]
	var screen_w := get_viewport_rect().size.x
	var w := BAND_W
	_band.scale = Vector2(SCALE, SCALE)
	_band.size = Vector2(w, BAND_H)
	_poly_accent.polygon = _shape(w, BAND_H + 12.0)
	_poly_accent.color = color
	_poly_dark.polygon = _shape(w, BAND_H, 0.0)
	_poly_dark.polygon = PackedVector2Array([Vector2(SLANT, 0), Vector2(w, 0), Vector2(w - SLANT, BAND_H), Vector2(0, BAND_H)])
	_poly_dark.color = Color(0.05, 0.08, 0.2, 0.9)
	_poly_shine.polygon = PackedVector2Array([Vector2(SLANT, 0), Vector2(w, 0), Vector2(w - SLANT * 0.5, BAND_H * 0.32), Vector2(SLANT * 0.2, BAND_H * 0.32)])
	_poly_shine.color = Color(1, 1, 1, 0.08)
	_poly_accent.position = Vector2(0, 6)
	_portrait.texture = texture
	_name.text = player_name.to_upper()
	_title.text = tr("CONTEXT_LABEL_YOUR_TURN").to_upper().replace("!", "")
	_title.modulate = color.lerp(Color.WHITE, 0.85)

	_play_sound("res://assets/sounds/ui/turn_start.wav")
	var y := get_viewport_rect().size.y * 0.42
	if _tween:
		_tween.kill()
	show()
	modulate.a = 1.0
	_band.position = Vector2(-w * SCALE - 20.0, y)
	_portrait.scale = Vector2.ZERO
	_portrait.pivot_offset = Vector2(125, 250)
	_name.modulate.a = 0.0
	_title.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_band, "position:x", (screen_w - w * SCALE) / 2.0, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_portrait, "scale", Vector2.ONE, 0.4).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_name, "modulate:a", 1.0, 0.2).set_delay(0.18)
	_tween.parallel().tween_property(_title, "modulate:a", 1.0, 0.2).set_delay(0.24)
	_tween.tween_callback(_idle)


# Gentle float while the banner waits for the player to roll
func _idle() -> void:
	_tween = create_tween().set_loops()
	_tween.tween_property(_portrait, "position:y", _portrait.position.y - 6.0, 0.9).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_portrait, "position:y", _portrait.position.y, 0.9).set_trans(Tween.TRANS_SINE)


func dismiss() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	_portrait.position.y = BAND_H - 250.0 + 14.0
	var out := create_tween()
	out.tween_property(_band, "position:x", get_viewport_rect().size.x + 20.0, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	out.tween_callback(hide)


func _play_sound(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Effects"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

extends CanvasLayer
## Autoload that draws the Nintendo 64 style post processing (see retro.gdshader) behind the user interface.

const LINES := 240.0

var enabled := true:
	set(value):
		enabled = value
		visible = value


func _ready() -> void:
	get_viewport().size_changed.connect(_update_resolution)
	_update_resolution()


func _update_resolution() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	($ColorRect.material as ShaderMaterial).set_shader_parameter("res", Vector2(roundf(LINES * aspect), LINES))

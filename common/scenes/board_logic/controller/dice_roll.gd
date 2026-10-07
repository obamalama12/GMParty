extends Control
## A big dice block that tumbles into the middle of the screen when a player rolls, then lands on the number.
## The dice is a plain cube whose faces come from assets/ui/dice_faces.png (opposite faces add up to 7).

signal finished

const FACE_TILES := 3
const ATLAS := preload("res://assets/ui/dice_faces.png")

@onready var dice: MeshInstance3D = $Container/Viewport/Dice

# face number -> [normal, right, up] of the face (right/up as seen from outside)
const FACES := {
	1: [Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	6: [Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	2: [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
	5: [Vector3.LEFT, Vector3.BACK, Vector3.UP],
	3: [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
	4: [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
}


func _ready() -> void:
	hide()
	dice.mesh = _build_mesh()
	var outline := StandardMaterial3D.new()
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = Color(0.063, 0.129, 0.353)
	outline.grow = true
	outline.grow_amount = 0.035
	var material := StandardMaterial3D.new()
	material.albedo_texture = ATLAS
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.roughness = 0.6
	material.next_pass = outline
	dice.material_override = material


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for number: int in FACES:
		var f: Array = FACES[number]
		var n: Vector3 = f[0]
		var r: Vector3 = f[1]
		var u: Vector3 = f[2]
		var tile := Vector2((number - 1) % FACE_TILES, (number - 1) / FACE_TILES)
		var tile_size := Vector2(1.0 / FACE_TILES, 1.0 / 2.0)
		var corners := [-r - u, r - u, r + u, -r + u]            # bottom left, bottom right, top right, top left
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv((tile + uvs[i]) * tile_size)
			st.add_vertex(n * 0.5 + corners[i] * 0.5)
	return st.commit()


## The rotation that turns the given face towards the camera.
func _target_basis(number: int) -> Basis:
	match number:
		6:
			return Basis(Vector3.UP, PI)
		2:
			return Basis(Vector3.UP, -PI / 2)
		5:
			return Basis(Vector3.UP, PI / 2)
		3:
			return Basis(Vector3.RIGHT, PI / 2)
		4:
			return Basis(Vector3.RIGHT, -PI / 2)
	return Basis.IDENTITY


var _glow: TextureRect
var _ring: TextureRect
var _badge: Label
var _sparks: CPUParticles2D
var _rays: TextureRect


func _make_effects() -> void:
	if _glow:
		return
	var holder := $Container
	# a soft glow behind the dice that pulses
	var glow_gradient := Gradient.new()
	glow_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	glow_gradient.colors = PackedColorArray([Color(1, 0.95, 0.6, 0.9), Color(1, 0.7, 0.2, 0.35), Color(1, 0.5, 0.1, 0.0)])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 256
	glow_texture.height = 256
	_glow = TextureRect.new()
	_glow.texture = glow_texture
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	move_child(_glow, 0)
	# the ring that flies outwards when it lands
	var ring_gradient := Gradient.new()
	ring_gradient.offsets = PackedFloat32Array([0.0, 0.72, 0.82, 0.9, 1.0])
	ring_gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 0.95, 0.5, 0.95), Color(1, 0.8, 0.2, 0), Color(1, 1, 1, 0)])
	var ring_texture := GradientTexture2D.new()
	ring_texture.gradient = ring_gradient
	ring_texture.fill = GradientTexture2D.FILL_RADIAL
	ring_texture.fill_from = Vector2(0.5, 0.5)
	ring_texture.fill_to = Vector2(1.0, 0.5)
	ring_texture.width = 256
	ring_texture.height = 256
	_ring = TextureRect.new()
	_ring.texture = ring_texture
	_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	# star burst
	_sparks = CPUParticles2D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.amount = 28
	_sparks.lifetime = 0.8
	_sparks.direction = Vector2.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 220.0
	_sparks.initial_velocity_max = 420.0
	_sparks.gravity = Vector2(0, 420)
	_sparks.scale_amount_min = 5.0
	_sparks.scale_amount_max = 11.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.9, 0.3), Color(1, 0.4, 0.6), Color(0.4, 0.85, 1.0), Color(1, 1, 1)])
	_sparks.color_initial_ramp = ramp
	add_child(_sparks)
	# the number that pops up above the dice
	_badge = Label.new()
	_badge.theme_type_variation = &"HeaderLarge"
	_badge.add_theme_font_size_override("font_size", 96)
	_badge.add_theme_color_override("font_color", Color("#ffe04a"))
	_badge.add_theme_constant_override("outline_size", 16)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)


func _place_effects() -> void:
	var c: Rect2 = Rect2($Container.position, $Container.size)
	var mid := c.get_center()
	_glow.size = Vector2(420, 420)
	_glow.position = mid - _glow.size / 2
	_ring.size = Vector2(300, 300)
	_ring.position = mid - _ring.size / 2
	_ring.pivot_offset = _ring.size / 2
	_sparks.position = mid
	_badge.size = Vector2(300, 120)
	_badge.position = mid + Vector2(-150, -c.size.y * 0.5 - 70)
	_badge.pivot_offset = _badge.size / 2


func play(number: int) -> void:
	_make_effects()
	await get_tree().process_frame
	_place_effects()
	show()
	modulate.a = 1.0
	_badge.text = ""
	_badge.scale = Vector2.ZERO
	_ring.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_glow.scale = Vector2.ONE * 0.4
	_glow.pivot_offset = _glow.size / 2
	# it comes to rest slightly turned, so the block still looks three-dimensional
	var tilt := Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.UP, 0.4)
	var target := (tilt * _target_basis(clampi(number, 1, 6))).get_euler()
	dice.rotation = target + Vector3(randf_range(3.0, 5.0), randf_range(3.0, 5.0), randf_range(1.0, 2.0)) * TAU
	dice.scale = Vector3.ONE * 0.15
	dice.position = Vector3(-1.3, 1.6, 0)
	$Rattle.play()
	var glow_in := create_tween().set_parallel()
	glow_in.tween_property(_glow, "modulate:a", 0.8, 0.5)
	glow_in.tween_property(_glow, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK)
	var spin := create_tween()
	spin.tween_property(dice, "rotation", target, 1.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var pop := create_tween()
	pop.tween_property(dice, "scale", Vector3.ONE * 0.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# it is thrown in from the side and bounces twice
	var travel := create_tween().set_parallel()
	travel.tween_property(dice, "position:x", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var hop := create_tween()
	hop.tween_property(dice, "position:y", -0.05, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).from(1.6)
	hop.tween_property(dice, "position:y", 0.65, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(dice, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.tween_property(dice, "position:y", 0.2, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(dice, "position:y", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await spin.finished
	$Land.play()
	get_tree().create_timer(0.12).timeout.connect($Chime.play)
	# landing: squash, ring, sparks and the number
	var land := create_tween()
	land.tween_property(dice, "scale", Vector3(1.05, 0.78, 1.05), 0.07)
	land.tween_property(dice, "scale", Vector3.ONE * 0.9, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ring.scale = Vector2.ONE * 0.5
	_ring.modulate.a = 1.0
	var ring_out := create_tween().set_parallel()
	ring_out.tween_property(_ring, "scale", Vector2.ONE * 1.9, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_out.tween_property(_ring, "modulate:a", 0.0, 0.55)
	_sparks.restart()
	_sparks.emitting = true
	_badge.text = str(number)
	var badge_in := create_tween()
	badge_in.tween_property(_badge, "scale", Vector2.ONE * 1.25, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	badge_in.tween_property(_badge, "scale", Vector2.ONE, 0.1)
	var pulse := create_tween().set_loops(3)
	pulse.tween_property(_glow, "scale", Vector2.ONE * 1.12, 0.25).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_glow, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.75).timeout
	var fade := create_tween().set_parallel()
	fade.tween_property(self, "modulate:a", 0.0, 0.25)
	fade.tween_property(dice, "scale", Vector3.ONE * 0.6, 0.25)
	await fade.finished
	hide()
	finished.emit()

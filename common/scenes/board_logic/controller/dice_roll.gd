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


func play(number: int) -> void:
	show()
	modulate.a = 1.0
	# it comes to rest slightly turned, so the block still looks three-dimensional
	var tilt := Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.UP, 0.4)
	var target := (tilt * _target_basis(clampi(number, 1, 6))).get_euler()
	dice.rotation = target + Vector3(randf_range(3.0, 5.0), randf_range(3.0, 5.0), randf_range(1.0, 2.0)) * TAU
	dice.scale = Vector3.ONE * 0.2
	dice.position = Vector3(0, -0.6, 0)
	var spin := create_tween()
	spin.tween_property(dice, "rotation", target, 1.05).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var pop := create_tween()
	pop.tween_property(dice, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var hop := create_tween()
	hop.tween_property(dice, "position:y", 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(dice, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await spin.finished
	# a little squash when it lands
	var land := create_tween()
	land.tween_property(dice, "scale", Vector3(1.12, 0.9, 1.12), 0.07)
	land.tween_property(dice, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.75).timeout
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.25)
	await fade.finished
	hide()
	finished.emit()

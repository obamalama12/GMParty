extends Node3D

func _process(delta):
	self.position.z += 10 * delta
	if self.position.z > 15:
		queue_free()

func _on_Area_body_entered(body):
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D:
		get_parent().on_player_hit()

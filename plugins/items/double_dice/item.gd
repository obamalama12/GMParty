extends Item

func _init() -> void:
	super(TYPES.DICE, "Double Dice")
	is_consumed = true

	can_be_bought = true
	item_cost = 4

func get_description() -> String:
	return "Roll two dice at once: anywhere from 2 to 12 steps!"

func activate(_player: Node3D, _controller: Node3D):
	return (randi() % 6) + 1 + (randi() % 6) + 1

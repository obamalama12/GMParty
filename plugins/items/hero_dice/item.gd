extends Item

func _init() -> void:
	super(TYPES.DICE, "Hero Dice")
	is_consumed = true

	can_be_bought = true
	item_cost = 5

func get_description() -> String:
	return "A mighty die that always rolls between 4 and 8."

func activate(_player: Node3D, _controller: Node3D):
	return (randi() % 5) + 4

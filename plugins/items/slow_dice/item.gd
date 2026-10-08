extends Item

func _init() -> void:
	super(TYPES.DICE, "Slow Dice")
	is_consumed = true

	can_be_bought = true
	item_cost = 2

func get_description() -> String:
	return "A gentle die that rolls only 1 to 3. Perfect for sneaking up on the cake!"

func activate(_player: Node3D, _controller: Node3D):
	return (randi() % 3) + 1

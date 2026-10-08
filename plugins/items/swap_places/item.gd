extends Item

func _init() -> void:
	super(TYPES.ACTION, "Swap Places")
	is_consumed = true

	can_be_bought = true
	item_cost = 7

func get_description() -> String:
	return "Swap places on the board with the player who has the most cakes. Hello, cake!"

func activate(player: Node3D, controller: Node3D):
	var target: Node3D = null
	for p in controller.players:
		if p == player:
			continue
		if target == null or p.cakes > target.cakes or (p.cakes == target.cakes and p.cookies > target.cookies):
			target = p
	if target == null:
		return null
	var mine: Node3D = player.space
	var theirs: Node3D = target.space
	player.teleport_to(theirs)
	target.teleport_to(mine)
	return {"title": "ITEM_SWAP_PLACES", "text": "ITEM_SWAP_PLACES_TEXT", "args": {"player": player.info.name, "other": target.info.name}}

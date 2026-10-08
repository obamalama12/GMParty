extends Item

func _init() -> void:
	super(TYPES.ACTION, "Cookie Bomb")
	is_consumed = true

	can_be_bought = true
	item_cost = 5

func get_description() -> String:
	return "Boom! Every other player loses 3 cookies. Do not stand too close."

func activate(player: Node3D, controller: Node3D):
	var total := 0
	for p in controller.players:
		if p != player:
			var lost := mini(3, p.cookies)
			p.cookies -= lost
			total += lost
	return {"title": "ITEM_COOKIE_BOMB", "text": "ITEM_COOKIE_BOMB_TEXT", "args": {"player": player.info.name, "amount": 3}}

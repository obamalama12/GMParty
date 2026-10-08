extends Item

func _init() -> void:
	super(TYPES.ACTION, "Pickpocket")
	is_consumed = true

	can_be_bought = true
	item_cost = 6

func get_description() -> String:
	return "Snatch up to 5 cookies from the richest player. They will never see it coming!"

func activate(player: Node3D, controller: Node3D):
	var victim: Node3D = null
	for p in controller.players:
		if p != player and (victim == null or p.cookies > victim.cookies):
			victim = p
	if victim == null or victim.cookies <= 0:
		return {"title": "ITEM_PICKPOCKET", "text": "ITEM_PICKPOCKET_EMPTY", "args": {"player": player.info.name}}
	var amount := mini(5, victim.cookies)
	victim.cookies -= amount
	player.cookies += amount
	return {"title": "ITEM_PICKPOCKET", "text": "ITEM_PICKPOCKET_TEXT", "args": {"player": player.info.name, "victim": victim.info.name, "amount": amount}}

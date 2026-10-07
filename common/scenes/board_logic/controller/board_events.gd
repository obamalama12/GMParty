class_name BoardEvents
extends RefCounted
## The "?" spaces: Mayor Pixel does something surprising to the player who lands on one.
## Every event changes the game on the server and returns what to tell the players: the title for the banner and the
## key and arguments of the text the mayor says.

const EVENTS := ["cookie_shower", "robin_hood", "free_item", "turbo_dice", "cookie_swap", "double_or_nothing", "cake_crumbs"]


# The event that happened last, so the same one never comes up twice in a row
static var _last_event := ""


## Picks and applies an event. Returns {"title": key, "text": key, "args": Dictionary}.
static func run(player: PlayerBoard, players: Array, controller: Controller) -> Dictionary:
	var choices: Array = EVENTS.filter(func(e): return e != _last_event)
	var name: String = choices.pick_random()
	_last_event = name
	if OS.get_environment("BOARD_EVENT") != "":
		name = OS.get_environment("BOARD_EVENT")
	match name:
		"robin_hood":
			return robin_hood(player, players, controller)
		"free_item":
			return free_item(player, players, controller)
		"turbo_dice":
			return turbo_dice(player, players, controller)
		"cookie_swap":
			return cookie_swap(player, players, controller)
		"double_or_nothing":
			return double_or_nothing(player, players, controller)
		"cake_crumbs":
			return cake_crumbs(player, players, controller)
	return cookie_shower(player, players, controller)


static func cookie_shower(player: PlayerBoard, players: Array, _controller: Controller) -> Dictionary:
	for p: PlayerBoard in players:
		p.cookies += 2
	player.cookies += 3
	return {"title": "EVENT_COOKIE_SHOWER", "text": "EVENT_COOKIE_SHOWER_TEXT", "args": {"player": player.info.name}}


static func robin_hood(player: PlayerBoard, players: Array, controller: Controller) -> Dictionary:
	var richest: PlayerBoard = players[0]
	var poorest: PlayerBoard = players[0]
	for p: PlayerBoard in players:
		if p.cookies > richest.cookies:
			richest = p
		if p.cookies < poorest.cookies:
			poorest = p
	if richest == poorest:
		return cookie_shower(player, players, controller)
	var amount := mini(4, richest.cookies)
	richest.cookies -= amount
	poorest.cookies += amount
	return {"title": "EVENT_ROBIN_HOOD", "text": "EVENT_ROBIN_HOOD_TEXT",
			"args": {"from": richest.info.name, "to": poorest.info.name, "amount": amount}}


static func free_item(player: PlayerBoard, players: Array, controller: Controller) -> Dictionary:
	var items: Array = PluginSystem.item_loader.get_buyable_items()
	if items.is_empty() or player.items.size() >= PlayerBoard.MAX_ITEMS:
		return cookie_shower(player, players, controller)
	var item: Item = load(items.pick_random()).new()
	player.give_item(item)
	return {"title": "EVENT_FREE_ITEM", "text": "EVENT_FREE_ITEM_TEXT", "args": {"player": player.info.name, "item": item.name}}


static func turbo_dice(player: PlayerBoard, _players: Array, _controller: Controller) -> Dictionary:
	player.add_roll_modifier(1, 2)
	return {"title": "EVENT_TURBO_DICE", "text": "EVENT_TURBO_DICE_TEXT", "args": {"player": player.info.name}}


static func cookie_swap(player: PlayerBoard, players: Array, controller: Controller) -> Dictionary:
	var others: Array = players.duplicate()
	others.erase(player)
	var other: PlayerBoard = others.pick_random()
	# A swap with a much richer player would be too big a swing: that becomes a small shower instead
	if other.cookies == player.cookies or absi(other.cookies - player.cookies) > 12:
		return cookie_shower(player, players, controller)
	var tmp := player.cookies
	player.cookies = other.cookies
	other.cookies = tmp
	return {"title": "EVENT_COOKIE_SWAP", "text": "EVENT_COOKIE_SWAP_TEXT", "args": {"player": player.info.name, "other": other.info.name}}


static func double_or_nothing(player: PlayerBoard, _players: Array, _controller: Controller) -> Dictionary:
	var amount := 5
	if randf() < 0.5:
		player.cookies += amount
		return {"title": "EVENT_GAMBLE", "text": "EVENT_GAMBLE_WIN", "args": {"player": player.info.name, "amount": amount}}
	var lost := mini(amount, player.cookies)
	player.cookies -= lost
	return {"title": "EVENT_GAMBLE", "text": "EVENT_GAMBLE_LOSE", "args": {"player": player.info.name, "amount": lost}}


static func cake_crumbs(player: PlayerBoard, _players: Array, _controller: Controller) -> Dictionary:
	# a sweet little bonus that also nudges a player who is close to buying a cake
	var amount := 2 + int(player.cakes == 0) * 2
	player.cookies += amount
	return {"title": "EVENT_CRUMBS", "text": "EVENT_CRUMBS_TEXT", "args": {"player": player.info.name, "amount": amount}}

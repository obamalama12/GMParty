class_name Awards
extends RefCounted
## Bonus awards handed out before the winner is announced: every award is worth one cake, so the game is not decided
## until the very end. They are worked out from the counters the board keeps for every player (PlayerState.stats).

# stat key, title, description, minimum value that counts
const LIST := [
	["mg_wins", "AWARD_MINIGAME", "AWARD_MINIGAME_TEXT", 1],
	["events", "AWARD_MYSTERY", "AWARD_MYSTERY_TEXT", 1],
	["items_used", "AWARD_GADGET", "AWARD_GADGET_TEXT", 1],
	["red_spaces", "AWARD_BLACK_CAT", "AWARD_BLACK_CAT_TEXT", 2],
	["blue_spaces", "AWARD_HAPPY", "AWARD_HAPPY_TEXT", 3],
	["steps", "AWARD_RUNNER", "AWARD_RUNNER_TEXT", 1],
]
const MAX_AWARDS := 3


## Returns up to MAX_AWARDS entries { "title", "text", "winners": [PlayerState], "value" } for the given player states.
static func compute(states: Array) -> Array:
	var result: Array = []
	for entry in LIST:
		if result.size() >= MAX_AWARDS:
			break
		var best := 0
		for s in states:
			best = maxi(best, int(s.stats.get(entry[0], 0)))
		if best < entry[3]:
			continue
		var winners: Array = states.filter(func(s): return int(s.stats.get(entry[0], 0)) == best)
		if winners.size() == states.size():
			continue        # everybody did the same: nothing to celebrate
		result.append({"title": entry[1], "text": entry[2], "winners": winners, "value": best})
	return result

class_name Quips
extends RefCounted
## Short, silly remarks of Mayor Pixel that pop up while the game is played. Every situation has a few lines (the
## translation keys QUIP_<SITUATION>_<n>); a random one is picked.

const COUNTS := {
	"LEADER": 4,
	"LAST": 4,
	"TIED": 3,
	"RED": 5,
	"CAKE": 4,
	"MINIGAME": 4,
	"POOR": 3,
}


static func pick(situation: String) -> String:
	return "QUIP_%s_%d" % [situation, 1 + randi() % COUNTS[situation]]

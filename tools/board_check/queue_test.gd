## Dev tool: draws minigames from the queue and reports back-to-back repeats.
extends Node

func _ready() -> void:
	var q = load("res://server/minigame_queue.gd").new()
	for kind in ["ffa", "1v3", "2v2", "duel"]:
		var seq := []
		for i in 40:
			seq.append(q.call("get_random_" + kind).scene_path.get_base_dir().get_file())
		var rep := 0
		for i in range(1, seq.size()):
			if seq[i] == seq[i - 1]:
				rep += 1
		print("QUEUE ", kind, " repeats ", rep, " ", seq.slice(0, 12))
	get_tree().quit()

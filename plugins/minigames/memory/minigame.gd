extends Node3D

var started := false
var finished := false

var lobby: Lobby

const TIME_LIMIT := 85.0
const SHUFFLE_AT_PAIRS := 6
const SND_GOLD := preload("res://assets/sounds/ui/round_win.wav")
const SND_SHUFFLE := preload("res://assets/sounds/ui/turn_start.wav")

var golden_variant := 1
var team_streak := [0, 0]
var pairs_matched := 0
var shuffled := false
var shuffling := false
var time_left := TIME_LIMIT

var clock_label: Label
var banner_label: Label
var gold_icon: TextureRect
var gold_label: Label
var banner_tween: Tween

func _enter_tree() -> void:
	lobby = Lobby.get_lobby(self)

func card_at(row: int, column: int) -> Node:
	return get_node("Row{0}/{1}".format([row, column]))

func _ready():
	_build_hud()
	if not is_multiplayer_authority():
		return
	golden_variant = 1 + randi() % 4
	$Player1.blocked = true
	$Player2.blocked = true
	$Player3.blocked = true
	$Player4.blocked = true

	var variants := [1, 2, 3, 4]

	var places_left := [
		$"Row1/1",
		$"Row1/2",
		$"Row1/3",
		$"Row2/1",
		$"Row2/2",
		$"Row2/3",
		$"Row3/1",
		$"Row3/2",
		$"Row3/3",
		$"Row4/1",
		$"Row4/2",
		$"Row4/3",
	]
	var places_right := [
		$"Row1/5",
		$"Row1/6",
		$"Row1/7",
		$"Row2/5",
		$"Row2/6",
		$"Row2/7",
		$"Row3/5",
		$"Row3/6",
		$"Row3/7",
		$"Row4/5",
		$"Row4/6",
		$"Row4/7",
	]
	places_left.shuffle()
	places_right.shuffle()

	while not places_left.is_empty() and not places_right.is_empty():
		var variant = variants[randi() % len(variants)]
		places_left.pop_back().variant = variant
		places_right.pop_back().variant = variant
	
	var data = [[], [], [], []]
	for i in range(6):
		data[0].append($Row1.get_child(i).variant)
		data[1].append($Row2.get_child(i).variant)
		data[2].append($Row3.get_child(i).variant)
		data[3].append($Row4.get_child(i).variant)
	lobby.broadcast(load_cards.bind(data, golden_variant))
	_set_golden(golden_variant)

	for i in range(6):
		$Row1.get_child(i).flip_up()
		$Row2.get_child(i).flip_up()
		$Row3.get_child(i).flip_up()
		$Row4.get_child(i).flip_up()
		await get_tree().create_timer(0.1).timeout

	await get_tree().create_timer(2).timeout
	for i in range(6):
		$Row1.get_child(i).flip_down()
		$Row2.get_child(i).flip_down()
		$Row3.get_child(i).flip_down()
		$Row4.get_child(i).flip_down()
		await get_tree().create_timer(0.1).timeout

	await get_tree().create_timer(0.5).timeout

	$Player1.blocked = false
	$Player2.blocked = false
	$Player3.blocked = false
	$Player4.blocked = false
	started = true

@rpc func load_cards(data, golden: int = 1):
	_set_golden(golden)
	for i in range(6):
		if not is_multiplayer_authority():
			$Row1.get_child(i).variant = data[0][i]
			$Row2.get_child(i).variant = data[1][i]
			$Row3.get_child(i).variant = data[2][i]
			$Row4.get_child(i).variant = data[3][i]

func _build_hud():
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme_var := &"HeaderLarge"
	clock_label = Label.new()
	clock_label.theme_type_variation = theme_var
	clock_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	clock_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	clock_label.offset_top = 8
	clock_label.add_theme_constant_override("outline_size", 6)
	clock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(clock_label)
	
	banner_label = Label.new()
	banner_label.theme_type_variation = theme_var
	banner_label.set_anchors_preset(Control.PRESET_CENTER)
	banner_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_label.text = ""
	layer.add_child(banner_label)
	
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -8
	layer.add_child(box)
	gold_icon = TextureRect.new()
	gold_icon.custom_minimum_size = Vector2(56, 56)
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.modulate = Color(1, 0.85, 0.25)
	box.add_child(gold_icon)
	gold_label = Label.new()
	gold_label.text = tr("MEMORY_GOLDEN_PAIR")
	gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.25))
	gold_label.add_theme_constant_override("outline_size", 6)
	gold_label.add_theme_color_override("font_outline_color", Color.BLACK)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(gold_label)
	_update_clock()

func _set_golden(variant: int):
	golden_variant = variant
	gold_icon.texture = load("res://plugins/minigames/memory/cards/card_{0}.png".format([variant]))

func _update_clock():
	clock_label.text = str(int(ceil(time_left)))
	clock_label.modulate = Color(1, 0.4, 0.3) if time_left < 15.0 else Color.WHITE

func _play(stream: AudioStream):
	# The server has no audio
	if multiplayer.is_server():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

@rpc func announce(text: String, color: Color, sound: int = 0):
	banner_label.text = text
	banner_label.modulate = color
	banner_label.pivot_offset = banner_label.size / 2.0
	banner_label.scale = Vector2(1.6, 1.6)
	if banner_tween:
		banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.tween_property(banner_label, "scale", Vector2.ONE, 0.2)
	banner_tween.tween_interval(1.3)
	banner_tween.tween_callback(banner_label.set.bind("text", ""))
	if sound == 1:
		_play(SND_GOLD)
	elif sound == 2:
		_play(SND_SHUFFLE)

@rpc func popup(pos: Vector3, text: String, color: Color):
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 96
	label.pixel_size = 0.012
	label.outline_size = 24
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3(0, 1.0, 0)
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", pos.y + 2.6, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)

@rpc func sync_time(t: float):
	time_left = t
	_update_clock()

# Called by the server when a team found a pair. Returns the points scored.
func score_pair(player: Node, card: Node) -> int:
	var team: int = player.team
	var points := 1
	var text := "+1"
	var color: Color = player.TEAM_COLORS[team]
	var sound := 0
	if card.variant == golden_variant:
		points = 3
		text = "+3"
		color = Color(1, 0.85, 0.25)
		sound = 1
	team_streak[team] += 1
	if team_streak[team] >= 2:
		var bonus := mini(team_streak[team] - 1, 2)
		points += bonus
		text = "+%d" % points
		text += "  " + tr("MEMORY_STREAK").format({"count": team_streak[team]})
	lobby.broadcast(popup.bind(card.global_position, text, color))
	popup(card.global_position, text, color)
	if sound != 0:
		lobby.broadcast(announce.bind(tr("MEMORY_GOLDEN_FOUND"), Color(1, 0.85, 0.25), 1))
		announce(tr("MEMORY_GOLDEN_FOUND"), Color(1, 0.85, 0.25), 1)
	pairs_matched += 1
	return points

func break_streak(team: int):
	team_streak[team] = 0

func _no_player_busy() -> bool:
	for player in [$Player1, $Player2, $Player3, $Player4]:
		if player.blocked:
			return false
	for row in range(1, 5):
		for column in range(1, 8):
			if column != 4 and card_at(row, column).is_animation_running():
				return false
	return true

# Twist halfway through: the remaining cards are shuffled and briefly shown again
func shuffle_twist():
	shuffling = true
	while not _no_player_busy():
		await get_tree().process_frame
	var players = [$Player1, $Player2, $Player3, $Player4]
	for player in players:
		player.blocked = true
		player.ai_target_row = -1
		player.ai_target_column = -1
	lobby.broadcast(announce.bind(tr("MEMORY_SHUFFLE"), Color(0.5, 0.9, 1.0), 2))
	announce(tr("MEMORY_SHUFFLE"), Color(0.5, 0.9, 1.0), 2)
	await get_tree().create_timer(0.8).timeout
	
	var unmatched := []
	for side in [[1, 3], [5, 7]]:
		var cards := []
		for row in range(1, 5):
			for column in range(side[0], side[1] + 1):
				var card = card_at(row, column)
				if not card.faceup:
					cards.append([row, column, card.variant])
		var variants := []
		for c in cards:
			variants.append(c[2])
		variants.shuffle()
		for i in cards.size():
			cards[i][2] = variants[i]
		unmatched.append_array(cards)
	lobby.broadcast(reshuffle.bind(unmatched))
	reshuffle(unmatched)
	
	for c in unmatched:
		card_at(c[0], c[1]).flip_up()
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(2.0).timeout
	for c in unmatched:
		card_at(c[0], c[1]).flip_down()
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.6).timeout
	for player in players:
		player.cooldown = 0.25
		player.blocked = false
	shuffling = false

@rpc func reshuffle(data: Array):
	for c in data:
		card_at(c[0], c[1]).variant = c[2]

func _process(delta):
	if not started:
		return
	
	if not finished:
		var old_second := int(ceil(time_left))
		time_left = max(time_left - delta, 0.0)
		if int(ceil(time_left)) != old_second:
			lobby.broadcast(sync_time.bind(time_left))
			_update_clock()
		if time_left <= 0.0:
			finished = true
			for player in [$Player1, $Player2, $Player3, $Player4]:
				player.blocked = true
			lobby.broadcast(announce.bind(tr("MEMORY_TIME_UP"), Color(1, 0.4, 0.3), 0))
			announce(tr("MEMORY_TIME_UP"), Color(1, 0.4, 0.3), 0)
			$Timer.start()
			return
		if not shuffled and pairs_matched >= SHUFFLE_AT_PAIRS and pairs_matched < 12:
			shuffled = true
			shuffle_twist()
	if shuffling:
		return
	
	var unmatched := 0
	var players = [$Player1, $Player2, $Player3, $Player4]
	for player in players:
		# If the player is holding a card open, then it's not yet matched
		# But it also isn't facedown anymore
		if player.blocked:
			unmatched += 1
	for row in range(1, 5):
		for column in range(1, 8):
			if column == 4:
				continue
			var card = card_at(row, column)
			if not card.faceup or card.is_animation_running():
				unmatched += 1
	if not unmatched and not finished:
		$Timer.start()
		finished = true

func _on_Timer_timeout():
	var team1 = $Player1.points + $Player2.points
	var team2 = $Player3.points + $Player4.points
	lobby.minigame_team_win_by_points([team1, team2])

extends Node3D

signal return_to_menu

func _input(event):
	if event.is_action_pressed("player1_ok"):
		return_to_menu.emit()

func _ready():
	var lobby := Lobby.get_lobby(self)
	for player in lobby.playerstates:
		var new_model = PluginSystem.character_loader.load_character(player.info.character)
		new_model.name = "Model"
		
		var i = player.info.player_id
		get_node("Player" + str(i)).add_child(new_model)
		
		$Summary/Stats/Names/Entries.get_node("Player" + str(i)).text = player.info.name
		$Summary/Stats/Cakes/Entries.get_node("Player" + str(i)).text = str(player.cakes)
		$Summary/Stats/Cookies/Entries.get_node("Player" + str(i)).text = str(player.cookies)
	
	$Player1/Model.play_animation("happy")
	$Player2/Model.play_animation("happy")
	$Player3/Model.play_animation("happy")
	$Player4/Model.play_animation("happy")
	
	await get_tree().create_timer(1).timeout
	
	$Scene/AnimationPlayer.play("KeyAction")
	
	await get_tree().create_timer(2).timeout
	
	var sara_tex = "res://common/scenes/board_logic/controller/icons/host.png"
	# the bonus awards come before the winner is known
	var bonus_cakes := {}
	for award in Awards.compute(lobby.playerstates):
		await _show_award(award, bonus_cakes)
	
	var winner = []
	for player in lobby.playerstates:
		var cakes: int = player.cakes + bonus_cakes.get(player.info.player_id, 0)
		if not winner or (winner[0].cakes + bonus_cakes.get(winner[0].info.player_id, 0) < cakes or (winner[0].cakes + bonus_cakes.get(winner[0].info.player_id, 0) == cakes and winner[0].cookies < player.cookies)):
			winner = [player]
		elif winner and winner[0].cakes + bonus_cakes.get(winner[0].info.player_id, 0) == cakes and winner[0].cookies == player.cookies:
			winner.append(player)
	
	var winner_names = []
	for w in winner:
		winner_names.append(w.info.name)
	
	$SpeechDialog.show_dialog("CONTEXT_SPEAKER_SARA", sara_tex, "CONTEXT_WINNER_ANNOUNCEMENT", 1)
	await $SpeechDialog.dialog_finished
	
	$AudioStreamPlayer2/AnimationPlayer.play("fade_out")
	await get_tree().create_timer(1).timeout
	$AudioStreamPlayer.play()
	
	var pos = Vector3(-(len(winner) - 1) / 2.0, 0, 2)
	for w in winner:
		var player = get_node("Player" + str(w.info.player_id))
		player.destination = pos
		player.get_node("Model").play_animation("run")
		pos.x += 1.0
	
	match len(winner):
		1: $SpeechDialog.show_dialog("CONTEXT_SPEAKER_SARA", sara_tex, "CONTEXT_WINNER_REVEAL_ONE_PLAYER", 1, winner_names)
		2: $SpeechDialog.show_dialog("CONTEXT_SPEAKER_SARA", sara_tex, "CONTEXT_WINNER_REVEAL_TWO_PLAYER", 1, winner_names)
		3: $SpeechDialog.show_dialog("CONTEXT_SPEAKER_SARA", sara_tex, "CONTEXT_WINNER_REVEAL_THREE_PLAYER", 1, winner_names)
		4: $SpeechDialog.show_dialog("CONTEXT_SPEAKER_SARA", sara_tex, "CONTEXT_WINNER_REVEAL_FOUR_PLAYER", 1, winner_names)
	$CameraMovement.play("closeup")
	
	await $SpeechDialog.dialog_finished
	$Summary.show()
	
	await self.return_to_menu
	
	lobby.end()


# A banner for one bonus award; the winners get a cake, which also shows in the summary.
func _show_award(award: Dictionary, bonus_cakes: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 260)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var kicker := Label.new()
	kicker.text = tr("AWARD_KICKER")
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override("font_color", Color("#ffe04a"))
	kicker.add_theme_font_size_override("font_size", 26)
	box.add_child(kicker)
	var title := Label.new()
	title.text = tr(award.title)
	title.theme_type_variation = &"HeaderLarge"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := Label.new()
	text.text = tr(award.text).format({"value": award.value})
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var faces := HBoxContainer.new()
	faces.alignment = BoxContainer.ALIGNMENT_CENTER
	faces.add_theme_constant_override("separation", 24)
	box.add_child(faces)
	for w in award.winners:
		var one := VBoxContainer.new()
		var face := TextureRect.new()
		face.texture = PluginSystem.character_loader.load_character_icon(w.info.character)
		face.custom_minimum_size = Vector2(84, 84)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		one.add_child(face)
		var name_label := Label.new()
		name_label.text = w.info.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		one.add_child(name_label)
		faces.add_child(one)
	var cake := Label.new()
	cake.text = tr("QUIP_BONUS_CAKE")
	cake.theme_type_variation = &"HeaderMedium"
	cake.add_theme_color_override("font_color", Color("#ff8fd0"))
	cake.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cake)

	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2.ZERO
	var pop := create_tween()
	pop.tween_property(panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var jingle := load("res://assets/sounds/ui/round_win.wav") as AudioStream
	if jingle:
		var player := AudioStreamPlayer.new()
		player.stream = jingle
		player.bus = &"Effects"
		overlay.add_child(player)
		player.play()
	await get_tree().create_timer(1.3).timeout
	for w in award.winners:
		var id: int = w.info.player_id
		bonus_cakes[id] = bonus_cakes.get(id, 0) + 1
		$Summary/Stats/Cakes/Entries.get_node("Player" + str(id)).text = str(w.cakes + bonus_cakes[id])
	await get_tree().create_timer(2.0).timeout
	var out := create_tween()
	out.tween_property(panel, "scale", Vector2(1.1, 0.0), 0.22)
	await out.finished
	overlay.queue_free()

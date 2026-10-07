extends Control
## Lists every minigame with one button per mode. Pressing one starts a game and opens that minigame
## (you play as Player 1, the other players are bots). "Try" on the info screen is a free practice run.

signal back

const LAUNCHER := preload("res://client/menus/minigame_launcher.gd")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://assets/defaults/default_theme.tres")
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = tr("MENU_MINIGAMES_TITLE")
	title.theme_type_variation = &"HeaderMedium"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := Label.new()
	hint.text = tr("MENU_MINIGAMES_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var entries := []
	for cfg in PluginSystem.minigame_loader.get_minigames():
		entries.append([_pretty_name(cfg), cfg])
	entries.sort_custom(func(a, b): return a[0] < b[0])
	var first: Button
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.text = entry[0]
		name_label.custom_minimum_size.x = 300
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		for ty in entry[1].type:
			if not (ty in LAUNCHER.TYPES):
				continue
			var button := Button.new()
			button.text = LAUNCHER.TYPE_LABELS.get(ty, ty)
			button.custom_minimum_size = Vector2(130, 46)
			button.pressed.connect(_launch.bind(entry[1], ty))
			row.add_child(button)
			if first == null:
				first = button
		list.add_child(row)

	var back_button := Button.new()
	back_button.text = tr("MENU_LABEL_BACK")
	back_button.custom_minimum_size = Vector2(190, 56)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.pressed.connect(back.emit)
	box.add_child(back_button)
	if first:
		first.grab_focus.call_deferred()
	else:
		back_button.grab_focus.call_deferred()

func _pretty_name(cfg: MinigameLoader.MinigameConfigFile) -> String:
	return cfg.scene_path.get_base_dir().get_file().replace("_", " ").capitalize()

func _launch(cfg: MinigameLoader.MinigameConfigFile, ty: String) -> void:
	# Freeze the menu so a second click cannot start a second game
	for b in find_children("*", "Button", true, false):
		b.disabled = true
	var launcher := Node.new()
	launcher.set_script(LAUNCHER)
	launcher.config = cfg
	launcher.type_name = ty
	get_tree().root.add_child(launcher)
	launcher.run()

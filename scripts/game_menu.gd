class_name GameMenu
extends CanvasLayer
## Pause menu: Esc or P pauses the game and opens it, and again resumes.
## Resume, Save game, Load game, Restart and Quit. Save and Load each show
## SaveGame.SLOTS slots. The start screen opens the Load page directly.
##
## It only opens while nothing else has paused the game (start screen, a
## machine screen or an ending), so it never fights those over the pause.

var _box: VBoxContainer
var _title: Label
var _note: Label
## True when opened from the start screen's "load" option.
var _from_title := false


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_menu")
	_ensure_pause_key()
	_build()
	visible = false
	# A load reloads the scene; put the save in place now it is ready.
	if SaveGame.pending:
		SaveGame.apply_pending.call_deferred(get_parent())


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	if event.is_echo():
		return
	if visible:
		get_viewport().set_input_as_handled()
		if _from_title:
			_close()
		else:
			_resume()
	elif not get_tree().paused:
		get_viewport().set_input_as_handled()
		open()


func open() -> void:
	_from_title = false
	get_tree().paused = true
	visible = true
	_show_main()


## Open straight on the load slots, over the start screen.
func open_load_from_title() -> void:
	_from_title = true
	visible = true
	_show_slots(false)


## Open straight on the settings page, over the start screen.
func open_settings_from_title() -> void:
	_from_title = true
	visible = true
	_show_settings()


func _resume() -> void:
	visible = false
	get_tree().paused = false


func _close() -> void:
	visible = false


# --- Pages --------------------------------------------------------------------

func _show_main() -> void:
	_clear()
	_title.text = "PAUSED"
	_note.text = "Hour %.1f of %d" % [Base.hour, int(Base.config.rescue_hours)]
	_add_button("Resume", _resume)
	_add_button("Save game", _show_slots.bind(true))
	_add_button("Load game", _show_slots.bind(false))
	_add_button("Settings", _show_settings)
	_add_button("Restart", _restart)
	_add_button("Quit", func() -> void: get_tree().quit())
	_focus_first()


func _show_slots(saving: bool) -> void:
	_clear()
	_title.text = "SAVE GAME" if saving else "LOAD GAME"
	_note.text = "Pick a slot to save over" if saving else "Pick a save to load"
	for slot in range(1, SaveGame.SLOTS + 1):
		var text := "Slot %d   %s" % [slot, SaveGame.describe(slot)]
		var b := _add_button(text, _on_slot.bind(slot, saving))
		b.disabled = not saving and not SaveGame.exists(slot)
	_add_button("Back", _close if _from_title else _show_main)
	_focus_first()


func _show_settings() -> void:
	_clear()
	_title.text = "SETTINGS"
	_note.text = "Saved automatically.  F11 full screen,  N sound"
	_add_button("Sound effects: %s" % ("ON" if Settings.sound_on else "OFF"), func() -> void:
		Settings.set_sound_on(not Settings.sound_on)
		_show_settings())
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.volume
	vol.custom_minimum_size = Vector2(420, 28)
	vol.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(v)
		Sfx.play("click"))
	var vol_label := Label.new()
	vol_label.text = "Volume"
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(vol_label)
	_box.add_child(vol)
	_add_button("Full screen: %s" % ("ON" if Settings.fullscreen else "OFF"), func() -> void:
		Settings.set_fullscreen(not Settings.fullscreen)
		_show_settings())
	_add_button("Background: %s" % Settings.background_name(), func() -> void:
		Settings.next_background()
		_show_settings())
	_add_button("Creator notes", _show_notes)
	_add_button("GitHub page", Settings.open_github)
	_add_button("Back", _close if _from_title else _show_main)
	_focus_first()


func _show_notes() -> void:
	_clear()
	_title.text = "CREATOR NOTES"
	_note.text = ""
	var notes := Label.new()
	notes.text = ("Moonbase: 72 Hours was made by Mahesh and team for Math Hacks 2.0.\n"
		+ "Every machine runs on rate equations, and the debrief at the end\n"
		+ "graphs how each resource changed over the run.\n\n"
		+ "(Placeholder: edit these notes in scripts/game_menu.gd.)")
	notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notes.add_theme_font_size_override("font_size", 18)
	_box.add_child(notes)
	_add_button("Back", _show_settings)
	_focus_first()


func _on_slot(slot: int, saving: bool) -> void:
	if saving:
		var err := SaveGame.save(slot, get_parent())
		_show_slots(true)
		_note.text = "Saved to slot %d" % slot if err == OK else "Could not save (error %d)" % err
	else:
		var err := SaveGame.load_slot(slot, get_tree())
		if err != OK:
			_note.text = "Could not load slot %d (error %d)" % [slot, err]


func _restart() -> void:
	get_tree().paused = false
	Base.reset()
	get_tree().reload_current_scene()


# --- Building -----------------------------------------------------------------

func _clear() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()


func _add_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if text.begins_with("Slot") else HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	_box.add_child(b)
	return b


func _focus_first() -> void:
	for child in _box.get_children():
		if child is Button and not child.disabled:
			var b: Button = child
			(func() -> void:
				if is_instance_valid(b) and b.is_inside_tree():
					b.grab_focus()).call_deferred()
			return


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.01, 0.04, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(col)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 48)
	_title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	col.add_child(_title)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 16)
	_note.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	col.add_child(_note)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	col.add_child(_box)

	var hint := Label.new()
	hint.text = "Arrows + Enter or click      Esc / P: back to the game"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.76))
	col.add_child(hint)


## Add a "pause" action bound to P if the project doesn't define one.
func _ensure_pause_key() -> void:
	if InputMap.has_action("pause"):
		return
	InputMap.add_action("pause")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	InputMap.action_add_event("pause", key)

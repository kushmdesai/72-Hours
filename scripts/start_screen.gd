class_name StartScreen
extends CanvasLayer
## Title screen shown when the game first launches. It pauses the game (so the
## Base model's clock doesn't run) until the player presses Enter, Space or clicks.
## Restarting with R after an ending skips it and goes straight back in.
## L opens the Load page of the GameMenu over it, and T starts the tutorial
## (scripts/tutorial.gd).

## True once the player has started a run, so scene reloads don't show it again.
static var started := false

var _hint: Label
var _blink := 0.0


func _ready() -> void:
	if started:
		queue_free()
		return
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_tree().paused = true


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta, 1.2)
	_hint.modulate.a = 1.0 if _blink < 0.8 else 0.25


func _unhandled_input(event: InputEvent) -> void:
	var menu := get_tree().get_first_node_in_group("game_menu") as GameMenu
	if menu and menu.visible:
		return
	if menu and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_L:
		get_viewport().set_input_as_handled()
		menu.open_load_from_title()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_T:
		get_viewport().set_input_as_handled()
		_start_tutorial()
		return
	var pressed := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and event.pressed:
		pressed = true
	if pressed:
		get_viewport().set_input_as_handled()
		_start()


func _start() -> void:
	started = true
	get_tree().paused = false
	queue_free()


## Reload the game with the tutorial guide on top (main.gd adds it).
func _start_tutorial() -> void:
	started = true
	Tutorial.active = true
	get_tree().paused = false
	Base.reset()
	get_tree().reload_current_scene()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.05, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	box.add_child(_label("MOONBASE", 72, Color(0.85, 0.92, 1.0)))
	box.add_child(_label("72 HOURS", 36, Color(1.0, 0.75, 0.3)))
	box.add_child(_label(
		"A meteor strike has crippled your lunar base.\n"
		+ "The rescue ship is 72 hours away and you are the only one awake.\n"
		+ "Keep oxygen, battery, water, temperature and food in their safe ranges until it lands.",
		18, Color(0.8, 0.85, 0.9)))
	box.add_child(_label(
		"A / D  move     W  jump     E  open a console / hold to repair     F  fast-forward",
		16, Color(0.55, 0.65, 0.75)))
	_hint = _label("Press Enter to start", 26, Color.WHITE)
	box.add_child(_label("New here? Press T for a short tutorial", 20, Color(1.0, 0.75, 0.3)))
	box.add_child(_label("L  load a saved game      Esc / P  pause, save and load during play", 15, Color(0.6, 0.66, 0.76)))
	box.add_child(_hint)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l

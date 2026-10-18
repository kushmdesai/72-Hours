class_name Tutorial
extends CanvasLayer
## Guided first run, opened with T on the title screen. It plays in the real
## Moonbase with the clock stopped (Base.running = false), so nothing breaks,
## no pods fall and no calamity comes while the player learns. A card in the
## top right gives one task at a time and moves on as soon as it is done:
## walking and jumping, the hydraulic doors, a machine screen and its ON/OFF
## switch, the HUD bars, the clock and a repair. Enter moves past the reading
## steps, Q leaves the tutorial at any time.

## Set by the title screen; main.gd adds a Tutorial when it is true.
static var active := false

## How far the player must walk for the first step, in pixels.
const WALK_PX := 240.0
## In-game hours the fast-forward step lets the clock run.
const CLOCK_HOURS := 1.5
## The door between the Habitat and the Heater room, and its x if not found.
const DOOR_NODE := "RoomDoors/HeaterHabitat"
const DOOR_X := 1936.0

const COLOR_TEXT := Color(0.88, 0.92, 1.0)
const COLOR_DIM := Color(0.6, 0.66, 0.76)
const COLOR_ACCENT := Color(1.0, 0.78, 0.35)
const COLOR_DONE := Color(0.4, 0.9, 0.55)

## id: what to check; text: the task; next: true if Enter moves on.
const STEPS := [
	{"id": "walk", "title": "MOVING",
		"text": "Walk left and right with A and D (or the arrow keys).\nLow gravity means less grip, so you take a moment to speed up and to stop."},
	{"id": "jump", "title": "JUMPING",
		"text": "Press W or Space to jump.\nThe Moon pulls at 1.62 m/s², about a sixth of Earth's, so a jump rises about 3 m and floats for nearly 4 s (h = v₀²/2g, t = 2v₀/g)."},
	{"id": "door", "title": "DOORS",
		"text": "Rooms are joined by hydraulic doors that slide open as you walk up to them.\nWalk left through the door into the Heater room."},
	{"id": "open", "title": "MACHINE SCREENS",
		"text": "Each room has a machine. Stand in front of the heater and press E to open its screen."},
	{"id": "switch", "title": "ON / OFF",
		"text": "The screen shows the heater's equation with today's numbers, and a what-if graph of the next 24 h with it ON and OFF.\nPress Space or Enter (or click the button) to switch it ON."},
	{"id": "close", "title": "ON / OFF",
		"text": "The heater is on now: its uᵢ term in the equation went from 0 to 1.\nPress E or Esc to close the screen."},
	{"id": "bars", "title": "RESOURCES", "next": true,
		"text": "The bars along the bottom are your five resources: oxygen, battery, water, temperature and food.\nThe red ends are the safe limits. Cross one and the run is over. Under each bar is its rate per hour and how long until it reaches a limit."},
	{"id": "systems", "title": "SYSTEMS AND CLOCKS", "next": true,
		"text": "Top left lists every machine, whether it is on and the power it draws against what the solar panels make. Beside it are your coins.\nBottom right, YOU LAST compares how long the base can hold out with the 72 hours until the rescue ship lands."},
	{"id": "clock", "title": "TIME",
		"text": "The clock is stopped for this tutorial. Hold F to fast-forward and watch the bars and rates change."},
	{"id": "repair", "title": "REPAIRS",
		"text": "Alarm! The heater has broken and flashes red. Machines break at random during a run.\nStand at the heater and hold E until the repair bar fills."},
	{"id": "more", "title": "BEYOND THE BASE", "next": true,
		"text": "Walk out through the airlocks to explore. The Landing Pad has a trade terminal: sell greenhouse food for coins (the price falls as you sell) and spend them on supply pods.\nThe ice tunnels under the base hold ice to drill for water and coal seams to dig for the coal generator, which keeps the battery up at night."},
	{"id": "end", "title": "CALAMITIES", "next": true,
		"text": "The Control Panel in the Habitat warns you hours before a calamity. While it warns, hold E there to pack survival packs and carry them down to the ice tunnels, then shelter there until it passes.\nKeep every bar inside its limits for 72 hours and board the rescue ship on the Landing Pad. Good luck!"},
]

var _step := -1
var _main: Node
var _player: CharacterBody2D
var _hud: Node
var _walked := 0.0
var _last_x := 0.0
var _airborne := false
var _clock_start := 0.0
var _panel_open := false
var _blink := 0.0

var _card: PanelContainer
var _title: Label
var _counter: Label
var _body: Label
var _footer: Label
var _banner: Label
var _highlight: Control
## Screen areas the highlight frames on the HUD steps.
var _rects: Array[Rect2] = []


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_parent()
	_player = _main.get_node("Player")
	Base.running = false
	Base.system_toggled.connect(_on_system_toggled)
	Base.failure_repaired.connect(_on_failure_repaired)
	get_tree().node_added.connect(_on_node_added)
	_build()
	# After main.gd has put the player at the start marker.
	_go.call_deferred(0)


func _process(delta: float) -> void:
	if _step < 0:
		return
	_blink = fmod(_blink + delta, 1.0)
	_layout()
	if get_tree().paused:
		return
	if not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud")
	var x := _player.global_position.x
	match _id():
		"walk":
			_walked += absf(x - _last_x)
			if _walked >= WALK_PX:
				_go(_step + 1)
		"jump":
			if not _player.is_on_floor():
				_airborne = true
			elif _airborne:
				_go(_step + 1)
		"door":
			var door := _main.current.get_node_or_null(DOOR_NODE) as Node2D if _main.current else null
			var door_x := door.global_position.x if door else DOOR_X
			if x < door_x - 60.0:
				_go(_step + 1)
		"clock":
			# Let the clock run only while this step is up.
			Base.running = true
			if Base.hour - _clock_start >= CLOCK_HOURS:
				Base.running = false
				_go(_step + 1)
	_last_x = x


func _unhandled_input(event: InputEvent) -> void:
	if _step < 0 or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_Q:
		get_viewport().set_input_as_handled()
		_finish()
	elif (key == KEY_ENTER or key == KEY_KP_ENTER) and STEPS[_step].get("next", false) \
			and not _panel_open:
		get_viewport().set_input_as_handled()
		if _step == STEPS.size() - 1:
			_finish()
		else:
			_go(_step + 1)


func _id() -> String:
	return STEPS[_step].id


func _go(step: int) -> void:
	_step = step
	_walked = 0.0
	_airborne = false
	_last_x = _player.global_position.x
	var s: Dictionary = STEPS[step]
	_title.text = s.title
	_counter.text = "%d / %d" % [step + 1, STEPS.size()]
	_body.text = s.text
	if s.get("next", false):
		_footer.text = "Enter: " + ("back to the title screen" if step == STEPS.size() - 1 else "next") \
				+ "     Q: leave the tutorial"
	else:
		_footer.text = "Q: leave the tutorial"
	match s.id:
		"switch":
			# The heater starts off; if it was switched on already, ask for OFF.
			if Base.switches.heater:
				_body.text = _body.text.replace("switch it ON", "switch it OFF")
		"close":
			if not Base.switches.heater:
				_body.text = "The heater is off now: its uᵢ term in the equation went from 1 to 0.\nPress E or Esc to close the screen."
			if not _panel_open:
				_go.call_deferred(step + 1)
		"clock":
			_clock_start = Base.hour
		"repair":
			Base.trigger_failure("heater_fault")
	_card.modulate.a = 0.0
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.25)


func _on_node_added(node: Node) -> void:
	if node is SystemPanel:
		_panel_open = true
		node.tree_exited.connect(_on_panel_closed)
		if _id() == "open" and node.site == "heater":
			_go(_step + 1)


func _on_panel_closed() -> void:
	_panel_open = false
	if _id() == "close":
		_go(_step + 1)
	elif _id() == "switch":
		_go(_step - 1)


func _on_system_toggled(system: String, _on: bool) -> void:
	if _id() == "switch" and system == "heater":
		_go(_step + 1)


func _on_failure_repaired(_failure: String) -> void:
	if _id() == "repair":
		_go(_step + 1)


## Back to the title screen with a fresh base.
func _finish() -> void:
	active = false
	StartScreen.started = false
	get_tree().paused = false
	Base.reset()
	get_tree().reload_current_scene()


# --- Display ----------------------------------------------------------------

## While a machine screen is open the card would cover it, so the task shows
## as one line across the top instead. On the HUD steps a blinking frame marks
## the part of the screen being explained.
func _layout() -> void:
	_card.visible = not _panel_open
	_banner.visible = _panel_open
	if _panel_open:
		_banner.text = _body.text.get_slice("\n", _body.text.get_slice_count("\n") - 1)
	_rects.clear()
	if is_instance_valid(_hud) and not _panel_open:
		match _id():
			"bars", "clock":
				var strip := Rect2()
				for row: Dictionary in _hud.get("_rows").values():
					var r: Rect2 = row.panel.get_global_rect()
					strip = r if strip.size == Vector2.ZERO else strip.merge(r)
				_rects.append(strip)
			"systems":
				for panel: String in ["_systems_panel", "_coin_panel", "_clock_panel"]:
					var c := _hud.get(panel) as Control
					if c and c.is_visible_in_tree():
						_rects.append(c.get_global_rect())
	_highlight.visible = not _rects.is_empty()
	if _highlight.visible:
		_highlight.modulate.a = 1.0 if _blink < 0.6 else 0.35
		_highlight.queue_redraw()


func _build() -> void:
	_highlight = Control.new()
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.draw.connect(func() -> void:
		for r in _rects:
			_highlight.draw_rect(r.grow(4.0), COLOR_ACCENT, false, 3.0))
	add_child(_highlight)

	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.13, 0.94)
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", style)
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -440.0
	_card.offset_right = -12.0
	_card.offset_top = 12.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = _label("", 18, COLOR_ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_counter = _label("", 13, COLOR_DIM)
	header.add_child(_counter)
	_body = _label("", 15, COLOR_TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 400.0
	box.add_child(_body)
	_footer = _label("", 12, COLOR_DIM)
	box.add_child(_footer)

	_banner = _label("", 16, COLOR_ACCENT)
	_banner.anchor_right = 1.0
	_banner.offset_top = 10.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 5)
	_banner.visible = false
	add_child(_banner)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

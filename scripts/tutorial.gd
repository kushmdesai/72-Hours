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
const PAD := "res://scenes/locations/landing_pad.tscn"
const TUNNELS := "res://scenes/locations/tunnels.tscn"

const COLOR_TEXT := Color(0.88, 0.92, 1.0)
const COLOR_DIM := Color(0.6, 0.66, 0.76)
const COLOR_ACCENT := Color(1.0, 0.78, 0.35)
const COLOR_DONE := Color(0.4, 0.9, 0.55)

## The four parts of the tutorial, shown on the card.
const PARTS := ["", "THE BASE", "THE LANDING PAD", "THE ICE TUNNELS", "SURVIVING A CALAMITY"]
const MISSION := "Mission: keep all five resources in their safe range for 72 hours, then board the rescue ship."

## id: what to check; part: which PARTS it belongs to; why: how it helps you
## survive; text: the task; next: true if Enter moves on.
const STEPS := [
	{"id": "goal", "part": 0, "title": "YOUR MISSION", "next": true,
		"text": "A meteor has crippled your moonbase and you are the only one awake. A rescue ship lands in 72 hours.\nUntil then, keep oxygen, battery, water, temperature and food between their safe limits. If any one crosses a limit, the run is over. When the ship lands, board it on the Landing Pad to win.\nThis tutorial teaches the tools for that in four parts: the base, the Landing Pad, the ice tunnels and surviving a calamity. Press Enter to begin."},
	{"id": "walk", "part": 1, "why": "You'll be running between machines all game.", "title": "MOVING",
		"text": "Walk left and right with A and D (or the arrow keys).\nLow gravity means less grip, so you take a moment to speed up and to stop."},
	{"id": "jump", "part": 1, "why": "Supply pods hang in the air, so you need a jump to grab them.", "title": "JUMPING",
		"text": "Press W or Space to jump.\nThe Moon pulls at 1.62 m/s², about a sixth of Earth's, so a jump rises about 3 m and floats for nearly 4 s (h = v₀²/2g, t = 2v₀/g)."},
	{"id": "door", "part": 1, "why": "Each machine sits in its own room, joined by these doors.", "title": "DOORS",
		"text": "Rooms are joined by hydraulic doors that slide open as you walk up to them.\nWalk left through the door into the Heater room."},
	{"id": "open", "part": 1, "why": "Machine screens are where you control the base.", "title": "MACHINE SCREENS",
		"text": "Each room has a machine. Stand in front of the heater and press E to open its screen."},
	{"id": "switch", "part": 1, "why": "Switching machines on and off is how you steer every resource.", "title": "ON / OFF",
		"text": "The screen shows the heater's equation with today's numbers, and a what-if graph of the next 24 h with it ON and OFF.\nPress Space or Enter (or click the button) to switch it ON."},
	{"id": "close", "part": 1, "why": "Switching machines on and off is how you steer every resource.", "title": "ON / OFF",
		"text": "The heater is on now: its uᵢ term in the equation went from 0 to 1.\nPress E or Esc to close the screen."},
	{"id": "bars", "part": 1, "why": "These bars decide whether you win or lose: watch them all game.", "title": "RESOURCES", "next": true,
		"text": "The bars along the bottom are your five resources: oxygen, battery, water, temperature and food.\nThe red ends are the safe limits. Cross one and the run is over. Under each bar is its rate per hour and how long until it reaches a limit."},
	{"id": "systems", "part": 1, "why": "Power is limited: every machine you run drains the battery.", "title": "SYSTEMS AND CLOCKS", "next": true,
		"text": "Top left lists every machine, whether it is on and the power it draws against what the solar panels make. Beside it are your coins.\nBottom right, YOU LAST compares how long the base can hold out with the 72 hours until the rescue ship lands."},
	{"id": "clock", "part": 1, "why": "Fast-forward skips quiet stretches. It stops by itself when something breaks.", "title": "TIME",
		"text": "The clock is stopped for this tutorial. Hold F to fast-forward and watch the bars and rates change."},
	{"id": "repair", "part": 1, "why": "A broken machine stops working until you fix it.", "title": "REPAIRS",
		"text": "Alarm! The heater has broken and flashes red. Machines break at random during a run.\nStand at the heater and hold E until the repair bar fills."},
	{"id": "to_pad", "part": 2, "why": "Trading, supply pods and the rescue ship are all on the pad.", "title": "THE LANDING PAD",
		"text": "Time to go outside. Walk right, through the Habitat and out of the East Airlock, to the Landing Pad."},
	{"id": "sell", "part": 2, "why": "Coins buy whatever the base is running short of.", "title": "COINS: SELLING FOOD",
		"text": "The trade terminal is on the left of the pad. The market pays p(s) = 20 · 0.9ˢ coins per kg after s kg sold, so every kilogram is worth 10% less than the last, and a sale pays the area under that curve.\nWalk to the terminal, press E and click Sell 2.0 kg."},
	{"id": "buy", "part": 2, "why": "Coins buy whatever the base is running short of.", "title": "COINS: SUPPLY PODS",
		"text": "Coins buy supply pods: oxygen, water, food, or a toolkit that fixes everything. A food pod costs 25 coins and puts back what you sold.\nClick Food pod to order one."},
	{"id": "catch", "part": 2, "why": "A pod only counts once you collect it.", "title": "CATCHING A POD",
		"text": "Your pod is parachuting onto the pad. Pods hang in the air, so you need a moon jump to reach them. Free pods also fall here every few hours during a run.\nClose the screen with E, then jump into the pod to collect it."},
	{"id": "hatch", "part": 3, "why": "The tunnels hold extra water, fuel and your only shelter.", "title": "THE ICE TUNNELS",
		"text": "Under the base are the ice tunnels: water ice, coal, and the only shelter from a calamity.\nWalk right to the hatch and press E to climb down."},
	{"id": "coal_dig", "part": 3, "why": "Solar panels make nothing at night. Coal keeps the battery up.", "title": "COAL",
		"text": "The dark rock past the Coal Generator is a coal seam.\nWalk right to it and hold E to dig coal into the generator's hopper."},
	{"id": "coal_on", "part": 3, "why": "Solar panels make nothing at night. Coal keeps the battery up.", "title": "THE COAL GENERATOR",
		"text": "Coal powers the battery when the sun is down. Burning at b = 1 kg/h it adds 3 kW, so the hopper's C kg lasts C/b hours (dC/dt = −b·u).\nWalk back to the Coal Generator, press E and switch it ON."},
	{"id": "close_coal", "part": 3, "why": "Solar panels make nothing at night. Coal keeps the battery up.", "title": "THE COAL GENERATOR",
		"text": "The battery's equation now has a +3 kW term while the coal lasts.\nPress E or Esc to close the screen."},
	{"id": "ice", "part": 3, "why": "Ice tops up the water tank when it runs low.", "title": "ICE",
		"text": "The blue crystals are an ice vein. Each pass of the drill brings r times the last load, a geometric series, so a vein holds a/(1 − r) litres in all. Melting it costs battery.\nWalk right to the ice and hold E to drill water."},
	{"id": "drill", "part": 4, "why": "Calamities are the biggest danger in a run.", "title": "CALAMITY DRILL", "next": true,
		"text": "About once a day a calamity strikes: a black hole, an alien UFO raid or an asteroid shower. Anyone on the surface dies, and the machines get damaged.\nThe Control Panel in the Habitat warns 6 hours ahead. Press Enter to start an asteroid shower drill."},
	{"id": "pack", "part": 4, "why": "The base is shut down while it passes, so you live off what you pack.", "title": "PACK SUPPLIES",
		"text": "The base shuts down while it passes, so you live off what you bring. It lasts 2 hours, and each pack holds 1 hour of air, water and food, so you need two.\nClimb the ladder, go back into the Moonbase to the Control Panel in the Habitat and hold E to pack twice."},
	{"id": "carry", "part": 4, "why": "Being on the surface when it hits ends the run.", "title": "TAKE SHELTER",
		"text": "Now carry the packs down to the ice tunnels. They are unpacked into the shelter as soon as you arrive.\nGo back out to the Landing Pad and down the hatch."},
	{"id": "wait", "part": 4, "why": "Resources freeze during the shutdown, so the base waits for you.", "title": "RIDE IT OUT",
		"text": "An hour before it hits, the base shuts down: resources freeze, machines ice over and you move at quarter speed. Stay down here until it passes.\nHold F to fast-forward (press it again if an alarm stops it)."},
	{"id": "after", "part": 4, "why": "Damaged machines stay broken until you repair them.", "title": "AFTERMATH", "next": true,
		"text": "You survived the shower, but it broke machines. The red list above the HUD says where to repair each one: hold E there as you did with the heater, or buy a toolkit pod to fix everything at once."},
	{"id": "end", "part": 4, "title": "READY", "next": true,
		"text": "That's the whole game. Your mission: keep every bar inside its limits for 72 hours, then board the rescue ship on the Landing Pad.\nEsc pauses, saves and loads. After a run, press M on the end screen for a math debrief: graphs and equations of how your resources changed."},
]

var _step := -1
var _main: Node
var _player: CharacterBody2D
var _hud: Node
var _walked := 0.0
var _last_x := 0.0
var _airborne := false
var _clock_start := 0.0
## Coins when the current step began, to see a sale or a purchase.
var _coins_mark := 0.0
var _controller: Node
var _panel_open := false
var _blink := 0.0

var _card: PanelContainer
var _title: Label
var _counter: Label
var _body: Label
var _part: Label
var _why: Label
var _mission: Label
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
	Base.supplies_added.connect(_on_supplies_added)
	# The trade screen pauses the game, so sales are caught by signal.
	Base.coins_changed.connect(_on_coins_changed)
	_controller = get_tree().get_first_node_in_group("systems_controller")
	_drops().pod_collected.connect(func(_pod: Dictionary) -> void:
		if _id() == "catch":
			_go(_step + 1))
	_dangers().passed.connect(func() -> void:
		if _id() == "wait":
			Base.running = false
			_go(_step + 1))
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
		"to_pad":
			if _at(PAD):
				_go(_step + 1)
		"hatch":
			if _at(TUNNELS):
				_go(_step + 1)
		"coal_dig":
			if Base.coal > 0.0:
				_go(_step + 1)
		"pack":
			var d := _dangers()
			if d.hours_of(d.carried) + d.hours_of(d.shelter) >= d.duration_hours - 0.01:
				_go(_step + 1)
		"carry":
			var d := _dangers()
			if d.sheltered() and d.hours_of(d.shelter) >= d.duration_hours - 0.01:
				_go(_step + 1)
		"wait":
			Base.running = true
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
	_part.text = "PART %d OF 4 · %s" % [s.part, PARTS[s.part]] if s.part > 0 else "MOONBASE: 72 HOURS"
	_body.text = s.text
	_why.text = "Why: " + s.why if s.has("why") else ""
	_why.visible = s.has("why")
	_mission.visible = s.id != "goal"
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
		"sell", "buy":
			_coins_mark = Base.coins
		"close_coal":
			if not _panel_open:
				_go.call_deferred(step + 1)
		"pack":
			# An asteroid shower 4 h away: inside the 6 h warning, so the
			# Control Panel lets the player pack straight away.
			var d := _dangers()
			d.kind = "asteroids"
			d.arrive_hour = Base.hour + 4.0
	_card.modulate.a = 0.0
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.25)


func _on_node_added(node: Node) -> void:
	if node is SystemPanel or node is TradePanel:
		_panel_open = true
		node.tree_exited.connect(_on_panel_closed)
		if _id() == "open" and node is SystemPanel and node.site == "heater":
			_go(_step + 1)


func _on_panel_closed() -> void:
	_panel_open = false
	if _id() in ["close", "close_coal"]:
		_go(_step + 1)
	elif _id() == "switch":
		_go(_step - 1)


func _on_system_toggled(system: String, on: bool) -> void:
	if _id() == "switch" and system == "heater":
		_go(_step + 1)
	elif _id() == "coal_on" and system == "coal" and on:
		_go(_step + 1)


func _on_supplies_added(resource: String, amount: float) -> void:
	if _id() == "ice" and resource == "water" and amount > 0.0:
		_go(_step + 1)


func _on_coins_changed(coins: float) -> void:
	if (_id() == "sell" and coins > _coins_mark + 0.01) \
			or (_id() == "buy" and coins < _coins_mark - 0.01):
		_go(_step + 1)


## True if the player is in the location at this scene path.
func _at(path: String) -> bool:
	return _main.current != null and _main.current.scene_file_path == path


func _drops() -> SupplyDrops:
	return _controller.get("_drops")


func _dangers() -> DangerEvents:
	return _controller.get("_dangers")


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
	# Sit below the calamity banner along the top while it shows.
	_card.offset_top = maxf(12.0, _dangers().banner_bottom() + 8.0)
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
	_part = _label("", 12, COLOR_DIM)
	box.add_child(_part)
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
	_why = _label("", 14, COLOR_DONE)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size.x = 400.0
	box.add_child(_why)
	# The goal stays on the card at every step.
	_mission = _label(MISSION, 13, COLOR_ACCENT)
	_mission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission.custom_minimum_size.x = 400.0
	box.add_child(_mission)
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

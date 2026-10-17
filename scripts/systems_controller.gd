class_name SystemsController
extends Node2D
## Connects the Base model to the map: switches, repairs, alarms and the end screen.
##
## Walk up to a system console in the Moonbase and press E to switch that system
## on or off (its u_i term in the equations). The Solar Control console connects
## or disconnects the panels, to stop a full battery overcharging. When something has failed, hold E
## at the console (or at any solar panel for dust) to repair it. Console screens
## show green = on, grey = off, flashing red = broken.

## How close the player must stand to a console or panel, in pixels.
@export var reach_px: float = 48.0
## Real seconds E must be held to finish a repair.
@export var repair_seconds: float = 2.0

const SYSTEM_LABELS := {
	"solar": "solar panels",
	"oxygen": "oxygen generator",
	"water": "water recycler",
	"heater": "heater",
}
const COLOR_ON := Color(0.3, 0.9, 0.5)
const COLOR_OFF := Color(0.25, 0.28, 0.32)
const COLOR_BROKEN := Color(1.0, 0.25, 0.2)
const DUST_TINT := Color(0.75, 0.6, 0.45)

var _player: Node2D
var _target: Node2D
var _target_site := ""
var _repair_progress := 0.0
var _prompt: Label
var _alert: Label
var _end_panel: PanelContainer
var _end_label: Label
var _blink := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_actions()
	_player = get_parent().get_node("Player")
	_build_ui()
	Base.failure_started.connect(_on_failure_started)
	Base.failure_repaired.connect(_on_failure_repaired)
	Base.game_over.connect(_on_game_over)
	Base.game_won.connect(_on_game_won)


func _process(delta: float) -> void:
	if get_tree().paused:
		if Input.is_action_just_pressed("restart"):
			_restart()
		return
	_blink = fmod(_blink + delta, 1.0)
	_update_visuals()
	_find_target()
	_handle_input(delta)
	_update_alert()


func _find_target() -> void:
	_target = null
	_target_site = ""
	var best := reach_px
	for console: Node2D in get_tree().get_nodes_in_group("system_consoles"):
		var d := absf(console.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = console
			_target_site = console.get_meta("system", "")
	for panel: Node2D in get_tree().get_nodes_in_group("solar_panels"):
		var d := absf(panel.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = panel
			_target_site = "panel"


func _handle_input(delta: float) -> void:
	if not _target:
		_prompt.visible = false
		_repair_progress = 0.0
		return
	var site := "solar" if _target_site == "panel" else _target_site
	var broken := Base.failures_at(site)
	var text := ""

	if broken.size() > 0 and not (_target_site == "solar"):
		var failure: String = broken[0]
		if Input.is_action_pressed("interact"):
			_repair_progress += delta
			if _repair_progress >= repair_seconds:
				Base.repair(failure)
				_repair_progress = 0.0
		else:
			_repair_progress = 0.0
		var pct := int(100.0 * _repair_progress / repair_seconds)
		text = "%s\nHold E to repair" % Base.FAILURE_NAMES[failure]
		if _repair_progress > 0.0:
			text += "  %d%%" % pct
	elif _target_site in Base.SYSTEMS:
		_repair_progress = 0.0
		var on: bool = Base.switches[_target_site]
		if Input.is_action_just_pressed("interact"):
			Base.toggle_system(_target_site)
			on = not on
		text = "%s: %s\nE to switch %s" % [
			SYSTEM_LABELS[_target_site].capitalize(), "ON" if on else "OFF", "off" if on else "on"]
		if _target_site == "solar":
			text += "\nSolar %.1f kW, draw %.1f kW" % [Base.solar_power(), Base.power_draw()]
			if Base.failures.has("dust"):
				text += "\nPanels dusty: clean them on the Solar Array"
	else:
		_prompt.visible = false
		return

	_prompt.text = text
	_prompt.visible = true
	_prompt.global_position = _target.global_position + Vector2(-_prompt.size.x / 2.0, -110.0)


func _update_visuals() -> void:
	var flash := _blink < 0.5
	for console: Node2D in get_tree().get_nodes_in_group("system_consoles"):
		var screen := console.get_node_or_null("Screen") as ColorRect
		if not screen:
			continue
		var site: String = console.get_meta("system", "")
		if Base.failures_at(site).size() > 0:
			screen.color = COLOR_BROKEN if flash else COLOR_OFF
		elif site in Base.SYSTEMS:
			screen.color = COLOR_ON if Base.switches[site] else COLOR_OFF
		else:
			screen.color = COLOR_ON if Base.is_day() else COLOR_OFF
	var dusty := Base.failures.has("dust")
	for panel: Node2D in get_tree().get_nodes_in_group("solar_panels"):
		panel.modulate = DUST_TINT if dusty else Color.WHITE


func _update_alert() -> void:
	var lines: PackedStringArray = []
	for f: String in Base.failures:
		var where := "the Solar Array" if f == "dust" else "the %s console" % SYSTEM_LABELS[Base.FAILURE_SITES[f]]
		lines.append("⚠ %s: repair at %s" % [Base.FAILURE_NAMES[f], where])
	_alert.text = "\n".join(lines)
	_alert.modulate.a = 1.0 if _blink < 0.7 else 0.6


func _on_failure_started(_failure: String) -> void:
	_blink = 0.0


func _on_failure_repaired(_failure: String) -> void:
	_repair_progress = 0.0


func _on_game_over(resource: String, hour: float, too_high: bool) -> void:
	var c := Base.config
	var low := {
		"oxygen": "Oxygen fell below %.1f kg and you passed out" % c.oxygen_min,
		"energy": "The battery went flat",
		"water": "The water ran out",
		"temperature": "The base froze below %d °C" % int(c.temperature_min),
	}
	var high := {
		"oxygen": "Oxygen built up past %.1f kg and the air caught fire" % c.oxygen_max,
		"energy": "The battery overcharged past %d kWh and burned out" % int(c.energy_max),
		"water": "The water tank overflowed",
		"temperature": "The base overheated past %d °C" % int(c.temperature_max),
	}
	var reason: String = high[resource] if too_high else low[resource]
	_show_end("%s at hour %.1f.\nThe rescue ship was %.1f hours away." % [
		reason, hour, Base.hours_until_rescue()])


func _on_game_won() -> void:
	var s := "The rescue ship has landed. You survived 72 hours!\n"
	s += "Left: %.2f kg oxygen, %.1f kWh, %.1f L water, %.1f °C" % [
		Base.oxygen, Base.energy, Base.water, Base.temperature]
	_show_end(s)


func _show_end(text: String) -> void:
	_end_label.text = text + "\n\nPress R to try again"
	_end_panel.visible = true
	_prompt.visible = false
	get_tree().paused = true


func _restart() -> void:
	get_tree().paused = false
	Base.reset()
	get_tree().reload_current_scene()


func _build_ui() -> void:
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.z_index = 20
	_prompt.visible = false
	add_child(_prompt)

	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)

	_alert = Label.new()
	_alert.anchor_left = 0.0
	_alert.anchor_right = 1.0
	_alert.anchor_top = 1.0
	_alert.anchor_bottom = 1.0
	_alert.offset_top = -90.0
	_alert.offset_bottom = -12.0
	_alert.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_alert.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert.add_theme_font_size_override("font_size", 16)
	_alert.add_theme_color_override("font_color", COLOR_BROKEN)
	_alert.add_theme_color_override("font_outline_color", Color.BLACK)
	_alert.add_theme_constant_override("outline_size", 4)
	_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_alert)

	_end_panel = PanelContainer.new()
	_end_panel.anchor_left = 0.5
	_end_panel.anchor_right = 0.5
	_end_panel.anchor_top = 0.5
	_end_panel.anchor_bottom = 0.5
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.08, 0.9)
	style.set_content_margin_all(24)
	style.set_corner_radius_all(6)
	_end_panel.add_theme_stylebox_override("panel", style)
	_end_panel.visible = false
	layer.add_child(_end_panel)
	_end_label = Label.new()
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 20)
	_end_panel.add_child(_end_label)


func _ensure_input_actions() -> void:
	var bindings := {"interact": KEY_E, "restart": KEY_R}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)

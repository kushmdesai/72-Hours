class_name SystemPanel
extends CanvasLayer
## The machine screen: opened with E at a working console. It pauses the game
## and shows the system's part of the model with today's numbers put in, an
## ON/OFF button, and a what-if comparison: the same Euler model run ahead
## twice, once with the system ON and once OFF, so the player can see what the
## switch will do before committing to it.
##
## Space/Enter or the button flips the switch. E or Esc closes.

signal closed

## How far ahead the what-if graph and table look, in in-game hours.
const LOOKAHEAD_HOURS := 24.0
## How far ahead "time to limit" is searched, in in-game hours.
const LIMIT_HORIZON_HOURS := 96.0
const STEP_HOURS := 0.1

const TITLES := {
	"solar": "SOLAR PANELS",
	"oxygen": "OXYGEN GENERATOR",
	"water": "WATER RECYCLER",
	"heater": "HEATER",
}
## The resource each system mainly controls, drawn on the graph.
const PRIMARY := {"solar": "energy", "oxygen": "oxygen", "water": "water", "heater": "temperature"}
const NAMES := {"oxygen": "Oxygen", "energy": "Battery", "water": "Water", "temperature": "Temp"}
const UNITS := {"oxygen": "kg", "energy": "kWh", "water": "L", "temperature": "°C"}

const COLOR_ON := Color(0.35, 0.9, 0.55)
const COLOR_OFF := Color(0.6, 0.64, 0.7)
const COLOR_BROKEN := Color(1.0, 0.35, 0.3)
const COLOR_TEXT := Color(0.88, 0.92, 1.0)
const COLOR_DIM := Color(0.6, 0.66, 0.76)
const COLOR_ACCENT := Color(1.0, 0.78, 0.35)

var site := ""
var _status: Label
var _button: Button
var _equations: RichTextLabel
var _symbols: RichTextLabel
var _table: GridContainer
var _graph: WhatIfGraph
var _graph_title: Label


func _init(system: String) -> void:
	site = system


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_tree().paused = true
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_toggle()


func close() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()


func _toggle() -> void:
	Base.toggle_system(site)
	_refresh()


# --- What-if model ----------------------------------------------------------

## Run the Base model ahead from the current state with this system forced on
## or off (everything else as it is now, no new failures). Returns the primary
## resource's curve over LOOKAHEAD_HOURS, the rates right now, and the hours
## until each resource leaves its safe range (INF if not within the horizon).
func _simulate(on: bool) -> Dictionary:
	var saved: bool = Base.switches[site]
	Base.switches[site] = on
	var state := {"oxygen": Base.oxygen, "energy": Base.energy,
			"water": Base.water, "temperature": Base.temperature}
	var rates_now := Base.rates()
	var limits := {}
	var curve := PackedVector2Array()
	var key: String = PRIMARY[site]
	var t := 0.0
	curve.append(Vector2(0.0, state[key]))
	while t < LIMIT_HORIZON_HOURS and (limits.size() < Base.RESOURCES.size() or t < LOOKAHEAD_HOURS):
		var r := Base.rates_at(Base.hour + t, state.oxygen, state.energy, state.water, state.temperature)
		for k: String in Base.RESOURCES:
			state[k] += r[k] * STEP_HOURS
			if not limits.has(k) and (state[k] <= Base.min_of(k) or state[k] >= Base.max_of(k)):
				limits[k] = t + STEP_HOURS
		t += STEP_HOURS
		# The curve stops where the resource leaves its safe range: game over.
		if t <= LOOKAHEAD_HOURS + 0.001 and (not limits.has(key) or limits[key] >= t):
			curve.append(Vector2(t, state[key]))
	Base.switches[site] = saved
	for k: String in Base.RESOURCES:
		if not limits.has(k):
			limits[k] = INF
	return {"curve": curve, "rates": rates_now, "limits": limits}


# --- Display ----------------------------------------------------------------

func _refresh() -> void:
	var on: bool = Base.switches[site]
	var broken := Base.failures_at(site).size() > 0
	if broken:
		_status.text = "DUSTY" if site == "solar" else "BROKEN"
		_status.add_theme_color_override("font_color", COLOR_BROKEN)
	else:
		_status.text = "ON" if on else "OFF"
		_status.add_theme_color_override("font_color", COLOR_ON if on else COLOR_OFF)
	_button.text = "SWITCH OFF" if on else "SWITCH ON"
	_equations.text = _equation_text()
	_symbols.text = _symbol_text()

	var with_on := _simulate(true)
	var with_off := _simulate(false)
	_fill_table(with_on, with_off, on)

	var key: String = PRIMARY[site]
	_graph_title.text = "%s over the next %d h  (Euler's method, dt = %.1f h)" % [
		NAMES[key], int(LOOKAHEAD_HOURS), STEP_HOURS]
	_graph.set_data(with_on.curve, with_off.curve, Base.min_of(key), Base.max_of(key), on)


func _fill_table(with_on: Dictionary, with_off: Dictionary, on: bool) -> void:
	for child in _table.get_children():
		child.queue_free()
	for h in ["", "Now", "Rate if ON", "Rate if OFF", "Lasts if ON", "Lasts if OFF"]:
		_table.add_child(_cell(h, COLOR_DIM, 13))
	for k: String in Base.RESOURCES:
		var r_on: float = with_on.rates[k]
		var r_off: float = with_off.rates[k]
		var changed := absf(r_on - r_off) > 0.0005
		_table.add_child(_cell(NAMES[k], COLOR_TEXT if changed else COLOR_DIM, 14))
		_table.add_child(_cell("%.1f %s" % [Base.value(k), UNITS[k]], COLOR_DIM, 14))
		var places := 3 if k == "oxygen" else 2
		_table.add_child(_cell(_signed(r_on, places) + "/h", _pick(changed, on, true), 14))
		_table.add_child(_cell(_signed(r_off, places) + "/h", _pick(changed, on, false), 14))
		_table.add_child(_cell(_hours(with_on.limits[k]), _limit_color(with_on.limits[k], changed && on), 14))
		_table.add_child(_cell(_hours(with_off.limits[k]), _limit_color(with_off.limits[k], changed && not on), 14))


func _pick(changed: bool, on: bool, column_on: bool) -> Color:
	if not changed:
		return COLOR_DIM
	return COLOR_ACCENT if on == column_on else COLOR_TEXT


func _limit_color(hours: float, current: bool) -> Color:
	if hours < Base.hours_until_rescue():
		return COLOR_BROKEN
	return COLOR_ACCENT if current else COLOR_TEXT


func _equation_text() -> String:
	var c := Base.config
	var u := "1" if _running() else "0"
	var lines: PackedStringArray = []
	match site:
		"solar":
			var s := Base.sunlight()
			var eta := c.panel_efficiency * (1.0 - c.dust_loss if Base.failures.has("dust") else 1.0)
			lines.append("[b]Solar power[/b]   P = η·A·S(t)·u")
			lines.append("S(t) = S_peak·max(0, sin(2π(t + φ)/%d))" % int(c.day_length))
			lines.append("     = %.2f·max(0, sin(2π(%.1f + %.0f)/%d)) = [color=#ffc759]%.2f kW/m²[/color]" % [
				c.sunlight_peak, Base.hour, c.day_phase, int(c.day_length), s])
			lines.append("P = %.2f · %.0f m² · %.2f · %s = [color=#ffc759]%.2f kW[/color]" % [
				eta, c.panel_area, s, u, Base.solar_power()])
			if Base.failures.has("dust"):
				lines.append("[color=#ff5a4d]Dust cuts η by %d%%: clean the panels on the Solar Array[/color]" % int(c.dust_loss * 100))
			lines.append("")
			lines.append("[b]Battery[/b]   dE/dt = P − Σ uᵢ·Pᵢ")
			lines.append("      = %.2f − %.2f = [color=#ffc759]%s kW[/color]" % [
				Base.solar_power(), Base.power_draw(), _signed(Base.rate("energy"))])
		"oxygen":
			var leak := c.oxygen_leak_rate if Base.failures.has("oxygen_leak") else 0.0
			lines.append("[b]Oxygen[/b]   dO/dt = g·u_gen − c_O − L_O")
			lines.append("      = %.3f·%s − %.3f − %.3f = [color=#ffc759]%s kg/h[/color]" % [
				c.generator_output, u, c.oxygen_use, leak, _signed(Base.rate("oxygen"), 3)])
			lines.append("")
			lines.append("[b]It splits water[/b]   k_e·g·u_gen = %.3f·%.3f·%s = %.3f L/h" % [
				c.water_per_oxygen, c.generator_output, u, c.water_per_oxygen * c.generator_output * float(u)])
			lines.append("[b]It uses power[/b]   u_gen·P_gen = %s·%.1f = %.1f kW" % [
				u, c.power_generator, c.power_generator * float(u)])
		"water":
			var leak := c.water_leak_rate if Base.failures.has("water_leak") else 0.0
			var gen := 1.0 if Base.generator_running() else 0.0
			lines.append("[b]Water[/b]   dW/dt = −(1 − r·u_rec)·c_W − k_e·g·u_gen − L_W")
			lines.append("      = −(1 − %.2f·%s)·%.2f − %.3f·%.3f·%d − %.2f" % [
				c.recycle_efficiency, u, c.water_use, c.water_per_oxygen, c.generator_output, int(gen), leak])
			lines.append("      = [color=#ffc759]%s L/h[/color]" % _signed(Base.rate("water"), 3))
			lines.append("")
			lines.append("The recycler gets back r = %d%% of the water you use." % int(c.recycle_efficiency * 100))
			lines.append("[b]It uses power[/b]   u_rec·P_rec = %s·%.1f = %.1f kW" % [
				u, c.power_recycler, c.power_recycler * float(u)])
		"heater":
			var t_out := Base.outside_temperature()
			lines.append("[b]Temperature[/b]   dT/dt = [H·u_heat − k·(T − T_out)] / C")
			lines.append("      = [%.1f·%s − %.3f·(%.1f − (%.0f))] / %.1f" % [
				c.power_heater, u, c.heat_loss, Base.temperature, t_out, c.heat_capacity])
			lines.append("      = [color=#ffc759]%s °C/h[/color]" % _signed(Base.rate("temperature"), 2))
			lines.append("")
			lines.append("Newton's law of cooling: heat leaks out faster the colder it is outside.")
			lines.append("[b]It uses power[/b]   u_heat·H = %s·%.1f = %.1f kW" % [
				u, c.power_heater, c.power_heater * float(u)])
	lines.append("")
	lines.append("[color=#9aa6bb]u = %s means this machine is %s.[/color]" % [
		u, "running" if u == "1" else "not running"])
	return "\n".join(lines)


func _symbol_text() -> String:
	var rows := {
		"solar": [["P", "power from the panels (kW)"], ["η", "panel efficiency"], ["A", "panel area (m²)"],
			["S(t)", "sunlight, a half sine wave over the %d h day" % int(Base.config.day_length)],
			["φ", "time of day at the start (h)"], ["Σ uᵢ·Pᵢ", "power used by every running machine"]],
		"oxygen": [["O", "oxygen in the air (kg)"], ["g", "generator output (kg/h)"],
			["c_O", "oxygen you breathe (kg/h)"], ["L_O", "leak, only while the leak failure is on"],
			["k_e", "litres of water split per kg of oxygen"], ["P_gen", "generator power (kW)"]],
		"water": [["W", "water in the tank (L)"], ["r", "fraction of used water recycled"],
			["c_W", "water you use (L/h)"], ["k_e·g", "water the oxygen generator splits (L/h)"],
			["L_W", "leak, only while the pipe leak is on"], ["P_rec", "recycler power (kW)"]],
		"heater": [["T", "cabin temperature (°C)"], ["H", "heater power (kW)"],
			["k", "heat lost per °C of difference with outside (kW/°C)"], ["T_out", "outside temperature, colder at night"],
			["C", "heat capacity of the cabin (kWh/°C)"]],
	}
	var lines: PackedStringArray = []
	for row: Array in rows[site]:
		lines.append("[color=#e0eaff]%s[/color]  %s" % [row[0], row[1]])
	lines.append("[color=#e0eaff]u[/color]  1 when the machine is running, 0 when it is off or broken")
	return "\n".join(lines)


func _running() -> bool:
	match site:
		"solar": return Base.switches.solar
		"oxygen": return Base.generator_running()
		"water": return Base.recycler_running()
		"heater": return Base.heater_running()
	return false


func _signed(v: float, decimals: int = 2) -> String:
	var s := ("%." + str(decimals) + "f") % absf(v)
	return ("+" if v >= 0.0 else "−") + s


func _hours(h: float) -> String:
	if h == INF:
		return "> %d h" % int(LIMIT_HORIZON_HOURS)
	return "%.1f h" % h


func _cell(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.13, 0.97)
	style.border_color = Color(0.3, 0.55, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1000, 560)
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var title := _cell(TITLES[site], COLOR_TEXT, 26)
	title.size_flags_horizontal = Control.SIZE_FILL
	header.add_child(title)
	_status = _cell("", COLOR_ON, 26)
	header.add_child(_status)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(170, 40)
	_button.add_theme_font_size_override("font_size", 18)
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_toggle)
	header.add_child(_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(480, 0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	left.add_child(_cell("THE MODEL, WITH TODAY'S NUMBERS", COLOR_DIM, 13))
	_equations = RichTextLabel.new()
	_equations.bbcode_enabled = true
	_equations.fit_content = true
	_equations.scroll_active = false
	_equations.add_theme_font_size_override("normal_font_size", 15)
	_equations.add_theme_font_size_override("bold_font_size", 15)
	_equations.add_theme_color_override("default_color", COLOR_TEXT)
	left.add_child(_equations)
	left.add_child(_cell("WHAT THE LETTERS MEAN", COLOR_DIM, 13))
	_symbols = RichTextLabel.new()
	_symbols.bbcode_enabled = true
	_symbols.fit_content = true
	_symbols.scroll_active = false
	_symbols.add_theme_font_size_override("normal_font_size", 13)
	_symbols.add_theme_color_override("default_color", COLOR_DIM)
	left.add_child(_symbols)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_graph_title = _cell("", COLOR_DIM, 13)
	right.add_child(_graph_title)
	_graph = WhatIfGraph.new()
	_graph.custom_minimum_size = Vector2(440, 200)
	right.add_child(_graph)
	right.add_child(_cell("WHAT IF?  The same model run ahead with this machine ON vs OFF", COLOR_DIM, 13))
	_table = GridContainer.new()
	_table.columns = 6
	_table.add_theme_constant_override("h_separation", 10)
	right.add_child(_table)

	var footer := _cell("Space / click: switch ON or OFF      E / Esc: close      (the clock is paused)", COLOR_DIM, 13)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)


## Line graph of the primary resource with the machine ON (green) and OFF
## (grey), over the safe range band. The line for the current setting is thicker.
class WhatIfGraph:
	extends Control

	var _on := PackedVector2Array()
	var _off := PackedVector2Array()
	var _lo := 0.0
	var _hi := 1.0
	var _is_on := true

	func set_data(on_curve: PackedVector2Array, off_curve: PackedVector2Array,
			lo: float, hi: float, is_on: bool) -> void:
		_on = on_curve
		_off = off_curve
		_lo = lo
		_hi = hi
		_is_on = is_on
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(44, 6), size - Vector2(52, 26))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.07))
		# y range: the safe range plus a margin, widened to fit both curves.
		var y0 := _lo
		var y1 := _hi
		for p in _on + _off:
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
		var pad := (y1 - y0) * 0.08 + 0.001
		y0 -= pad
		y1 += pad
		var x1 := SystemPanel.LOOKAHEAD_HOURS
		var to_px := func(p: Vector2) -> Vector2:
			return Vector2(r.position.x + r.size.x * p.x / x1,
					r.end.y - r.size.y * (p.y - y0) / (y1 - y0))
		# Safe band and limit lines.
		var top: Vector2 = to_px.call(Vector2(0, _hi))
		var bottom: Vector2 = to_px.call(Vector2(0, _lo))
		draw_rect(Rect2(Vector2(r.position.x, top.y), Vector2(r.size.x, bottom.y - top.y)),
				Color(0.2, 0.6, 0.35, 0.12))
		draw_line(Vector2(r.position.x, top.y), Vector2(r.end.x, top.y), Color(1, 0.35, 0.3, 0.7), 1.0)
		draw_line(Vector2(r.position.x, bottom.y), Vector2(r.end.x, bottom.y), Color(1, 0.35, 0.3, 0.7), 1.0)
		var font := get_theme_default_font()
		draw_string(font, Vector2(2, top.y + 4), str(snappedf(_hi, 0.1)), HORIZONTAL_ALIGNMENT_LEFT, 40, 11, Color(1, 0.5, 0.45))
		draw_string(font, Vector2(2, bottom.y + 4), str(snappedf(_lo, 0.1)), HORIZONTAL_ALIGNMENT_LEFT, 40, 11, Color(1, 0.5, 0.45))
		for h in range(0, int(x1) + 1, 6):
			var x: float = to_px.call(Vector2(h, 0)).x
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.06))
			draw_string(font, Vector2(x - 12, size.y - 4), "+%dh" % h, HORIZONTAL_ALIGNMENT_LEFT, 40, 11, Color(0.6, 0.66, 0.76))
		_curve(_off, to_px, Color(0.6, 0.64, 0.7), 3.0 if not _is_on else 1.5)
		_curve(_on, to_px, Color(0.35, 0.9, 0.55), 3.0 if _is_on else 1.5)
		draw_string(font, Vector2(r.end.x - 110, r.position.y + 14), "ON", HORIZONTAL_ALIGNMENT_LEFT, 40, 12, Color(0.35, 0.9, 0.55))
		draw_string(font, Vector2(r.end.x - 70, r.position.y + 14), "OFF", HORIZONTAL_ALIGNMENT_LEFT, 40, 12, Color(0.6, 0.64, 0.7))

	func _curve(points: PackedVector2Array, to_px: Callable, color: Color, width: float) -> void:
		if points.size() < 2:
			return
		var px := PackedVector2Array()
		for p in points:
			px.append(to_px.call(p))
		draw_polyline(px, color, width, true)
		# A curve that ends early hit a limit there.
		if points[-1].x < SystemPanel.LOOKAHEAD_HOURS - 0.01:
			draw_circle(px[-1], 4.0, Color(1, 0.35, 0.3))

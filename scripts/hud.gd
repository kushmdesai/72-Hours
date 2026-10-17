class_name Hud
extends CanvasLayer
## On-screen readout for the base: the four resources against their safe
## ranges, the survival clock against the rescue clock, the systems and their
## power, the day/night cycle and the controls.
##
## The resource model pushes numbers in every frame:
##   hud.set_resource("oxygen", 2.4, -0.035, time_left)  # value, rate per in-game hour
##   hud.set_clock(18.5)                                  # in-game hours since the strike
##
## Safe ranges come from Base.config (oxygen_min, oxygen_max, ...). Going past
## either end of a range ends the game, so every bar shows its min and max and
## the "Limit in" column says which one the resource is heading for and when:
##   t_limit = (R - min) / |dR/dt| when falling, (max - R) / dR/dt when rising
## unless the model passes its own forecast as time_left. The survival clock is
## t_survive = min(t_limit) and turns red when it is shorter than the time
## left until rescue.
##
## Find it from anywhere with get_tree().get_first_node_in_group("hud").
## Without the Base autoload, `demo` drains placeholder values so the HUD can be
## seen working on its own.

const RESOURCES := ["oxygen", "energy", "water", "temperature"]

## Per resource: label, unit, number format, and fallback safe range when the
## Base autoload isn't loaded.
const CONFIG := {
	"oxygen": {"label": "Oxygen", "unit": "kg", "fmt": "%.2f", "min": 0.5, "max": 4.0},
	"energy": {"label": "Energy", "unit": "kWh", "fmt": "%.1f", "min": 0.0, "max": 80.0},
	"water": {"label": "Water", "unit": "L", "fmt": "%.1f", "min": 0.0, "max": 40.0},
	"temperature": {"label": "Temp", "unit": "°C", "fmt": "%.1f", "min": 5.0, "max": 35.0},
}

## Switchable systems as Base names them, with what the panel calls them.
const SYSTEMS := {
	"solar": "Solar panels",
	"oxygen": "O₂ generator",
	"water": "Water recycler",
	"heater": "Heater",
}

const COLOR_OK := Color(0.45, 0.85, 1.0)
const COLOR_GOOD := Color(0.4, 0.9, 0.55)
const COLOR_WARN := Color(1.0, 0.75, 0.3)
const COLOR_DANGER := Color(1.0, 0.3, 0.3)
const COLOR_DIM := Color(0.62, 0.68, 0.75)
const COLOR_OFF := Color(0.45, 0.48, 0.52)

## In-game hours until the rescue ship lands (overridden by Base.config).
@export var rescue_hours: float = 72.0
## Drain placeholder values until the model first calls set_resource.
@export var demo: bool = true

var hours_elapsed: float = 0.0
var _values := {}
var _rates := {}
var _forecasts := {}
var _rows := {}
var _system_rows := {}
var _base: Node
var _blink := 0.0

var _clock_label: Label
var _mission_bar: RangeBar
var _rescue_label: Label
var _survive_label: Label
var _verdict_label: Label
var _limiting_label: Label
var _systems_panel: PanelContainer
var _net_label: Label
var _sun_label: Label
var _risk_label: Label


func _ready() -> void:
	add_to_group("hud")
	_base = get_node_or_null("/root/Base")
	if _base:
		rescue_hours = _base.config.rescue_hours
	_build()
	if demo:
		_values = {"oxygen": 2.0, "energy": 30.0, "water": 30.0, "temperature": 21.0}
		_rates = {"oxygen": 0.055, "energy": -1.2, "water": -0.4, "temperature": -0.25}
	_refresh()


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta, 1.0)
	if demo:
		# Placeholder model: 1 real second = 0.08 in-game hours.
		var dh := delta * 0.08
		hours_elapsed = minf(hours_elapsed + dh, rescue_hours)
		for key in RESOURCES:
			_values[key] = _values[key] + _rates[key] * dh
	_refresh()


## Set one resource's current value and its rate of change per in-game hour.
## Pass time_left (hours until it leaves its safe range) to override the HUD's
## own straight-line estimate, e.g. when the model forecasts changing rates.
func set_resource(key: String, value: float, rate_per_hour: float, time_left: float = -1.0) -> void:
	assert(CONFIG.has(key), "Unknown resource: %s" % key)
	_stop_demo()
	_values[key] = value
	_rates[key] = rate_per_hour
	if time_left >= 0.0:
		_forecasts[key] = time_left
	else:
		_forecasts.erase(key)


## Set the in-game time since the meteor strike, in hours.
func set_clock(hours: float) -> void:
	_stop_demo()
	hours_elapsed = hours


func hours_until_rescue() -> float:
	return maxf(rescue_hours - hours_elapsed, 0.0)


func min_of(key: String) -> float:
	return _base.min_of(key) if _base else CONFIG[key].min


func max_of(key: String) -> float:
	return _base.max_of(key) if _base else CONFIG[key].max


## True if the resource will leave its range through the max rather than the min.
func heading_to_max(key: String) -> bool:
	if _base:
		return _base.heading_to_max(key)
	return _rates.get(key, 0.0) > 0.0


## Hours until this resource leaves its safe range, or INF if it never does.
func time_until_empty(key: String) -> float:
	if _forecasts.has(key):
		return _forecasts[key]
	var rate: float = _rates.get(key, 0.0)
	var v: float = _values.get(key, 0.0)
	if v <= min_of(key) or v >= max_of(key):
		return 0.0
	if rate < 0.0:
		return (v - min_of(key)) / -rate
	if rate > 0.0:
		return (max_of(key) - v) / rate
	return INF


## t_survive = min over all resources of time_until_empty.
func survival_time() -> float:
	var best := INF
	for key in RESOURCES:
		best = minf(best, time_until_empty(key))
	return best


func _stop_demo() -> void:
	if demo:
		demo = false
		_values.clear()
		_rates.clear()


func _refresh() -> void:
	var rescue := hours_until_rescue()
	var survive := survival_time()
	var limiting := ""
	for key in RESOURCES:
		_refresh_row(key, rescue)
		if not is_inf(survive) and limiting == "" and time_until_empty(key) == survive:
			limiting = key

	_clock_label.text = "HOUR %d of %d" % [int(hours_elapsed), int(rescue_hours)]
	_mission_bar.set_range(0.0, rescue_hours)
	_mission_bar.value = hours_elapsed
	_mission_bar.fill_color = COLOR_OK
	_rescue_label.text = "Rescue ship in  %s" % _fmt_hours(rescue)

	var color := _status_color(survive, rescue)
	_survive_label.text = "You last  " + ("∞" if is_inf(survive) else _fmt_hours(survive))
	_survive_label.add_theme_color_override("font_color", color)
	# Flash the survival clock when the end is close.
	_survive_label.modulate.a = 0.45 if survive < 3.0 and _blink > 0.6 else 1.0
	if is_inf(survive) or survive >= rescue:
		_verdict_label.text = "On track to be rescued" if is_inf(survive) \
				else "On track: %s to spare" % _fmt_hours(survive - rescue)
	else:
		_verdict_label.text = "Not enough: %s short" % _fmt_hours(rescue - survive)
	_verdict_label.add_theme_color_override("font_color", color)
	if limiting != "":
		_limiting_label.text = "%s will hit its %s first" % [
			CONFIG[limiting].label, "max" if heading_to_max(limiting) else "min"]
	else:
		_limiting_label.text = ""

	_refresh_systems()


func _refresh_row(key: String, rescue: float) -> void:
	var row: Dictionary = _rows[key]
	var cfg: Dictionary = CONFIG[key]
	var bar: RangeBar = row.bar
	bar.set_range(min_of(key), max_of(key))
	if not _values.has(key):
		row.value.text = "--"
		row.rate.text = ""
		row.limit.text = ""
		return
	var value: float = _values[key]
	var rate: float = _rates.get(key, 0.0)
	var t := time_until_empty(key)
	var color := _status_color(t, rescue)
	bar.value = value
	bar.fill_color = color
	row.value.text = (cfg.fmt + " %s") % [value, cfg.unit]
	var arrow := "↑" if rate > 0.0 else ("↓" if rate < 0.0 else "")
	row.rate.text = "%s %s/h" % [arrow, _fmt_rate(absf(rate))]
	row.rate.add_theme_color_override("font_color", COLOR_DIM if absf(rate) < 1e-6 else Color.WHITE)
	if is_inf(t):
		row.limit.text = "safe"
	else:
		row.limit.text = "%s in %s" % ["max" if heading_to_max(key) else "min", _fmt_hours(t)]
	row.limit.add_theme_color_override("font_color", color)


func _refresh_systems() -> void:
	_systems_panel.visible = _base != null
	if not _base:
		return
	var cfg = _base.config
	var draws := {
		"oxygen": cfg.power_generator,
		"water": cfg.power_recycler,
		"heater": cfg.power_heater,
	}
	for system: String in SYSTEMS:
		var row: Dictionary = _system_rows[system]
		var on: bool = _base.switches[system]
		var broken: bool = _base.failures_at(system).size() > 0
		var state := "BROKEN" if broken else ("ON" if on else "OFF")
		var color := COLOR_DANGER if broken else (COLOR_GOOD if on else COLOR_OFF)
		row.state.text = state
		row.state.add_theme_color_override("font_color", color)
		if broken:
			row.state.modulate.a = 1.0 if _blink < 0.6 else 0.4
		else:
			row.state.modulate.a = 1.0
		var power := ""
		var active := true
		if system == "solar":
			power = "+%.1f kW" % _base.solar_power()
			active = _base.solar_power() > 0.0
		else:
			var running: bool = {
				"oxygen": _base.generator_running(),
				"water": _base.recycler_running(),
				"heater": _base.heater_running(),
			}[system]
			power = ("−%.1f kW" % draws[system]) if running else ("(%.1f kW)" % draws[system])
			active = running
		row.power.text = power
		row.power.add_theme_color_override("font_color", Color.WHITE if active else COLOR_OFF)

	var net: float = _base.solar_power() - _base.power_draw()
	_net_label.text = "Net power  %+.1f kW" % net
	_net_label.add_theme_color_override("font_color", COLOR_GOOD if net >= 0.0 else COLOR_WARN)

	var length: float = cfg.day_length
	var frac := fposmod((hours_elapsed + cfg.day_phase) / length, 1.0)
	var outside: float = _base.outside_temperature()
	if frac < 0.5:
		_sun_label.text = "☀ Day: sunset in %s   Outside %d °C" % [
			_fmt_hours((0.5 - frac) * length), int(round(outside))]
		_sun_label.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_sun_label.text = "☾ Night: sunrise in %s   Outside %d °C" % [
			_fmt_hours((1.0 - frac) * length), int(round(outside))]
		_sun_label.add_theme_color_override("font_color", COLOR_OK)

	var risk: float = _base.failure_chance(1.0)
	if hours_elapsed < cfg.failure_grace_hours:
		_risk_label.text = "No breakdowns for %s" % _fmt_hours(cfg.failure_grace_hours - hours_elapsed)
	else:
		_risk_label.text = "Breakdown risk next hour  %d%%" % int(round(risk * 100.0))


## Red when it hits a limit before rescue, amber when the margin is under 25%.
func _status_color(t: float, rescue: float) -> Color:
	if t < rescue:
		return COLOR_DANGER
	if t < rescue * 1.25:
		return COLOR_WARN
	return COLOR_GOOD


func _fmt_hours(h: float) -> String:
	var total_min := int(round(h * 60.0))
	return "%dh %02dm" % [total_min / 60, total_min % 60]


func _fmt_rate(r: float) -> String:
	if r >= 10.0:
		return "%.0f" % r
	if r >= 0.1:
		return "%.2f" % r
	return "%.3f" % r


func _build() -> void:
	# Resources, top left.
	var panel := _panel()
	panel.position = Vector2(12, 12)
	add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)
	for header in ["", "Safe range  (min to max)", "Now", "Rate", "Limit in"]:
		grid.add_child(_label(header, 11, COLOR_DIM))
	for key in RESOURCES:
		var cfg: Dictionary = CONFIG[key]
		var bar := RangeBar.new()
		bar.custom_minimum_size = Vector2(200, 20)
		bar.show_limits = true
		var row := {
			"bar": bar,
			"value": _label("", 15, Color.WHITE, 78),
			"rate": _label("", 12, Color.WHITE, 72),
			"limit": _label("", 14, COLOR_GOOD, 96),
		}
		grid.add_child(_label(cfg.label, 15, Color.WHITE, 52))
		grid.add_child(bar)
		grid.add_child(row.value)
		grid.add_child(row.rate)
		grid.add_child(row.limit)
		_rows[key] = row

	# Survival vs rescue, top right.
	var clock := _panel()
	clock.anchor_left = 1.0
	clock.anchor_right = 1.0
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	clock.offset_right = -12
	clock.offset_top = 12
	add_child(clock)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	clock.add_child(box)
	_clock_label = _label("", 12, COLOR_DIM)
	_mission_bar = RangeBar.new()
	_mission_bar.custom_minimum_size = Vector2(230, 8)
	_rescue_label = _label("", 15, Color.WHITE)
	_survive_label = _label("", 24, COLOR_GOOD)
	_verdict_label = _label("", 14, COLOR_GOOD)
	_limiting_label = _label("", 12, COLOR_DIM)
	for c in [_clock_label, _mission_bar, _rescue_label, _survive_label, _verdict_label, _limiting_label]:
		if c is Label:
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(c)

	# Systems and power, bottom left.
	_systems_panel = _panel()
	_systems_panel.anchor_top = 1.0
	_systems_panel.anchor_bottom = 1.0
	_systems_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_systems_panel.offset_left = 12
	_systems_panel.offset_bottom = -12
	add_child(_systems_panel)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 2)
	_systems_panel.add_child(sbox)
	sbox.add_child(_label("SYSTEMS  (press E at a console to open it)", 11, COLOR_DIM))
	var sgrid := GridContainer.new()
	sgrid.columns = 3
	sgrid.add_theme_constant_override("h_separation", 12)
	sgrid.add_theme_constant_override("v_separation", 0)
	sbox.add_child(sgrid)
	for system: String in SYSTEMS:
		var row := {
			"state": _label("", 13, COLOR_GOOD, 58),
			"power": _label("", 13, Color.WHITE, 70),
		}
		sgrid.add_child(_label(SYSTEMS[system], 13, Color.WHITE, 104))
		sgrid.add_child(row.state)
		sgrid.add_child(row.power)
		row.power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_system_rows[system] = row
	_net_label = _label("", 13, COLOR_GOOD)
	_sun_label = _label("", 13, COLOR_WARN)
	_risk_label = _label("", 12, COLOR_DIM)
	for l in [_net_label, _sun_label, _risk_label]:
		sbox.add_child(l)

	# Controls, bottom right.
	var keys := _label("A/D move   W/Space jump   E open console / hold to repair", 12, COLOR_DIM)
	keys.anchor_left = 1.0
	keys.anchor_right = 1.0
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.offset_right = -12
	keys.offset_bottom = -12
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.add_theme_color_override("font_outline_color", Color.BLACK)
	keys.add_theme_constant_override("outline_size", 4)
	add_child(keys)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.08, 0.8)
	style.border_color = Color(0.45, 0.85, 1.0, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(text: String, size: int, color: Color, min_width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = min_width
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A bar from min to max with the current value marked. With show_limits, the
## min and max are written at either end and the last 15% of the range at each
## end is tinted red as the danger zone.
class RangeBar extends Control:
	const LIMIT_W := 34.0
	var min_value := 0.0
	var max_value := 1.0
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var fill_color := Color.WHITE
	var show_limits := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_range(lo: float, hi: float) -> void:
		min_value = lo
		max_value = hi

	func _draw() -> void:
		var x0 := LIMIT_W if show_limits else 0.0
		var w := size.x - 2.0 * x0
		var bar_h := minf(size.y, 10.0) if show_limits else size.y
		var y0 := (size.y - bar_h) / 2.0
		draw_rect(Rect2(x0, y0, w, bar_h), Color(1, 1, 1, 0.08))
		if show_limits:
			var zone := w * 0.15
			var danger := Color(1, 0.3, 0.3, 0.25)
			draw_rect(Rect2(x0, y0, zone, bar_h), danger)
			draw_rect(Rect2(x0 + w - zone, y0, zone, bar_h), danger)
		var span := maxf(max_value - min_value, 1e-6)
		var f := clampf((value - min_value) / span, 0.0, 1.0)
		draw_rect(Rect2(x0, y0, w * f, bar_h), Color(fill_color, 0.85))
		if not show_limits:
			return
		draw_rect(Rect2(x0 + w * f - 1.5, y0 - 3, 3, bar_h + 6), Color.WHITE)
		var font := get_theme_default_font()
		var base_y := size.y / 2.0 + 4.0
		var limit_color := Color(1, 0.6, 0.6)
		draw_string(font, Vector2(0, base_y), _short(min_value), HORIZONTAL_ALIGNMENT_RIGHT,
				LIMIT_W - 5.0, 11, limit_color)
		draw_string(font, Vector2(size.x - LIMIT_W + 5.0, base_y), _short(max_value),
				HORIZONTAL_ALIGNMENT_LEFT, LIMIT_W - 5.0, 11, limit_color)

	func _short(v: float) -> String:
		return ("%d" % int(v)) if is_equal_approx(v, round(v)) else ("%.1f" % v)

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

const RESOURCES := ["oxygen", "energy", "water", "temperature", "food"]

## Per resource: label, unit, number format, and fallback safe range when the
## Base autoload isn't loaded. A "capped" max is a storage limit (extra is
## lost), not a danger, so its bar has no red zone at that end.
const CONFIG := {
	"oxygen": {"label": "Oxygen", "unit": "kg", "fmt": "%.2f", "min": 0.5, "max": 4.0},
	"energy": {"label": "Energy", "unit": "kWh", "fmt": "%.1f", "min": 0.0, "max": 80.0},
	"water": {"label": "Water", "unit": "L", "fmt": "%.1f", "min": 0.0, "max": 40.0},
	"temperature": {"label": "Temp", "unit": "°C", "fmt": "%.1f", "min": 5.0, "max": 35.0},
	"food": {"label": "Food", "unit": "kg", "fmt": "%.1f", "min": 0.0, "max": 6.0, "capped": true},
}

## Switchable systems as Base names them, with what the panel calls them.
const SYSTEMS := {
	"solar": "Solar panels",
	"oxygen": "O₂ generator",
	"water": "Water recycler",
	"heater": "Heater",
	"greenhouse": "Greenhouse",
}

## Multiplies every font size and fixed width in the HUD, for readability.
const UI_SCALE := 1.2

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
var _clock_panel: PanelContainer
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
		_values = {"oxygen": 2.0, "energy": 30.0, "water": 30.0, "temperature": 21.0,
				"food": 3.0}
		_rates = {"oxygen": 0.055, "energy": -1.2, "water": -0.4, "temperature": -0.25,
				"food": -0.02}
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
	var capped: bool = CONFIG[key].get("capped", false)
	if v <= min_of(key) or (v >= max_of(key) and not capped):
		return 0.0
	if rate < 0.0:
		return (v - min_of(key)) / -rate
	if rate > 0.0 and not capped:
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

	_clock_label.text = "HOUR %d/%d" % [int(hours_elapsed), int(rescue_hours)]
	_mission_bar.set_range(0.0, rescue_hours)
	_mission_bar.value = hours_elapsed
	_mission_bar.fill_color = COLOR_OK
	_rescue_label.text = "rescue %s" % _fmt_hours(rescue)

	var color := _status_color(survive, rescue)
	_survive_label.text = "∞" if is_inf(survive) else _fmt_hours(survive)
	_survive_label.add_theme_color_override("font_color", color)
	# Flash the survival clock when the end is close.
	_survive_label.modulate.a = 0.45 if survive < 3.0 and _blink > 0.6 else 1.0
	_set_border(_clock_panel, color)
	var verdict := ""
	if is_inf(survive) or survive >= rescue:
		verdict = "on track" if is_inf(survive) else "%s to spare" % _fmt_hours(survive - rescue)
	else:
		verdict = "%s short" % _fmt_hours(rescue - survive)
	if limiting != "":
		verdict += " · %s %s first" % [CONFIG[limiting].label.to_lower(),
				"max" if heading_to_max(limiting) else "min"]
	_verdict_label.text = verdict
	_verdict_label.add_theme_color_override("font_color", color)

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
	_set_border(row.panel, color)
	row.value.text = (cfg.fmt + " %s") % [value, cfg.unit]
	var arrow := "↑" if rate > 0.0 else ("↓" if rate < 0.0 else "→")
	row.rate.text = "%s %s/h" % [arrow, _fmt_rate(absf(rate))]
	if is_inf(t):
		row.limit.text = "safe"
	else:
		row.limit.text = "%s %s" % ["max" if heading_to_max(key) else "min", _fmt_hours(t)]
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
		"greenhouse": cfg.power_greenhouse,
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
				"greenhouse": _base.greenhouse_running(),
			}[system]
			power = ("−%.1f kW" % draws[system]) if running else ("(%.1f kW)" % draws[system])
			active = running
		row.power.text = power
		row.power.add_theme_color_override("font_color", Color.WHITE if active else COLOR_OFF)
		row.name.add_theme_color_override("font_color", Color.WHITE if on else COLOR_OFF)

	var net: float = _base.solar_power() - _base.power_draw()
	_net_label.text = "net %+.1f kW" % net
	_net_label.add_theme_color_override("font_color", COLOR_GOOD if net >= 0.0 else COLOR_WARN)

	var length: float = cfg.day_length
	var frac := fposmod((hours_elapsed + cfg.day_phase) / length, 1.0)
	var outside: float = _base.outside_temperature()
	if frac < 0.5:
		_sun_label.text = "☀ Day · sunset in %s · outside %d °C" % [
			_fmt_hours((0.5 - frac) * length), int(round(outside))]
		_sun_label.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_sun_label.text = "☾ Night · sunrise in %s · outside %d °C" % [
			_fmt_hours((1.0 - frac) * length), int(round(outside))]
		_sun_label.add_theme_color_override("font_color", COLOR_OK)

	var risk: float = _base.failure_chance(1.0)
	if hours_elapsed < cfg.failure_grace_hours:
		_risk_label.text = "No breakdowns for %s" % _fmt_hours(cfg.failure_grace_hours - hours_elapsed)
	else:
		_risk_label.text = "Breakdown risk %d%% per hour" % int(round(risk * 100.0))


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
	# Bottom strip: one card per resource, then the survival card. It sits on
	# the ground below the base so the sky stays clear for the calamities.
	var strip := HBoxContainer.new()
	strip.anchor_top = 1.0
	strip.anchor_right = 1.0
	strip.anchor_bottom = 1.0
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = 10
	strip.offset_right = -10
	strip.offset_bottom = -10
	strip.add_theme_constant_override("separation", 6)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	for key in RESOURCES:
		var cfg: Dictionary = CONFIG[key]
		var card := _panel()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		card.add_child(v)
		var bar := RangeBar.new()
		bar.custom_minimum_size = Vector2(0, 16 * UI_SCALE)
		bar.show_limits = true
		bar.capped = cfg.get("capped", false)
		var row := {
			"panel": card,
			"bar": bar,
			"value": _label("", 15, Color.WHITE),
			"rate": _label("", 11, COLOR_DIM),
			"limit": _label("", 12, COLOR_GOOD),
		}
		v.add_child(_pair(_label(cfg.label.to_upper(), 11, COLOR_DIM), row.value))
		v.add_child(bar)
		v.add_child(_pair(row.rate, row.limit))
		_rows[key] = row

	_clock_panel = _panel()
	_clock_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_panel.size_flags_stretch_ratio = 1.5
	strip.add_child(_clock_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_clock_panel.add_child(box)
	_clock_label = _label("", 11, COLOR_DIM)
	_rescue_label = _label("", 12, Color.WHITE)
	box.add_child(_pair(_clock_label, _rescue_label))
	_mission_bar = RangeBar.new()
	_mission_bar.custom_minimum_size = Vector2(0, 5)
	box.add_child(_mission_bar)
	_survive_label = _label("", 20, COLOR_GOOD)
	box.add_child(_pair(_label("YOU LAST", 11, COLOR_DIM), _survive_label))
	_verdict_label = _label("", 11, COLOR_GOOD)
	_verdict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_verdict_label)

	# Controls: one quiet line above the strip, right side.
	var keys := _label("A/D move  ·  W jump  ·  E console (hold: repair)  ·  F fast-forward", 11, COLOR_DIM)
	keys.anchor_left = 1.0
	keys.anchor_right = 1.0
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.offset_right = -14
	keys.offset_bottom = -106
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys.add_theme_color_override("font_outline_color", Color.BLACK)
	keys.add_theme_constant_override("outline_size", 3)
	add_child(keys)

	# Systems and power, top left in the sky (the calamities appear further
	# right, and this keeps the tunnels' floor clear).
	_systems_panel = _panel()
	_systems_panel.offset_left = 10
	_systems_panel.offset_top = 10
	add_child(_systems_panel)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 1)
	_systems_panel.add_child(sbox)
	_net_label = _label("", 11, COLOR_GOOD)
	sbox.add_child(_pair(_label("SYSTEMS", 11, COLOR_DIM), _net_label))
	var sgrid := GridContainer.new()
	sgrid.columns = 3
	sgrid.add_theme_constant_override("h_separation", 10)
	sgrid.add_theme_constant_override("v_separation", -2)
	sbox.add_child(sgrid)
	for system: String in SYSTEMS:
		var row := {
			"name": _label(SYSTEMS[system], 12, Color.WHITE, 100),
			"state": _label("", 11, COLOR_GOOD, 48),
			"power": _label("", 12, Color.WHITE, 58),
		}
		row.power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sgrid.add_child(row.name)
		sgrid.add_child(row.state)
		sgrid.add_child(row.power)
		_system_rows[system] = row
	sbox.add_child(HSeparator.new())
	_sun_label = _label("", 11, COLOR_WARN)
	_risk_label = _label("", 11, COLOR_DIM)
	sbox.add_child(_sun_label)
	sbox.add_child(_risk_label)


## Two labels on one line: the first on the left, the second pushed right.
func _pair(left: Label, right: Label) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(left)
	h.add_child(right)
	return h


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.08, 0.82)
	style.border_color = Color(0.45, 0.85, 1.0, 0.3)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 7
	style.content_margin_top = 4
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	return panel


## Colour a card's left edge (and faintly its outline) by status.
func _set_border(panel: PanelContainer, color: Color) -> void:
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = Color(color, 0.75)


func _label(text: String, size: int, color: Color, min_width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(round(size * UI_SCALE)))
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = min_width * UI_SCALE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A bar from min to max with the current value marked. With show_limits, the
## min and max are written at either end and the last 15% of the range at each
## end is tinted red as the danger zone.
class RangeBar extends Control:
	const LIMIT_W := 24.0 * Hud.UI_SCALE
	var min_value := 0.0
	var max_value := 1.0
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var fill_color := Color.WHITE
	var show_limits := false
	## The max is a storage cap, not a danger: no red zone at that end.
	var capped := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_range(lo: float, hi: float) -> void:
		min_value = lo
		max_value = hi

	func _draw() -> void:
		var x0 := LIMIT_W if show_limits else 0.0
		var w := size.x - 2.0 * x0
		var bar_h := minf(size.y, 12.0) if show_limits else size.y
		var y0 := (size.y - bar_h) / 2.0
		draw_rect(Rect2(x0, y0, w, bar_h), Color(1, 1, 1, 0.08))
		if show_limits:
			var zone := w * 0.15
			var danger := Color(1, 0.3, 0.3, 0.25)
			draw_rect(Rect2(x0, y0, zone, bar_h), danger)
			if not capped:
				draw_rect(Rect2(x0 + w - zone, y0, zone, bar_h), danger)
		var span := maxf(max_value - min_value, 1e-6)
		var f := clampf((value - min_value) / span, 0.0, 1.0)
		draw_rect(Rect2(x0, y0, w * f, bar_h), Color(fill_color, 0.85))
		if not show_limits:
			return
		draw_rect(Rect2(x0 + w * f - 1.5, y0 - 3, 3, bar_h + 6), Color.WHITE)
		var font := get_theme_default_font()
		var base_y := size.y / 2.0 + 5.0
		var limit_color := Color(1, 0.6, 0.6)
		draw_string(font, Vector2(0, base_y), _short(min_value), HORIZONTAL_ALIGNMENT_RIGHT,
				LIMIT_W - 5.0, int(11 * Hud.UI_SCALE), limit_color)
		draw_string(font, Vector2(size.x - LIMIT_W + 5.0, base_y), _short(max_value),
				HORIZONTAL_ALIGNMENT_LEFT, LIMIT_W - 5.0, int(11 * Hud.UI_SCALE),
				Color(0.62, 0.68, 0.75) if capped else limit_color)

	func _short(v: float) -> String:
		return ("%d" % int(v)) if is_equal_approx(v, round(v)) else ("%.1f" % v)

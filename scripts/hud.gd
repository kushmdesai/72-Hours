class_name Hud
extends CanvasLayer
## On-screen readout for the base's four resources and the 72 hour rescue clock.
##
## The HUD only displays numbers; the resource model pushes them in:
##   hud.set_resource("oxygen", 12.4, -0.035)   # value, rate per in-game hour
##   hud.set_clock(18.5)                        # in-game hours since the strike
##
## From those it works out, for each resource with a falling rate,
##   t_empty = (R - floor) / |dR/dt|
## and the survival clock t_survive = min(t_empty). A row turns red when its
## t_empty is shorter than the hours left until rescue.
##
## Find it from anywhere with get_tree().get_first_node_in_group("hud").
## Until the model calls set_resource, `demo` drains placeholder values so the
## HUD can be seen working on its own.

const RESOURCES := ["oxygen", "energy", "water", "temperature"]

## Per resource: label, unit, bar range, and the floor that counts as "empty".
## Temperature is "empty" when it falls to the lowest safe limit, not zero.
const CONFIG := {
	"oxygen": {"label": "Oxygen", "unit": "kg", "min": 0.0, "max": 20.0, "floor": 0.0},
	"energy": {"label": "Energy", "unit": "kWh", "min": 0.0, "max": 100.0, "floor": 0.0},
	"water": {"label": "Water", "unit": "L", "min": 0.0, "max": 200.0, "floor": 0.0},
	"temperature": {"label": "Temp", "unit": "°C", "min": -20.0, "max": 40.0, "floor": 5.0},
}

const COLOR_OK := Color(0.45, 0.85, 1.0)
const COLOR_WARN := Color(1.0, 0.75, 0.3)
const COLOR_DANGER := Color(1.0, 0.3, 0.3)
const COLOR_DIM := Color(0.7, 0.75, 0.8)

## In-game hours until the rescue ship lands.
@export var rescue_hours: float = 72.0
## Drain placeholder values until the model first calls set_resource.
@export var demo: bool = true

var hours_elapsed: float = 0.0
var _values := {}
var _rates := {}
var _rows := {}
var _clock_label: Label
var _rescue_label: Label
var _survive_label: Label
var _limiting_label: Label


func _ready() -> void:
	add_to_group("hud")
	_build()
	if demo:
		_values = {"oxygen": 14.0, "energy": 60.0, "water": 150.0, "temperature": 21.0}
		_rates = {"oxygen": -0.035, "energy": -1.2, "water": -0.4, "temperature": -0.25}
	_refresh()


func _process(delta: float) -> void:
	if not demo:
		return
	# Placeholder model: 1 real second = 0.08 in-game hours (the plan's 15 min game).
	var dh := delta * 0.08
	hours_elapsed = minf(hours_elapsed + dh, rescue_hours)
	for key in RESOURCES:
		_values[key] = _values[key] + _rates[key] * dh
	_refresh()


## Set one resource's current value and its rate of change per in-game hour.
## Pass time_left (hours) to override the HUD's own R / |dR/dt| estimate, e.g.
## when the model knows the rate isn't constant.
func set_resource(key: String, value: float, rate_per_hour: float, time_left: float = -1.0) -> void:
	assert(CONFIG.has(key), "Unknown resource: %s" % key)
	_stop_demo()
	_values[key] = value
	_rates[key] = rate_per_hour
	if time_left >= 0.0:
		_rates[key + "_override"] = time_left
	else:
		_rates.erase(key + "_override")
	_refresh()


## Set the in-game time since the meteor strike, in hours.
func set_clock(hours: float) -> void:
	_stop_demo()
	hours_elapsed = hours
	_refresh()


func hours_until_rescue() -> float:
	return maxf(rescue_hours - hours_elapsed, 0.0)


## Hours until this resource reaches its floor, or INF if it isn't falling.
func time_until_empty(key: String) -> float:
	if _rates.has(key + "_override"):
		return _rates[key + "_override"]
	var rate: float = _rates.get(key, 0.0)
	var left: float = _values.get(key, 0.0) - CONFIG[key].floor
	if left <= 0.0:
		return 0.0
	if rate >= 0.0:
		return INF
	return left / -rate


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
	for key in RESOURCES:
		var row: Dictionary = _rows[key]
		var cfg: Dictionary = CONFIG[key]
		if not _values.has(key):
			row.value.text = "--"
			row.rate.text = ""
			row.empty.text = ""
			continue
		var value: float = _values[key]
		var rate: float = _rates.get(key, 0.0)
		var t := time_until_empty(key)
		var bar: ProgressBar = row.bar
		bar.value = value
		row.value.text = "%.1f %s" % [value, cfg.unit]
		row.rate.text = ("%+.3f/h" if absf(rate) < 0.1 else "%+.2f/h") % rate
		row.empty.text = "never" if is_inf(t) else _fmt_hours(t)
		var color := _status_color(t, rescue)
		(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color
		row.empty.add_theme_color_override("font_color", color)

	_clock_label.text = "Hour %.1f of %d" % [hours_elapsed, int(rescue_hours)]
	_rescue_label.text = "Rescue in %s" % _fmt_hours(rescue)
	var survive := survival_time()
	_survive_label.text = "SURVIVAL  " + ("∞" if is_inf(survive) else _fmt_hours(survive))
	_survive_label.add_theme_color_override("font_color", _status_color(survive, rescue))
	var limiting := ""
	if not is_inf(survive):
		for key in RESOURCES:
			if time_until_empty(key) == survive:
				limiting = "Limited by " + CONFIG[key].label.to_lower()
				break
	_limiting_label.text = limiting


## Red when it runs out before rescue, amber when the margin is under 25%.
func _status_color(t: float, rescue: float) -> Color:
	if t < rescue:
		return COLOR_DANGER
	if t < rescue * 1.25:
		return COLOR_WARN
	return COLOR_OK


func _fmt_hours(h: float) -> String:
	var total_min := int(round(h * 60.0))
	return "%dh %02dm" % [total_min / 60, total_min % 60]


func _build() -> void:
	# Resource panel, top left.
	var panel := _panel()
	panel.position = Vector2(12, 12)
	add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)
	for header in ["", "", "Now", "Rate", "Empty in"]:
		grid.add_child(_label(header, 11, COLOR_DIM))
	for key in RESOURCES:
		var cfg: Dictionary = CONFIG[key]
		var bar := ProgressBar.new()
		bar.min_value = cfg.min
		bar.max_value = cfg.max
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.set_corner_radius_all(3)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.08)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		var row := {
			"bar": bar,
			"value": _label("", 14, Color.WHITE, 80),
			"rate": _label("", 12, COLOR_DIM, 70),
			"empty": _label("", 14, COLOR_OK, 75),
		}
		grid.add_child(_label(cfg.label, 14, Color.WHITE, 52))
		grid.add_child(bar)
		grid.add_child(row.value)
		grid.add_child(row.rate)
		grid.add_child(row.empty)
		_rows[key] = row

	# Mission clock, top right.
	var clock := _panel()
	clock.anchor_left = 1.0
	clock.anchor_right = 1.0
	clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	clock.offset_right = -12
	clock.offset_top = 12
	add_child(clock)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	clock.add_child(box)
	_clock_label = _label("", 14, COLOR_DIM)
	_rescue_label = _label("", 16, Color.WHITE)
	_survive_label = _label("", 24, COLOR_OK)
	_limiting_label = _label("", 12, COLOR_DIM)
	for l in [_clock_label, _rescue_label, _survive_label, _limiting_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(l)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.08, 0.75)
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

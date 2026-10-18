class_name MathDebrief
extends CanvasLayer
## End-of-game math debrief: a graph of every resource across the run (from
## Base.history, one sample per in-game hour) with its safe range shaded, the
## rate equation that drove it, and a few numbers worked out from the curve.
## Opened with M from the WASTED / SURVIVED screen; M closes it again.

const COLORS := {
	"oxygen": Color(0.45, 0.8, 1.0),
	"energy": Color(1.0, 0.82, 0.3),
	"water": Color(0.35, 0.55, 1.0),
	"temperature": Color(1.0, 0.45, 0.35),
	"food": Color(0.5, 0.95, 0.45),
}
const TITLES := {
	"oxygen": "Oxygen O (kg)",
	"energy": "Battery E (kWh)",
	"water": "Water W (L)",
	"temperature": "Temperature T (°C)",
	"food": "Food F (kg)",
}
const EQUATIONS := {
	"oxygen": "dO/dt = g·u_gen + crops − c_O − L_O",
	"energy": "dE/dt = η·A·S(t) − Σ u_i·P_i",
	"water": "dW/dt = −(1 − r·u_rec)·c_W − k_e·g·u_gen − L_W",
	"temperature": "dT/dt = [H·u_heat − k·(T − T_out)] / C",
	"food": "dF/dt = y·u_gh·f(T) − c_F",
}
const TEXT := Color(0.85, 0.9, 0.95)
const DIM := Color(0.55, 0.62, 0.72)

var _grid: GridContainer


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


## Rebuild the cards from the run that just ended and show them.
## `repairs` and `pods` come from the SystemsController's tally.
func open(repairs: int, pods: int) -> void:
	for c in _grid.get_children():
		c.queue_free()
	var samples := _samples()
	for key: String in Base.RESOURCES:
		_grid.add_child(_resource_card(key, samples))
	_grid.add_child(_summary_card(samples, repairs, pods))
	visible = true


func close() -> void:
	visible = false


## The hourly history plus the moment the run ended.
func _samples() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(Base.history)
	if out.is_empty() or Base.hour - float(out[-1].hour) > 0.01:
		out.append({"hour": Base.hour, "oxygen": Base.oxygen, "energy": Base.energy,
			"water": Base.water, "temperature": Base.temperature, "food": Base.food})
	return out


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.05, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(_label("MATH DEBRIEF", 28, Color(1.0, 0.75, 0.3)))
	box.add_child(_label(
		"Every frame the game stepped each resource with Euler's method:  R(t + Δt) = R(t) + (dR/dt)·Δt."
		+ "  Shaded band = safe range.", 14, DIM))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(_grid)
	box.add_child(_label("M  back      R  play again", 16, TEXT))


func _resource_card(key: String, samples: Array[Dictionary]) -> Control:
	var card := _card()
	var v := card.get_child(0)
	var col: Color = COLORS[key]
	v.add_child(_label(TITLES[key], 16, col, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(_label(EQUATIONS[key], 13, TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	var graph := Graph.new()
	graph.key = key
	graph.samples = samples
	graph.color = col
	graph.lo = Base.min_of(key)
	graph.hi = Base.max_of(key)
	graph.hours = maxf(Base.config.rescue_hours, Base.hour)
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(0, 110)
	v.add_child(graph)

	var start: float = samples[0][key]
	var end: float = samples[-1][key]
	var lo := start
	var hi := start
	for s in samples:
		lo = minf(lo, s[key])
		hi = maxf(hi, s[key])
	var span := float(samples[-1].hour) - float(samples[0].hour)
	var avg := (end - start) / span if span > 0.0 else 0.0
	v.add_child(_label("%s → %s   (low %s, high %s)" % [_n(start), _n(end), _n(lo), _n(hi)],
		13, TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(_label("Average rate ΔR/Δt = %s per hour" % _n(avg, true), 13, DIM,
		HORIZONTAL_ALIGNMENT_LEFT))
	return card


func _summary_card(samples: Array[Dictionary], repairs: int, pods: int) -> Control:
	var card := _card()
	var v := card.get_child(0)
	v.add_child(_label("The run in numbers", 16, Color(1.0, 0.75, 0.3), HORIZONTAL_ALIGNMENT_LEFT))
	var c := Base.config
	var lam := 0.0
	for f: String in c.failure_rates:
		lam += c.failure_rates[f]
	var lines := PackedStringArray([
		"Hours survived: %.1f of %d" % [Base.hour, int(c.rescue_hours)],
		"Hourly samples graphed: %d" % samples.size(),
		"Repairs made: %d     Supply pods: %d" % [repairs, pods],
		"",
		"Breakdowns are a Poisson process, rate λ = %.3f/h." % lam,
		"Expected over 72 h: λ·t = %.1f" % (lam * c.rescue_hours),
		"P(≥1 in 24 h) = 1 − e^(−λ·24) = %d%%" % roundi(100.0 * (1.0 - exp(-lam * 24.0))),
		"",
		"Coupling: the generator spends water and power,",
		"the heater spends power, and crops need warmth.",
	])
	for line in lines:
		v.add_child(_label(line, 13, TEXT if line != "" else DIM, HORIZONTAL_ALIGNMENT_LEFT))
	return card


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11)
	style.border_color = Color(0.22, 0.27, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	return card


func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A number with sensible precision for the debrief.
static func _n(x: float, signed := false) -> String:
	var s := "%.2f" % x if absf(x) < 10.0 else "%.1f" % x
	return ("+" + s) if signed and x >= 0.0 else s


## Line graph of one resource against in-game hours, with the safe range shaded.
class Graph extends Control:
	var key := ""
	var samples: Array[Dictionary] = []
	var color := Color.WHITE
	var lo := 0.0
	var hi := 1.0
	var hours := 72.0

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var left := 34.0
		var plot := Rect2(left, 4.0, size.x - left - 6.0, size.y - 20.0)
		# The y axis covers the safe range and anything the curve did outside it.
		var y_lo := lo
		var y_hi := hi
		for s in samples:
			y_lo = minf(y_lo, s[key])
			y_hi = maxf(y_hi, s[key])
		var pad := (y_hi - y_lo) * 0.08 + 0.001
		y_lo -= pad
		y_hi += pad
		var to_px := func(h: float, v: float) -> Vector2:
			return Vector2(plot.position.x + plot.size.x * h / hours,
				plot.end.y - plot.size.y * (v - y_lo) / (y_hi - y_lo))

		draw_rect(plot, Color(0.02, 0.03, 0.05))
		var band_top: Vector2 = to_px.call(0.0, hi)
		var band_bottom: Vector2 = to_px.call(0.0, lo)
		draw_rect(Rect2(plot.position.x, band_top.y, plot.size.x, band_bottom.y - band_top.y),
			Color(0.3, 0.9, 0.5, 0.1))
		for v in [lo, hi]:
			var y: float = to_px.call(0.0, v).y
			draw_dashed_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
				Color(0.4, 0.9, 0.55, 0.6), 1.0, 4.0)
			draw_string(font, Vector2(0, y + 4), MathDebrief._n(v), HORIZONTAL_ALIGNMENT_LEFT,
				left - 4, 11, Color(0.55, 0.62, 0.72))
		for h in range(0, int(hours) + 1, 24):
			var x: float = to_px.call(float(h), y_lo).x
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1, 1, 1, 0.06))
			draw_string(font, Vector2(x - 10, size.y - 3), "%dh" % h, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 11, Color(0.55, 0.62, 0.72))
		draw_rect(plot, Color(1, 1, 1, 0.15), false)

		var points := PackedVector2Array()
		for s in samples:
			points.append(to_px.call(float(s.hour), float(s[key])))
		if points.size() >= 2:
			draw_polyline(points, color, 2.0, true)
		if not points.is_empty():
			draw_circle(points[-1], 3.5, color)

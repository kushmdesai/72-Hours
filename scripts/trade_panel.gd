class_name TradePanel
extends CanvasLayer
## The trade screen, opened at the TradeTerminal on the Landing Pad. It pauses
## the game. Sell greenhouse food for coins, then spend coins to order a supply
## pod, which parachutes onto the pad straight away.
##
## The market pays p(s) = P0 * q^s coins per kg after s kg have been sold, so
## each kilogram is worth less than the last. A sale of Δ kg is paid the area
## under that curve, P0 * (q^s - q^(s+Δ)) / -ln(q), drawn shaded on the graph.
##
## E or Esc closes.

signal closed

## Lot sizes offered on the sell buttons, in kg.
const LOTS := [0.5, 1.0, 2.0]
const POD_NAMES := {
	"oxygen": "Oxygen pod  (O₂ +1 kg)",
	"water": "Water pod  (H₂O +6 L)",
	"food": "Food pod  (+1.5 kg)",
	"toolkit": "Toolkit pod  (fixes everything)",
}

const COLOR_TEXT := Color(0.88, 0.92, 1.0)
const COLOR_DIM := Color(0.6, 0.66, 0.76)
const COLOR_GOLD := Color(1.0, 0.8, 0.3)
const COLOR_GOOD := Color(0.4, 0.9, 0.55)
const COLOR_BAD := Color(1.0, 0.35, 0.3)

var _coins: Label
var _food: Label
var _model: RichTextLabel
var _graph: PriceGraph
var _sell_buttons := {}
var _buy_buttons := {}
var _message: Label


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


func close() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()


func _sell(kg: float) -> void:
	var sold := minf(kg, Base.food)
	var paid := Base.sell_food(kg)
	if paid > 0.0:
		_say("Sold %.1f kg of food for %d coins." % [sold, int(paid)], COLOR_GOOD)
	_refresh()


func _buy(kind: String) -> void:
	var drops := _drops()
	if not drops:
		return
	if not Base.buy_pod(kind):
		_say("Not enough coins.", COLOR_BAD)
		return
	drops.order(kind)
	_say("Ordered: %s. It is coming down on the Landing Pad." % POD_NAMES[kind], COLOR_GOOD)
	_refresh()


func _drops() -> SupplyDrops:
	for child in get_tree().current_scene.get_children():
		if child is SystemsController:
			return child._drops
	return null


func _say(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)


func _refresh() -> void:
	var c := Base.config
	_coins.text = "%d coins" % int(Base.coins)
	_food.text = "Food in the pantry: %.2f kg   (you eat %.3f kg/h)" % [Base.food, c.food_use]

	var s := Base.food_sold
	var lines: PackedStringArray = []
	lines.append("[b]Market price[/b]   p(s) = P0·q^s")
	lines.append("      = %.0f·%.2f^%.1f = [color=#ffcc4d]%.2f coins/kg[/color]" % [
		c.food_price_start, c.food_price_ratio, s, Base.food_price()])
	lines.append("[color=#9aa6bb]s = %.1f kg sold so far. Each kg sold cuts the price by %d%%.[/color]" % [
		s, int(round((1.0 - c.food_price_ratio) * 100.0))])
	lines.append("")
	lines.append("[b]A sale of Δ kg pays the area under p(s)[/b]")
	lines.append("      ∫ P0·q^s ds from s to s+Δ = P0·(q^s − q^(s+Δ)) / −ln q")
	var one := Base.food_sale_value(1.0)
	lines.append("      Δ = 1:  %.0f·(%.3f − %.3f) / %.3f = [color=#ffcc4d]%.1f coins[/color]" % [
		c.food_price_start, pow(c.food_price_ratio, s), pow(c.food_price_ratio, s + 1.0),
		-log(c.food_price_ratio), one])
	lines.append("")
	var hours := Base.food / c.food_use
	lines.append("[color=#9aa6bb]Every kg you sell is %.1f h of eating gone. Keep enough to last.[/color]" % (1.0 / c.food_use))
	lines.append("[color=#9aa6bb]Right now your food lasts %.1f h with the greenhouse off.[/color]" % hours)
	_model.text = "\n".join(lines)
	_graph.set_data(s, Base.food)

	for kg: float in _sell_buttons:
		var b: Button = _sell_buttons[kg]
		var lot := minf(kg, Base.food)
		b.text = "Sell %.1f kg   +%d" % [kg, int(Base.food_sale_value(lot))]
		b.disabled = Base.food < kg
	for kind: String in _buy_buttons:
		var b: Button = _buy_buttons[kind]
		var price := Base.pod_price(kind)
		b.text = "%s   %d coins" % [POD_NAMES[kind], int(price)]
		b.disabled = Base.coins + 0.0001 < price


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.13, 0.97)
	style.border_color = Color(0.75, 0.6, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1000, 520)
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var title := _cell("TRADE TERMINAL", COLOR_TEXT, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coins = _cell("", COLOR_GOLD, 26)
	_coins.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(_coins)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	left.add_child(_cell("THE MARKET, WITH TODAY'S NUMBERS", COLOR_DIM, 13))
	_model = RichTextLabel.new()
	_model.bbcode_enabled = true
	_model.fit_content = true
	_model.scroll_active = false
	_model.add_theme_font_size_override("normal_font_size", 15)
	_model.add_theme_font_size_override("bold_font_size", 15)
	_model.add_theme_color_override("default_color", COLOR_TEXT)
	left.add_child(_model)
	left.add_child(_cell("Price p(s) against food sold s  (shaded: what selling 1 kg pays)", COLOR_DIM, 13))
	_graph = PriceGraph.new()
	_graph.custom_minimum_size = Vector2(520, 170)
	left.add_child(_graph)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_food = _cell("", COLOR_TEXT, 15)
	right.add_child(_food)
	right.add_child(_cell("SELL FOOD", COLOR_DIM, 13))
	for kg: float in LOTS:
		var b := _button()
		b.pressed.connect(_sell.bind(kg))
		right.add_child(b)
		_sell_buttons[kg] = b
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	right.add_child(gap)
	right.add_child(_cell("ORDER A SUPPLY POD TO THE LANDING PAD", COLOR_DIM, 13))
	for kind: String in POD_NAMES:
		var b := _button()
		b.pressed.connect(_buy.bind(kind))
		right.add_child(b)
		_buy_buttons[kind] = b
	_message = _cell("", COLOR_GOOD, 14)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_message)

	var footer := _cell("Click to sell or buy      E / Esc: close      (the clock is paused)", COLOR_DIM, 13)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)


func _button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func _cell(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## p(s) = P0*q^s over the kilograms sold, with the next 1 kg sale shaded.
class PriceGraph:
	extends Control
	var _sold := 0.0
	var _food := 0.0

	func set_data(sold: float, food: float) -> void:
		_sold = sold
		_food = food
		queue_redraw()

	func _draw() -> void:
		var c := Base.config
		var r := Rect2(Vector2(44, 8), size - Vector2(56, 30))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.07))
		var s_max := maxf(10.0, ceilf(_sold + 4.0))
		var p_max := c.food_price_start
		var font := get_theme_default_font()
		var to_px := func(s: float, p: float) -> Vector2:
			return Vector2(r.position.x + r.size.x * s / s_max,
					r.end.y - r.size.y * p / p_max)
		# Shaded area: the next 1 kg sale.
		var a := _sold
		var b := _sold + minf(1.0, maxf(_food, 0.0))
		if b > a:
			var poly := PackedVector2Array([to_px.call(a, 0.0)])
			var n := 12
			for i in n + 1:
				var s := lerpf(a, b, float(i) / n)
				poly.append(to_px.call(s, Base.food_price(s)))
			poly.append(to_px.call(b, 0.0))
			draw_colored_polygon(poly, Color(1.0, 0.8, 0.3, 0.35))
		# The curve.
		var pts := PackedVector2Array()
		for i in 101:
			var s := s_max * i / 100.0
			pts.append(to_px.call(s, Base.food_price(s)))
		draw_polyline(pts, Color(1.0, 0.8, 0.3), 2.0, true)
		# Where the market is now.
		var now: Vector2 = to_px.call(_sold, Base.food_price(_sold))
		draw_circle(now, 4.0, Color.WHITE)
		# Axes and labels.
		var axis := Color(0.4, 0.45, 0.55)
		draw_line(r.position, Vector2(r.position.x, r.end.y), axis)
		draw_line(Vector2(r.position.x, r.end.y), r.end, axis)
		draw_string(font, Vector2(4, r.position.y + 10), "%.0f" % p_max,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, axis)
		draw_string(font, Vector2(4, r.end.y), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, axis)
		for s in range(0, int(s_max) + 1, 2):
			var x: float = to_px.call(float(s), 0.0).x
			draw_string(font, Vector2(x - 8, size.y - 4), "%d kg" % s,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, axis)

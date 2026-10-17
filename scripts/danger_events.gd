class_name DangerEvents
extends Node
## Black holes passing close to the Moon.
##
## Every so often a black hole sweeps past. The Control Panel in the Habitat
## switches to its danger screen `warning_hours` before it arrives, and a
## banner counts down. While it passes (`duration_hours`) the only safe place
## is the ice tunnels: anyone outside is pulled off the surface and the game
## ends. Its tides still shake the base apart, so when it has gone the
## machines are broken and need repairing.
##
## Phases: "calm" -> "warning" -> "active" -> "calm" (next one scheduled).

signal warning_started
## The black hole arrived (machines break now).
signal arrived
signal caught
signal passed

## When the first black hole arrives, in in-game hours (picked in this range).
@export var first_hours := Vector2(14.0, 20.0)
## Hours between one black hole leaving and the next arriving.
@export var gap_hours := Vector2(16.0, 22.0)
## How long before arrival the Control Panel warns.
@export var warning_hours: float = 3.0
## How long the black hole takes to pass.
@export var duration_hours: float = 2.0

const TUNNELS := "res://scenes/locations/tunnels.tscn"
const BLACK_HOLE := preload("res://Pixelated Black Hole.png")
## What breaks when the black hole passes.
const DAMAGE := ["dust", "generator_jam", "water_leak", "heater_fault", "blight"]

var phase := "calm"
## Hour the next (or current) black hole arrives.
var arrive_hour := 0.0
## The Main scene (holds `current`, the location the player is in).
var main: Node

var _rng := RandomNumberGenerator.new()
var _layer: CanvasLayer
var _banner: Label
var _hole: TextureRect
var _tint: ColorRect
var _t := 0.0


func _ready() -> void:
	_rng.randomize()
	if not main:
		main = get_parent()
	arrive_hour = _rng.randf_range(first_hours.x, first_hours.y)
	_build()


func _process(delta: float) -> void:
	_t += delta
	if Base.ended:
		_layer.visible = false
		return
	var h := Base.hour
	match phase:
		"calm":
			if h >= arrive_hour - warning_hours:
				phase = "warning"
				warning_started.emit()
		"warning":
			if h >= arrive_hour:
				phase = "active"
				arrived.emit()
				for f: String in DAMAGE:
					if Base.FAILURE_SITES.has(f):
						Base.trigger_failure(f)
		"active":
			if not sheltered():
				phase = "calm"
				caught.emit()
				return
			if h >= arrive_hour + duration_hours:
				phase = "calm"
				arrive_hour = h + _rng.randf_range(gap_hours.x, gap_hours.y)
				passed.emit()
	_update_visuals()


## True while the player is down in the ice tunnels.
func sheltered() -> bool:
	return main.current != null and main.current.scene_file_path == TUNNELS


func in_danger() -> bool:
	return phase != "calm"


func hours_until_arrival() -> float:
	return maxf(arrive_hour - Base.hour, 0.0)


func hours_until_gone() -> float:
	return maxf(arrive_hour + duration_hours - Base.hour, 0.0)


## Text for the Control Panel prompt.
func status_text() -> String:
	match phase:
		"warning":
			return "DANGER: black hole in %s, shelter in the ice tunnels" % _fmt(hours_until_arrival())
		"active":
			return "DANGER: black hole passing, %s left" % _fmt(hours_until_gone())
	return "All clear: next black hole in %s" % _fmt(hours_until_arrival())


func _update_visuals() -> void:
	# Control panels: swap to the danger art, or flash red if there is none.
	for panel: Node2D in get_tree().get_nodes_in_group("control_panels"):
		var sprite := panel.get_node_or_null("Screen") as Sprite2D
		if not sprite:
			continue
		var danger_tex := panel.get_meta("danger_texture") as Texture2D if panel.has_meta("danger_texture") else null
		var normal_tex := panel.get_meta("normal_texture") as Texture2D if panel.has_meta("normal_texture") else null
		if in_danger() and danger_tex:
			sprite.texture = danger_tex
			sprite.modulate = Color.WHITE
		else:
			if normal_tex:
				sprite.texture = normal_tex
			var flash := in_danger() and fmod(_t, 0.8) < 0.4
			sprite.modulate = Color(1.0, 0.45, 0.4) if flash else Color.WHITE

	var flash_on := fmod(_t, 1.0) < 0.6
	match phase:
		"calm":
			_banner.visible = false
			_hole.visible = false
			_tint.visible = false
		"warning":
			_banner.visible = true
			_banner.text = "⚠ BLACK HOLE in %s: get to the ice tunnels (hatch on the Landing Pad)" % _fmt(hours_until_arrival())
			if sheltered():
				_banner.text = "⚠ BLACK HOLE in %s: you are safe down here, wait it out" % _fmt(hours_until_arrival())
			_banner.modulate.a = 1.0 if flash_on else 0.7
			# It grows in the sky as it gets closer (hidden underground).
			var k := 1.0 - hours_until_arrival() / warning_hours
			_hole.visible = not sheltered()
			_hole.scale = Vector2.ONE * lerpf(0.5, 1.6, k)
			_hole.rotation = _t * 0.3
			_tint.visible = false
		"active":
			_banner.visible = true
			_banner.text = "BLACK HOLE PASSING OVERHEAD: stay in the tunnels, %s left" % _fmt(hours_until_gone())
			_banner.modulate.a = 1.0
			_hole.visible = false
			_tint.visible = true
			_tint.color = Color(0.25, 0.0, 0.3, 0.12 + 0.05 * sin(_t * 3.0))


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 8
	add_child(_layer)

	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	_layer.add_child(_tint)

	_hole = TextureRect.new()
	_hole.texture = BLACK_HOLE
	_hole.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hole.size = Vector2(100, 100)
	_hole.pivot_offset = Vector2(50, 50)
	_hole.position = Vector2(692, 35)
	_hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole.visible = false
	_layer.add_child(_hole)

	_banner = Label.new()
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.offset_top = 178.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 20)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_layer.add_child(_banner)


func _fmt(h: float) -> String:
	return "%dh %02dm" % [int(h), int(fmod(h, 1.0) * 60.0)]

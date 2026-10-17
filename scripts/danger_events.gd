class_name DangerEvents
extends Node
## Calamities that send the astronaut into the ice tunnels.
##
## Every so often a calamity arrives: a black hole sweeping past the Moon, or
## an alien UFO raiding the base, or an asteroid shower. They take turns in
## that order (the first is picked at random). The Control Panel in the Habitat switches to its danger screen
## `warning_hours` before one arrives, and a banner counts down. While it lasts
## (`duration_hours`) the only safe place is the ice tunnels: anyone outside is
## pulled off the surface or abducted and the game ends. Either way the base is
## left damaged, so the machines need repairing afterwards.
##
## Phases: "calm" -> "warning" -> "active" -> "calm" (next one scheduled).

signal warning_started
## The calamity arrived (machines break now).
signal arrived
signal caught
signal passed

## When the first calamity arrives, in in-game hours (picked in this range).
@export var first_hours := Vector2(14.0, 20.0)
## Hours between one calamity ending and the next arriving.
@export var gap_hours := Vector2(16.0, 22.0)
## How long before arrival the Control Panel warns.
@export var warning_hours: float = 3.0
## How long each calamity lasts.
@export var duration_hours: float = 2.0

const TUNNELS := "res://scenes/locations/tunnels.tscn"
## name: shown in the banner and on the Control Panel; art: drawn in the sky
## while it approaches; damage: failures it causes when it arrives; caught: how
## the game ends for anyone left outside; tint: screen colour while it lasts.
const KINDS := {
	"black_hole": {
		"name": "BLACK HOLE",
		"art": preload("res://Pixelated Black Hole.png"),
		"passing": "passing overhead",
		# Its tides shake everything, outside and in.
		"damage": ["dust", "generator_jam", "water_leak", "heater_fault", "blight"],
		"caught": "You were outside when the black hole passed at hour %.1f\nand were pulled off the Moon.",
		"tint": Color(0.25, 0.0, 0.3),
	},
	"alien": {
		"name": "ALIEN UFO",
		"art": preload("res://Pixelated Alien UFO .png"),
		"passing": "raiding the base",
		# The aliens smash up the machines inside the base.
		"damage": ["oxygen_leak", "generator_jam", "water_leak", "heater_fault"],
		"caught": "You were outside when the alien UFO raided the base at hour %.1f\nand were abducted.",
		"tint": Color(0.1, 0.45, 0.15),
	},
	"asteroids": {
		"name": "ASTEROID SHOWER",
		"art": preload("res://assests/background/Pixelated Astroid (BIG).png"),
		"passing": "hitting the surface",
		# Impacts out on the surface and holes punched in the hull.
		"damage": ["dust", "oxygen_leak", "water_leak", "blight"],
		"caught": "You were outside when the asteroid shower hit at hour %.1f\nand were struck by a falling rock.",
		"tint": Color(0.5, 0.2, 0.0),
	},
}
## The calamities in the order they take turns.
const ORDER := ["black_hole", "alien", "asteroids"]
const ASTEROID_SMALL := preload("res://assests/background/Pixelated Astroid (SMALL).png")

var phase := "calm"
## Which calamity is next (or happening): a key of KINDS.
var kind := "black_hole"
## Hour the next (or current) calamity arrives.
var arrive_hour := 0.0
## The Main scene (holds `current`, the location the player is in).
var main: Node

var _rng := RandomNumberGenerator.new()
var _layer: CanvasLayer
var _banner: Label
var _hole: TextureRect
var _tint: ColorRect
var _t := 0.0
var _dt := 0.0
## Asteroids streaking across the sky during an asteroid warning:
## {node: TextureRect, velocity: Vector2}.
var _meteors: Array[Dictionary] = []
var _next_meteor := 0.0


func _ready() -> void:
	_rng.randomize()
	if not main:
		main = get_parent()
	arrive_hour = _rng.randf_range(first_hours.x, first_hours.y)
	kind = ORDER[_rng.randi() % ORDER.size()]
	_build()


func _process(delta: float) -> void:
	_t += delta
	_dt = delta
	if Base.ended:
		_layer.visible = false
		return
	var h := Base.hour
	# Resources hold still while a calamity passes, so sheltering in the
	# tunnels can't run a tank dry or over its max.
	Base.frozen = phase == "active"
	match phase:
		"calm":
			if h >= arrive_hour - warning_hours:
				phase = "warning"
				warning_started.emit()
		"warning":
			if h >= arrive_hour:
				phase = "active"
				Base.frozen = true
				arrived.emit()
				for f: String in KINDS[kind].damage:
					if Base.FAILURE_SITES.has(f):
						Base.trigger_failure(f)
		"active":
			if not sheltered():
				phase = "calm"
				caught.emit()
				return
			if h >= arrive_hour + duration_hours:
				phase = "calm"
				Base.frozen = false
				arrive_hour = h + _rng.randf_range(gap_hours.x, gap_hours.y)
				passed.emit()
				# The other calamity comes next.
				kind = ORDER[(ORDER.find(kind) + 1) % ORDER.size()]
	_update_visuals()


## True while the player is down in the ice tunnels.
func sheltered() -> bool:
	return main.current != null and main.current.scene_file_path == TUNNELS


func in_danger() -> bool:
	return phase != "calm"


func hours_until_arrival() -> float:
	return maxf(arrive_hour - Base.hour, 0.0)


## The calamity's name for messages, e.g. "black hole" or "alien UFO".
func kind_name() -> String:
	return KINDS[kind].name.to_lower().replace("ufo", "UFO")


## End-screen text for being caught outside.
func caught_text() -> String:
	return KINDS[kind].caught % Base.hour


func hours_until_gone() -> float:
	return maxf(arrive_hour + duration_hours - Base.hour, 0.0)


## Text for the Control Panel prompt.
func status_text() -> String:
	match phase:
		"warning":
			return "DANGER: %s in %s, shelter in the ice tunnels" % [kind_name(), _fmt(hours_until_arrival())]
		"active":
			return "DANGER: %s %s, %s left" % [kind_name(), KINDS[kind].passing, _fmt(hours_until_gone())]
	return "All clear: next calamity (%s) in %s" % [kind_name(), _fmt(hours_until_arrival())]


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
			var title: String = KINDS[kind].name
			_banner.text = "⚠ %s in %s: get to the ice tunnels (hatch on the Landing Pad)" % [title, _fmt(hours_until_arrival())]
			if sheltered():
				_banner.text = "⚠ %s in %s: you are safe down here, wait it out" % [title, _fmt(hours_until_arrival())]
			_banner.modulate.a = 1.0 if flash_on else 0.7
			# It grows in the sky as it gets closer (hidden underground).
			var k := 1.0 - hours_until_arrival() / warning_hours
			var art: Texture2D = KINDS[kind].art
			if _hole.texture != art:
				_hole.texture = art
				_hole.size = art.get_size()
				_hole.pivot_offset = art.get_size() / 2.0
			_hole.visible = not sheltered()
			if kind == "black_hole":
				_hole.position = Vector2(692, 35)
				_hole.scale = Vector2.ONE * lerpf(0.5, 1.6, k)
				_hole.rotation = _t * 0.3
			else:
				# The UFO sweeps in from the right and bobs as it hovers.
				_hole.position = Vector2(lerpf(1100.0, 692.0, minf(k * 2.0, 1.0)), 50.0 + sin(_t * 2.0) * 8.0)
				_hole.scale = Vector2.ONE * lerpf(0.8, 1.5, k)
				_hole.rotation = sin(_t * 1.3) * 0.08
			if kind == "asteroids":
				# No single object in the sky: rocks streak past instead,
				# more and more often as the shower gets close.
				_hole.visible = false
				if not sheltered():
					_next_meteor -= _dt
					if _next_meteor <= 0.0:
						_spawn_meteor(k)
						_next_meteor = lerpf(1.6, 0.25, k) * _rng.randf_range(0.6, 1.4)
			_tint.visible = false
		"active":
			_banner.visible = true
			_banner.text = "%s %s: stay in the tunnels, %s left" % [
				KINDS[kind].name, KINDS[kind].passing.to_upper(), _fmt(hours_until_gone())]
			_banner.modulate.a = 1.0
			_hole.visible = false
			_tint.visible = true
			_tint.color = Color(KINDS[kind].tint, 0.12 + 0.05 * sin(_t * 3.0))
	_move_meteors()


func _spawn_meteor(k: float) -> void:
	var big := _rng.randf() < lerpf(0.15, 0.5, k)
	var m := TextureRect.new()
	m.texture = KINDS.asteroids.art if big else ASTEROID_SMALL
	m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.size = m.texture.get_size()
	m.scale = Vector2.ONE * _rng.randf_range(0.6, 1.1)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.position = Vector2(_rng.randf_range(500.0, 1250.0), -90.0)
	_layer.add_child(m)
	# The art points down and to the left, so fly that way.
	var speed := _rng.randf_range(420.0, 700.0)
	_meteors.append({"node": m, "velocity": Vector2(-0.8, 0.6) * speed})


func _move_meteors() -> void:
	var out_of_sight := sheltered() or phase != "warning"
	for m: Dictionary in _meteors:
		var node: TextureRect = m.node
		node.position += m.velocity * _dt
		node.visible = not out_of_sight
	var gone := _meteors.filter(func(m: Dictionary) -> bool:
		return m.node.position.y > 700.0 or m.node.position.x < -150.0)
	for m: Dictionary in gone:
		m.node.queue_free()
		_meteors.erase(m)


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
	_hole.texture = KINDS[kind].art
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

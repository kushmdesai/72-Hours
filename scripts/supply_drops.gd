class_name SupplyDrops
extends Node
## Supply pods parachuted from orbit onto the Landing Pad and Solar Array.
##
## Every few in-game hours a pod comes down at a random spot, hanging in the air
## under its parachute. Jump into it (the low gravity makes high grabs possible)
## to collect it before it drifts away. Oxygen and water pods add to those
## tanks, which can push oxygen over its safe max, so look before you grab.
## A toolkit pod instantly repairs everything that is broken.

signal pod_landed(pod: Dictionary)
signal pod_collected(pod: Dictionary)
signal pod_lost(pod: Dictionary)

## In-game hours between drops, picked at random in this range.
@export var interval_hours := Vector2(5.0, 9.0)
## How long a pod waits before drifting off, in in-game hours.
@export var lifetime_hours: float = 8.0
## Height range a pod hangs at above the ground, in metres. Standing, the
## astronaut reaches about 2 m; a full moon jump adds about 3 m, so every pod
## needs a jump and the highest need a full one.
@export var hover_m := Vector2(2.6, 4.4)
## How close (pixels) the astronaut's middle must get to a pod to grab it.
@export var grab_px: float = 30.0

const SITES := {
	"res://scenes/locations/landing_pad.tscn": "Landing Pad",
	"res://scenes/locations/solar_field.tscn": "Solar Array",
}
## kind: [resource, amount, label, colour]
const KINDS := {
	"oxygen": ["oxygen", 1.0, "O₂ +1 kg", Color(0.45, 0.8, 1.0)],
	"water": ["water", 6.0, "H₂O +6 L", Color(0.4, 0.6, 1.0)],
	"toolkit": ["", 0.0, "Toolkit: fixes everything", Color(1.0, 0.8, 0.3)],
}

## Pods waiting to be collected: {id, kind, site, site_name, x_px, height_px,
## landed_hour}.
var pods: Array[Dictionary] = []
var collected := 0

var _next_hour := 3.0
var _next_id := 0
var _rng := RandomNumberGenerator.new()
## The Main scene (holds `current` and the Player). Defaults to the parent.
var main: Node

var _visuals := {}
var _player: Node2D


func _ready() -> void:
	_rng.randomize()
	if not main:
		main = get_parent()
	_player = main.get_node("Player")
	_next_hour = 2.0 + _rng.randf_range(0.0, 2.0)


func _process(_delta: float) -> void:
	if Base.ended:
		return
	if Base.hour >= _next_hour:
		_drop()
		_next_hour = Base.hour + _rng.randf_range(interval_hours.x, interval_hours.y)
	for pod in pods.duplicate():
		if Base.hour - pod.landed_hour > lifetime_hours:
			_remove(pod)
			pod_lost.emit(pod)
	_sync_visuals()
	_check_grab()


## Hours before a pod drifts away.
func hours_left(pod: Dictionary) -> float:
	return maxf(lifetime_hours - (Base.hour - pod.landed_hour), 0.0)


func _drop() -> void:
	var site: String = SITES.keys()[_rng.randi() % SITES.size()]
	var location: Location = load(site).instantiate()
	var width := location.width_px()
	location.free()
	var kind := _pick_kind()
	_next_id += 1
	var pod := {
		"id": _next_id,
		"kind": kind,
		"site": site,
		"site_name": SITES[site],
		"x_px": _rng.randf_range(width * 0.15, width * 0.85),
		"height_px": _rng.randf_range(hover_m.x, hover_m.y) * Location.PIXELS_PER_METER,
		"landed_hour": Base.hour,
	}
	pods.append(pod)
	pod_landed.emit(pod)


## Bias the drop towards what the base needs most right now.
func _pick_kind() -> String:
	if Base.failures.size() >= 2:
		return "toolkit"
	var weights := {"oxygen": 1.0, "water": 1.0, "toolkit": 0.6}
	if Base.oxygen > Base.config.oxygen_max - 1.2:
		weights.oxygen = 0.3
	if Base.water > Base.config.water_max - 8.0:
		weights.water = 0.2
	elif Base.water < 15.0:
		weights.water = 2.0
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := _rng.randf() * total
	for k in weights:
		roll -= weights[k]
		if roll <= 0.0:
			return k
	return "water"


func _check_grab() -> void:
	var here := _current_site()
	var body := _player.global_position + Vector2(0, -16)
	for pod in pods.duplicate():
		if pod.site != here or not _visuals.has(pod.id):
			continue
		var node: Node2D = _visuals[pod.id]
		if node.global_position.distance_to(body) < grab_px:
			_collect(pod)


func _collect(pod: Dictionary) -> void:
	_remove(pod)
	collected += 1
	var info: Array = KINDS[pod.kind]
	if pod.kind == "toolkit":
		for f: String in Base.failures.keys():
			Base.repair(f)
	else:
		Base.add_supplies(info[0], info[1])
	pod_collected.emit(pod)


func _remove(pod: Dictionary) -> void:
	pods.erase(pod)
	if _visuals.has(pod.id):
		_visuals[pod.id].queue_free()
		_visuals.erase(pod.id)


func _current_site() -> String:
	var loc: Node = main.get("current")
	return loc.scene_file_path if loc else ""


## Show the pods that belong to the location on screen, and only those.
func _sync_visuals() -> void:
	var here := _current_site()
	var loc: Node2D = main.get("current")
	var live := {}
	for pod in pods:
		if pod.site == here:
			live[pod.id] = pod
	for id in _visuals.keys():
		var node: Node2D = _visuals[id]
		if not is_instance_valid(node) or not live.has(id):
			if is_instance_valid(node):
				node.queue_free()
			_visuals.erase(id)
	for id in live:
		var pod: Dictionary = live[id]
		if not _visuals.has(id) and loc:
			var ground := _ground_y(loc, pod.x_px)
			if is_nan(ground):
				continue  # Terrain collision not ready yet; try next frame.
			var node := PodVisual.new()
			node.color = KINDS[pod.kind][3]
			node.text = KINDS[pod.kind][2]
			node.position = Vector2(pod.x_px, ground - pod.height_px)
			loc.add_child(node)
			_visuals[id] = node
		if _visuals.has(id):
			_visuals[id].fade = clampf(hours_left(pod) / 1.5, 0.3, 1.0)


## Height of the ground under x in the location, found with a ray cast down
## from just above the surface line (y = 0), or NAN if nothing was hit. The
## ray starts low so it skips the sky and backdrop tiles.
func _ground_y(loc: Node2D, x: float) -> float:
	var space := loc.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			loc.to_global(Vector2(x, -8)), loc.to_global(Vector2(x, 2000)))
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	return loc.to_local(hit.position).y if hit else NAN


## A pod under a parachute, gently swaying.
class PodVisual:
	extends Node2D
	var color := Color.WHITE
	var text := ""
	var fade := 1.0
	var _t := randf() * TAU
	var _label: Label

	func _ready() -> void:
		z_index = 5
		_label = Label.new()
		_label.text = text
		_label.position = Vector2(-80, 14)
		_label.size = Vector2(160, 20)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 11)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 3)
		add_child(_label)

	func _process(delta: float) -> void:
		_t += delta
		rotation = sin(_t * 1.3) * 0.12
		modulate.a = fade if fmod(_t, 0.5) < 0.35 or fade >= 1.0 else fade * 0.4
		queue_redraw()

	func _draw() -> void:
		# Parachute canopy and lines.
		draw_arc(Vector2(0, -34), 22, PI, TAU, 16, Color(0.95, 0.95, 0.95), 3.0)
		draw_line(Vector2(-22, -34), Vector2(-7, -8), Color(0.8, 0.8, 0.8), 1.0)
		draw_line(Vector2(22, -34), Vector2(7, -8), Color(0.8, 0.8, 0.8), 1.0)
		# Crate with a glowing stripe.
		draw_rect(Rect2(-10, -8, 20, 18), Color(0.25, 0.28, 0.32))
		draw_rect(Rect2(-10, -2, 20, 5), color)
		draw_circle(Vector2.ZERO, 16 + sin(_t * 4.0) * 2.0, Color(color, 0.15))

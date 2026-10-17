extends Sprite2D
## The rescue ship. It stays out of sight until the last APPROACH_HOURS before
## the rescue, then comes down over the Landing Pad on its engine (the FIRE
## image), slowing as it nears the ground, and touches down with the engine
## off right at the rescue hour.

## In-game hours before the rescue that the rocket appears in the sky.
const APPROACH_HOURS := 1.5
## Height it starts its descent from, in pixels above the pad.
const START_HEIGHT_PX := 900.0

@export var fire_texture: Texture2D
@export var off_texture: Texture2D

## Sprite y when standing on the pad (the bottom of the hull at y = 0).
var _ground_y := 0.0
var _t := 0.0


func _ready() -> void:
	_ground_y = position.y
	_update()


func _process(delta: float) -> void:
	_t += delta
	_update()


func _update() -> void:
	var left := Base.config.rescue_hours - Base.hour
	if left > APPROACH_HOURS:
		visible = false
		return
	visible = true
	if left <= 0.0:
		texture = off_texture
		position.y = _ground_y
		return
	# Height falls with the square of the time left, so it brakes as it lands.
	var f := left / APPROACH_HOURS
	position.y = _ground_y - START_HEIGHT_PX * f * f
	texture = fire_texture
	# Flicker the engine a little.
	modulate = Color(1, 1, 1) if fmod(_t, 0.16) < 0.08 else Color(1, 0.92, 0.85)

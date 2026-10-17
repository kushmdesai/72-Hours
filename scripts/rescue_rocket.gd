extends Sprite2D
## The rescue ship. It stays out of sight until the last APPROACH_HOURS before
## the rescue, then comes down over the Landing Pad on its engine (the FIRE
## image), slowing as it nears the ground, and touches down with the engine
## off right at the rescue hour. Then it waits for the player: walk up to it and
## press E to board, and it lifts off and flies away before the SURVIVED screen.

## In-game hours before the rescue that the rocket appears in the sky.
const APPROACH_HOURS := 1.5
## Height it starts its descent from, in pixels above the pad.
const START_HEIGHT_PX := 900.0
## How close the player must be to board, in pixels from the rocket's centre.
const BOARD_REACH_PX := 110.0
## Upward acceleration on take-off, in px/s².
const LAUNCH_ACCEL := 450.0
## Seconds of flight shown before the SURVIVED screen.
const LAUNCH_SECONDS := 3.2

@export var fire_texture: Texture2D
@export var off_texture: Texture2D

## Sprite y when standing on the pad (the bottom of the hull at y = 0).
var _ground_y := 0.0
var _t := 0.0
var _launch_t := -1.0
var _departed := false
var _prompt: Label


func _ready() -> void:
	_ground_y = position.y
	_prompt = Label.new()
	_prompt.top_level = true
	_prompt.text = "Rescue ship\nE to board"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.z_index = 20
	_prompt.visible = false
	add_child(_prompt)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _launch_t >= 0.0:
		_fly(delta)
		return
	_update()
	_check_boarding()


func _check_boarding() -> void:
	var player := get_tree().current_scene.get_node_or_null("Player") as Node2D
	var landed := Base.ended and Base.hour >= Base.config.rescue_hours
	var near := player != null and landed and absf(player.global_position.x - global_position.x) < BOARD_REACH_PX
	_prompt.visible = near
	if not near:
		return
	_prompt.global_position = global_position + Vector2(-_prompt.size.x / 2.0, -180.0 - _prompt.size.y)
	if Input.is_action_just_pressed("interact"):
		_board(player)


## The astronaut climbs in and the engine lights.
func _board(player: Node2D) -> void:
	_prompt.visible = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_launch_t = 0.0
	texture = fire_texture


func _fly(delta: float) -> void:
	_launch_t += delta
	# Constant thrust: height = a·t²/2, so it climbs slowly then streaks away.
	position.y = _ground_y - 0.5 * LAUNCH_ACCEL * _launch_t * _launch_t
	modulate = Color(1, 1, 1) if fmod(_t + _launch_t, 0.16) < 0.08 else Color(1, 0.92, 0.85)
	if _launch_t >= LAUNCH_SECONDS and not _departed:
		_departed = true
		get_tree().call_group("systems_controller", "rocket_departed")


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

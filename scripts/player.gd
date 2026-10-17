class_name Player
extends CharacterBody2D
## Astronaut controller with lunar physics.
##
## All tunables are in real-world SI units (metres, seconds) and converted to
## pixels with `pixels_per_meter`, so the in-game motion follows the same
## equations you would use to model a jump on the Moon:
##   apex height  h = v0^2 / (2g)
##   air time     t = 2 * v0 / g

## Surface gravity in m/s^2. Moon = 1.62 (about 1/6 of Earth's 9.81).
@export var gravity_mps2: float = 1.62
## How many pixels represent one metre. The 32px sprite at 2x scale is ~2 m tall.
@export var pixels_per_meter: float = 32.0

@export_group("Running")
## Top horizontal speed in m/s.
@export var max_speed_mps: float = 4.0
## Acceleration while on the ground in m/s^2. Low gravity means less grip.
@export var ground_accel_mps2: float = 8.0
## Deceleration when no key is held on the ground, in m/s^2.
@export var ground_friction_mps2: float = 6.0
## Steering acceleration while airborne, in m/s^2.
@export var air_accel_mps2: float = 2.0

@export_group("Jumping")
## Take-off speed in m/s. 3.13 m/s is what clears 0.5 m on Earth; on the Moon
## the same push gives an apex of about 3 m and roughly 3.9 s of air time.
@export var jump_speed_mps: float = 3.13
## Releasing jump early multiplies upward speed by this, for variable jump height.
@export_range(0.0, 1.0) var jump_cut: float = 0.5
## Grace period after walking off a ledge during which a jump still counts, in s.
@export var coyote_time: float = 0.12
## A jump pressed this long before landing still fires on touchdown, in s.
@export var jump_buffer_time: float = 0.12

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_ensure_input_actions()


func _physics_process(delta: float) -> void:
	var ppm := pixels_per_meter

	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		velocity.y += gravity_mps2 * ppm * delta

	_jump_buffer_timer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = -jump_speed_mps * ppm
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut

	var direction := Input.get_axis("move_left", "move_right")
	var target := direction * max_speed_mps * ppm
	var accel: float
	if is_on_floor():
		accel = ground_accel_mps2 if direction != 0.0 else ground_friction_mps2
	else:
		accel = air_accel_mps2
	velocity.x = move_toward(velocity.x, target, accel * ppm * delta)

	if direction != 0.0:
		_sprite.flip_h = direction < 0.0

	move_and_slide()


## Predicted apex height of a full jump in metres: h = v0^2 / (2g).
func jump_apex_m() -> float:
	return jump_speed_mps * jump_speed_mps / (2.0 * gravity_mps2)


## Predicted air time of a full jump on flat ground in seconds: t = 2 * v0 / g.
func jump_air_time_s() -> float:
	return 2.0 * jump_speed_mps / gravity_mps2


## Registers move/jump actions (arrows, WASD, space) if the project's Input Map
## doesn't define them, so the player works without editing project.godot.
func _ensure_input_actions() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP],
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)

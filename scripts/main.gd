extends Node2D
## Holds the current Location and moves the player between locations when they
## walk off either end of the map.

## Location the game starts in. Its PlayerStart marker sets the spawn point.
@export_file("*.tscn") var start_location: String = "res://scenes/locations/base.tscn"
## How far inside the new location the player appears, in pixels.
@export var entry_margin: float = 24.0

var current: Location
var _tween: Tween

@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D
@onready var _fade: ColorRect = $Overlay/Fade
@onready var _location_label: Label = $Overlay/LocationName


func _ready() -> void:
	add_child(SystemsController.new())
	add_child(StartScreen.new())
	add_child(GameMenu.new())
	_enter(start_location)
	var start := current.get_node_or_null("PlayerStart") as Node2D
	if start:
		_player.position = start.position
	_camera.reset_smoothing()


func _physics_process(_delta: float) -> void:
	var x := _player.position.x
	if x > current.width_px() and current.right_exit != "":
		_enter(current.right_exit)
		_player.position.x = entry_margin
	elif x < 0.0 and current.left_exit != "":
		_enter(current.left_exit)
		_player.position.x = current.width_px() - entry_margin
	else:
		return
	_camera.reset_smoothing()


## Go straight to another location through a hatch or ladder, arriving at the
## node named `arrive` in it (used for the tunnels under the Moonbase).
func travel(path: String, arrive: String) -> void:
	_enter(path)
	var spot := current.get_node_or_null(arrive) as Node2D
	if spot:
		_player.position = spot.position + Vector2(0, -32)
	_player.velocity = Vector2.ZERO
	_camera.reset_smoothing()


func _enter(path: String) -> void:
	if current:
		remove_child(current)
		current.queue_free()
	current = load(path).instantiate()
	add_child(current)
	move_child(current, 0)

	_camera.limit_left = 0
	_camera.limit_right = int(current.width_px())
	_camera.limit_bottom = int(current.depth_px())

	_location_label.text = current.display_name
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_fade.modulate.a = 1.0
	_location_label.modulate.a = 1.0
	_tween.tween_property(_fade, "modulate:a", 0.0, 0.3)
	_tween.tween_interval(1.2)
	_tween.tween_property(_location_label, "modulate:a", 0.0, 0.6)

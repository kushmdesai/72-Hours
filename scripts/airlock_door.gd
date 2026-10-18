class_name AirlockDoor
extends Sprite2D
## An airlock door that slides open while the astronaut is close and shuts
## again once they walk away. A door with `exit_side` set is the way out of
## its location on that side: walking through it takes the player out (see
## main.gd), instead of walking off the edge of the map.

@export var closed_texture: Texture2D
@export var open_texture: Texture2D
## How close the player must be (horizontally, in pixels) for it to open.
@export var open_distance: float = 110.0
## "left" or "right": the location exit this door leads to, or "none".
@export_enum("none", "left", "right") var exit_side: String = "none"

var _player: Node2D


func _ready() -> void:
	texture = closed_texture
	if exit_side != "none":
		add_to_group("exit_doors")


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		var scene := get_tree().current_scene
		_player = scene.get_node_or_null("Player") as Node2D if scene else null
		if not _player:
			return
	var near := absf(_player.global_position.x - global_position.x) < open_distance
	texture = open_texture if near else closed_texture

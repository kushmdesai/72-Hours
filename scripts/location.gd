class_name Location
extends Node2D
## One area of the map (a self-contained scene in scenes/locations/).
##
## The playable strip runs from x = 0 to width_m metres, with the ground surface
## at y = 0. Walking past either edge loads the neighbouring location; an empty
## exit means that edge is a wall the player can't pass.

const PIXELS_PER_METER := 32.0

## Shown on screen when the player arrives.
@export var display_name: String = ""
@export var width_m: float = 40.0
## How far below the surface the camera may look, in metres.
@export var depth_m: float = 12.0
@export_file("*.tscn") var left_exit: String = ""
@export_file("*.tscn") var right_exit: String = ""


func width_px() -> float:
	return width_m * PIXELS_PER_METER


func depth_px() -> float:
	return depth_m * PIXELS_PER_METER

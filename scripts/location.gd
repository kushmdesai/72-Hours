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


## Ground tiles in moon_tileset.tres that get reshuffled every play.
const GROUND_SURFACE := 2 # cratered "mineral" tile
const GROUND_FILL := 3 # plain moon gray
const GROUND_BOTTOM := 4 # Bottom-Layer
const GROUND_SOURCES := [GROUND_SURFACE, GROUND_FILL, GROUND_BOTTOM]

## Picked once per run, so an area looks the same each time you come back to it
## during one play but gets a fresh pattern the next time the game starts.
static var _run_seed: int = randi()


func _ready() -> void:
	_regenerate_ground()


## Re-rolls which moon tile each ground cell uses. The shape of the ground and
## its collision stay exactly as painted in the scene; only the look changes.
func _regenerate_ground() -> void:
	var terrain := get_node_or_null("Terrain") as TileMapLayer
	if terrain == null:
		return

	var ground: Array[Vector2i] = []
	var surface_y := {}
	var lowest_y: int = -(1 << 30)
	for cell in terrain.get_used_cells():
		if terrain.get_cell_source_id(cell) in GROUND_SOURCES:
			ground.append(cell)
			surface_y[cell.x] = mini(surface_y.get(cell.x, cell.y), cell.y)
			lowest_y = maxi(lowest_y, cell.y)

	# Skip the bottom tile if it has been taken out of the tileset, so those
	# cells fall back to plain gray instead of turning into holes.
	var use_bottom := terrain.tile_set.has_source(GROUND_BOTTOM)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_run_seed, scene_file_path])
	for cell in ground:
		var source := GROUND_FILL
		if cell.y == surface_y[cell.x]:
			source = GROUND_SURFACE
		elif use_bottom and cell.y > lowest_y - 3 and rng.randf() < 0.5:
			source = GROUND_BOTTOM
		elif rng.randf() < 0.125:
			source = GROUND_SURFACE
		terrain.set_cell(cell, source, Vector2i.ZERO)

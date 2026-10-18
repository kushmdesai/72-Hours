class_name DayNight
extends Node2D
## Makes the sunlight model S(t) from Base.sunlight() visible.
##
## The Moon's surface and the base are tinted by how much sunlight is falling:
## full colour at noon (S = sunlight_peak), a dim blue at night (S = 0), and in
## between the brightness follows S(t) / sunlight_peak exactly, so the half sine
## the solar panels see is the light you see. The sun sprite rides the same
## angle across the sky: it rises on the left when S(t) turns positive, peaks at
## noon and sets on the right when S(t) drops back to 0.
##
## The sky itself (gradient, stars, sun) is not tinted: the Moon has no
## atmosphere, so its sky stays black and starry in the day too.

## Colour the world is multiplied by at night.
const NIGHT_TINT := Color(0.3, 0.34, 0.52)

@export var sun_texture: Texture2D
@export var sun_scale := 3.0
## Height of the horizon the sun rises from, as a fraction of the screen height.
@export var horizon := 0.62
## How far the sun climbs above the horizon at noon, as a fraction of the screen.
@export var arc_height := 0.5

var _tint: CanvasModulate
var _sun: Sprite2D


func _ready() -> void:
	_tint = CanvasModulate.new()
	add_child(_tint)
	_sun = Sprite2D.new()
	_sun.texture = sun_texture
	_sun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sun.scale = Vector2.ONE * sun_scale
	# In front of the stars (z -10) but behind the backdrop and ground, so it
	# sinks behind the hills as it sets.
	_sun.z_index = -9
	add_child(_sun)


func _process(_delta: float) -> void:
	var light := Base.sunlight() / Base.config.sunlight_peak
	_tint.color = NIGHT_TINT.lerp(Color.WHITE, light)

	# Undo the tint on the sky so only the ground and the base change.
	var untint := Color(1.0 / _tint.color.r, 1.0 / _tint.color.g, 1.0 / _tint.color.b)
	_sun.modulate = untint
	var stars := get_parent().get_node_or_null("Stars") as CanvasItem
	if stars:
		stars.modulate = untint

	_place_sun()


## Puts the sun on its arc across the visible screen. The angle is the same
## one S(t) takes the sine of, so sin(angle) is both its height and the light.
func _place_sun() -> void:
	var angle := fposmod(TAU * (Base.hour + Base.config.day_phase) / Base.config.day_length, TAU)
	_sun.visible = angle < PI
	if not _sun.visible:
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var size := get_viewport_rect().size / camera.zoom
	var top_left := camera.get_screen_center_position() - size / 2.0
	var across := angle / PI
	var x := lerpf(-0.05, 1.05, across) * size.x
	var y := (horizon - arc_height * sin(angle)) * size.y
	_sun.global_position = top_left + Vector2(x, y)

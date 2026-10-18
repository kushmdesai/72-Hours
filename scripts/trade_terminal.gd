class_name TradeTerminal
extends Node2D
## The trade terminal on the Landing Pad: walk up to it and press E to open the
## trade screen (TradePanel), where you sell greenhouse food for coins and spend
## coins to order supply pods down to the pad.

## How close the player must stand, in pixels.
@export var reach_px: float = 48.0

var _player: Node2D
var _prompt: Label
var _t := 0.0
var _panel_closed_frame := -10


func _ready() -> void:
	z_index = -1
	_player = get_tree().current_scene.get_node_or_null("Player")
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.z_index = 20
	_prompt.visible = false
	add_child(_prompt)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if get_tree().paused or not is_instance_valid(_player):
		_prompt.visible = false
		return
	var near := absf(_player.global_position.x - global_position.x) < reach_px
	_prompt.visible = near
	if not near:
		return
	_prompt.text = "Trade terminal: %d coins, %.1f kg food\nE to sell food / buy supplies" % [
		int(Base.coins), Base.food]
	_prompt.position = Vector2(-_prompt.size.x / 2.0, -190.0)
	if Input.is_action_just_pressed("interact") and Engine.get_process_frames() > _panel_closed_frame + 1:
		var panel := TradePanel.new()
		panel.closed.connect(func() -> void: _panel_closed_frame = Engine.get_process_frames())
		get_tree().current_scene.add_child(panel)


func _draw() -> void:
	# A kiosk: post, screen with a coin symbol, and a blinking light.
	draw_rect(Rect2(-6, -70, 12, 70), Color(0.32, 0.35, 0.4))
	draw_rect(Rect2(-26, -108, 52, 42), Color(0.18, 0.2, 0.24))
	draw_rect(Rect2(-22, -104, 44, 34), Color(0.08, 0.2, 0.14))
	var gold := Color(1.0, 0.8, 0.3)
	draw_circle(Vector2(0, -87), 10, gold)
	draw_circle(Vector2(0, -87), 7, gold.darkened(0.3))
	draw_rect(Rect2(-14, -6, 28, 6), Color(0.25, 0.27, 0.3))
	var on := fmod(_t, 1.2) < 0.6
	draw_circle(Vector2(18, -112), 3, Color(0.4, 1.0, 0.55) if on else Color(0.15, 0.35, 0.2))

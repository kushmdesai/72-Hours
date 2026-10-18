extends Node
## Player settings, autoloaded as `Settings`, saved to user://settings.cfg so
## they carry over between runs: sound on/off and volume, full screen, and
## which sky sits behind the Moon. The pages that change them live in the
## pause menu (scripts/game_menu.gd). F11 toggles full screen anywhere.

const PATH := "user://settings.cfg"
const GITHUB_URL := "https://github.com/kushmdesai/MathHacks2.0-2026"
## Sky choices for the Background setting: name shown in the menu, the two
## colours of a top-to-bottom gradient, and whether the starfield shows.
const BACKGROUNDS := {
	"starfield": {"name": "Starfield", "top": Color.BLACK, "bottom": Color.BLACK, "stars": true},
	"earthshine": {"name": "Earthshine blue", "top": Color(0.0, 0.01, 0.04), "bottom": Color(0.04, 0.1, 0.22), "stars": true},
	"nebula": {"name": "Nebula purple", "top": Color(0.02, 0.0, 0.05), "bottom": Color(0.18, 0.05, 0.22), "stars": true},
	"deep": {"name": "Deep space (no stars)", "top": Color.BLACK, "bottom": Color.BLACK, "stars": false},
}
const BACKGROUND_ORDER := ["starfield", "earthshine", "nebula", "deep"]

var sound_on := true
## Master volume, 0 to 1. Decibels are 20·log10(volume), so half volume is
## about −6 dB.
var volume := 0.8
var fullscreen := false
var background := "starfield"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		sound_on = cfg.get_value("audio", "sound_on", sound_on)
		volume = clampf(cfg.get_value("audio", "volume", volume), 0.0, 1.0)
		fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
		background = cfg.get_value("display", "background", background)
		if not BACKGROUNDS.has(background):
			background = "starfield"
	_apply_audio()
	_apply_fullscreen()
	get_tree().node_added.connect(_on_node_added)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		set_fullscreen(not fullscreen)


func set_sound_on(on: bool) -> void:
	sound_on = on
	_apply_audio()
	save()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	save()


func set_background(key: String) -> void:
	if not BACKGROUNDS.has(key):
		return
	background = key
	_apply_background(get_tree().current_scene)
	save()


## The next sky in BACKGROUND_ORDER (for the menu's cycle button).
func next_background() -> void:
	var i := BACKGROUND_ORDER.find(background)
	set_background(BACKGROUND_ORDER[(i + 1) % BACKGROUND_ORDER.size()])


func background_name() -> String:
	return BACKGROUNDS[background].name


func open_github() -> void:
	OS.shell_open(GITHUB_URL)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sound_on", sound_on)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "background", background)
	cfg.save(PATH)


func _apply_audio() -> void:
	if has_node("/root/Sfx"):
		get_node("/root/Sfx").muted = not sound_on
	AudioServer.set_bus_mute(0, not sound_on)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func _apply_fullscreen() -> void:
	# The headless test runs have no window to change.
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## Repaints the sky in the Main scene: Background/Space gets a gradient and
## the Stars layer shows or hides.
func _apply_background(main: Node) -> void:
	if main == null:
		return
	var bg: Dictionary = BACKGROUNDS[background]
	var space := main.get_node_or_null("Background/Space") as TextureRect
	if space:
		var g := Gradient.new()
		g.set_color(0, bg.top)
		g.set_color(1, bg.bottom)
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill_from = Vector2(0, 0)
		tex.fill_to = Vector2(0, 1)
		space.texture = tex
		space.stretch_mode = TextureRect.STRETCH_SCALE
	var stars := main.get_node_or_null("Stars") as CanvasItem
	if stars:
		stars.visible = bg.stars


func _on_node_added(node: Node) -> void:
	# Main is added before its children are ready; wait a frame for them.
	if node.name == "Main" and node.get_parent() == get_tree().root:
		_apply_background.call_deferred(node)

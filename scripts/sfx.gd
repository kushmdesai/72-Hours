extends Node
## Sound effects for the whole game, made from code (no audio files needed).
##
## Autoloaded as `Sfx`. It listens to the Base model's signals and to the
## calamity, supply-drop and player nodes as they enter the tree, so the rest
## of the game does not have to call it. Other scripts can still play a sound
## with `Sfx.play("coin")`. Press N to mute or unmute.
##
## Each sound is a short wave built sample by sample: a tone sliding from one
## pitch to another (f(t) = f0 + (f1 - f0) * t / T) under an envelope that
## rises linearly over `attack` and decays exponentially, e^(-t / decay).

const RATE := 22050
const VOICES := 8
## Pixels walked between footsteps.
const STEP_PX := 44.0

var muted := false

var _sounds := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_coins := 0.0
var _player: CharacterBody2D
var _was_on_floor := true
var _air_time := 0.0
var _step_px := 0.0
var _hum: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sounds()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_hum = AudioStreamPlayer.new()
	_hum.stream = _sounds.hum
	_hum.volume_db = -26.0
	add_child(_hum)
	_hum.play()

	Base.system_toggled.connect(func(_s, on): play("switch_on" if on else "switch_off"))
	Base.failure_started.connect(func(_f): play("alarm"))
	Base.failure_repaired.connect(func(_f): play("repaired"))
	Base.game_over.connect(func(_r, _h, _hi): _end_sound("game_over"))
	Base.game_won.connect(func(): _end_sound("win"))
	Base.supplies_added.connect(func(_r, _a): play("pickup"))
	# Coins arrived later than the rest of Base, so hook them up only if present.
	if Base.has_signal("coins_changed"):
		_last_coins = Base.get("coins")
		Base.coins_changed.connect(_on_coins_changed)
	get_tree().node_added.connect(_on_node_added)


func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted or not _sounds.has(sound):
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	p.stream = _sounds[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func set_muted(on: bool) -> void:
	muted = on
	AudioServer.set_bus_mute(0, on)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		set_muted(not muted)


func _end_sound(sound: String) -> void:
	_hum.stop()
	play(sound)


func _on_coins_changed(coins: float) -> void:
	if coins > _last_coins + 0.01:
		play("coin")
	elif coins < _last_coins - 0.01:
		play("spend")
	_last_coins = coins


## Hooks up things that are created after the game starts.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(func(): play("click", randf_range(0.95, 1.05), -6.0))
		node.mouse_entered.connect(func():
			if not node.disabled:
				play("hover", 1.0, -16.0))
	elif node is DangerEvents:
		node.warning_started.connect(func(): play("siren"))
		node.arrived.connect(func(): play("rumble"))
		node.passed.connect(func(): play("all_clear"))
		node.caught.connect(func(): _end_sound("game_over"))
	elif node is SupplyDrops:
		node.pod_landed.connect(func(_p): play("thud"))
	elif node is Player:
		_player = node
		_was_on_floor = true
		if not _hum.playing:
			_hum.play()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or get_tree().paused:
		return
	var on_floor := _player.is_on_floor()
	if on_floor:
		if not _was_on_floor and _air_time > 0.25:
			# Harder landings are louder: impact speed v = g * t on the way down.
			play("land", randf_range(0.9, 1.1), lerpf(-12.0, 0.0, clampf(_air_time / 2.0, 0.0, 1.0)))
		_air_time = 0.0
		var speed := absf(_player.velocity.x)
		if speed > 30.0:
			_step_px += speed * delta
			if _step_px >= STEP_PX:
				_step_px = 0.0
				play("step", randf_range(0.85, 1.15), -14.0)
		else:
			_step_px = STEP_PX * 0.6
	else:
		if _was_on_floor and _player.velocity.y < -1.0:
			play("jump", randf_range(0.95, 1.05), -8.0)
		_air_time += delta
	_was_on_floor = on_floor


# --- Synthesis -------------------------------------------------------------

func _build_sounds() -> void:
	_sounds.click = _tone([[900, 600, 0.04]], "square", 0.25, 0.002, 0.015)
	_sounds.hover = _tone([[1400, 1400, 0.025]], "sine", 0.2, 0.002, 0.01)
	_sounds.switch_on = _tone([[400, 400, 0.05], [800, 800, 0.08]], "square", 0.3, 0.003, 0.05)
	_sounds.switch_off = _tone([[700, 700, 0.05], [350, 350, 0.08]], "square", 0.3, 0.003, 0.05)
	_sounds.alarm = _tone([[880, 880, 0.14], [0, 0, 0.04], [660, 660, 0.14], [0, 0, 0.04],
			[880, 880, 0.14], [0, 0, 0.04], [660, 660, 0.2]], "square", 0.3, 0.005, 0.5)
	_sounds.repaired = _tone([[523, 523, 0.08], [659, 659, 0.08], [784, 784, 0.18]], "triangle", 0.45, 0.004, 0.12)
	_sounds.coin = _tone([[988, 988, 0.06], [1319, 1319, 0.2]], "square", 0.22, 0.002, 0.1)
	_sounds.spend = _tone([[660, 440, 0.15]], "triangle", 0.4, 0.004, 0.08)
	_sounds.pickup = _tone([[440, 880, 0.18]], "triangle", 0.45, 0.004, 0.1)
	_sounds.siren = _tone([[500, 900, 0.5], [900, 500, 0.5], [500, 900, 0.5], [900, 500, 0.5]], "saw", 0.22, 0.05, 2.0)
	_sounds.rumble = _noise(1.6, 0.6, 0.02, 0.6, 0.97)
	_sounds.thud = _noise(0.45, 0.6, 0.002, 0.12, 0.95)
	_sounds.all_clear = _tone([[392, 392, 0.12], [523, 523, 0.12], [659, 659, 0.12], [784, 784, 0.3]], "triangle", 0.4, 0.005, 0.2)
	_sounds.jump = _tone([[220, 440, 0.16]], "sine", 0.4, 0.004, 0.08)
	_sounds.land = _noise(0.18, 0.5, 0.001, 0.05, 0.9)
	_sounds.step = _noise(0.07, 0.5, 0.001, 0.02, 0.8)
	_sounds.game_over = _tone([[392, 392, 0.3], [330, 330, 0.3], [262, 262, 0.3], [196, 110, 0.9]], "triangle", 0.5, 0.01, 0.6)
	_sounds.win = _tone([[523, 523, 0.15], [659, 659, 0.15], [784, 784, 0.15], [1047, 1047, 0.5]], "square", 0.25, 0.005, 0.4)
	_sounds.hum = _hum_loop()


## Plays notes one after another. Each note is [start Hz, end Hz, seconds];
## 0 Hz is a rest. The envelope restarts on every note.
func _tone(notes: Array, wave: String, volume: float, attack: float, decay: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for note in notes:
		var n := int(note[2] * RATE)
		var phase := 0.0
		for i in n:
			var t := float(i) / RATE
			var f := lerpf(note[0], note[1], float(i) / n)
			phase = fmod(phase + f / RATE, 1.0)
			var s := 0.0
			if note[0] > 0:
				match wave:
					"square": s = 1.0 if phase < 0.5 else -1.0
					"triangle": s = 4.0 * absf(phase - 0.5) - 1.0
					"saw": s = 2.0 * phase - 1.0
					_: s = sin(TAU * phase)
			# Fade out over the last 5 ms so notes do not click.
			var tail := clampf((n - i) / (RATE * 0.005), 0.0, 1.0)
			_push(data, s * volume * _envelope(t, attack, decay) * tail)
	return _wav(data)


## A burst of low-passed noise (a thump or rumble). `smooth` near 1 is darker.
func _noise(seconds: float, volume: float, attack: float, decay: float, smooth: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var n := int(seconds * RATE)
	var y := 0.0
	for i in n:
		y = smooth * y + (1.0 - smooth) * randf_range(-1.0, 1.0)
		var tail := clampf((n - i) / (RATE * 0.01), 0.0, 1.0)
		_push(data, clampf(y * 4.0, -1.0, 1.0) * volume * _envelope(float(i) / RATE, attack, decay) * tail)
	return _wav(data)


## A quiet two-tone machine hum that loops seamlessly (whole cycles of 60 and
## 90 Hz fit exactly in one second).
func _hum_loop() -> AudioStreamWAV:
	var data := PackedByteArray()
	for i in RATE:
		var t := float(i) / RATE
		_push(data, 0.25 * sin(TAU * 60.0 * t) + 0.12 * sin(TAU * 90.0 * t) + 0.03 * sin(TAU * 0.5 * t) * sin(TAU * 180.0 * t))
	var wav := _wav(data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = RATE
	return wav


func _envelope(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


func _push(data: PackedByteArray, s: float) -> void:
	var v := int(clampf(s, -1.0, 1.0) * 32767.0)
	data.append(v & 0xFF)
	data.append((v >> 8) & 0xFF)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

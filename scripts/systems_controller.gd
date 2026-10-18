class_name SystemsController
extends Node2D
## Connects the Base model to the map: switches, repairs, alarms and the end screen.
##
## Walk up to a system console in the Moonbase and press E to open its screen
## (SystemPanel), which shows that system's equations with live numbers and
## switches it on or off (its u_i term in the equations). The Solar Control console connects
## or disconnects the panels, to stop a full battery overcharging. When something has failed, hold E
## at the console (or at any solar panel for dust) to repair it. Each machine's
## sprite shows its on, off or broken art.
##
## It also runs the feel of the game: hold F to fast-forward quiet stretches,
## supply pods to jump for (SupplyDrops), warnings with a hint when a resource
## is heading out of its safe range, a red screen pulse and camera shake when
## things go wrong, and a score with a saved best on the end screen.

## How close the player must stand to a console or panel, in pixels.
@export var reach_px: float = 48.0
## Real seconds E must be held to finish a repair.
@export var repair_seconds: float = 2.0
## Clock multiplier while F is held.
@export var fast_forward_scale: float = 6.0
## Warn when a resource will leave its safe range within this many hours.
@export var warning_hours: float = 3.0

const BEST_PATH := "user://moonbase_best.cfg"
## What to do about each resource heading too low / too high.
const HINTS_LOW := {
	"oxygen": "switch the oxygen generator on",
	"energy": "switch systems off to save power",
	"water": "switch the water recycler on",
	"temperature": "switch the heater on",
	"food": "switch the greenhouse on and keep the cabin near %d °C",
}
const HINTS_HIGH := {
	"oxygen": "switch the oxygen generator off",
	"energy": "disconnect the solar panels at Solar Control",
	"water": "use some water",
	"temperature": "switch the heater off",
	"food": "the pantry is full",
}
const NAMES := {"oxygen": "Oxygen", "energy": "Battery", "water": "Water", "temperature": "Temperature",
		"food": "Food"}

const SYSTEM_LABELS := {
	"solar": "solar panels",
	"oxygen": "oxygen generator",
	"water": "water recycler",
	"heater": "heater",
	"greenhouse": "greenhouse",
	"coal": "coal generator",
}
const COLOR_ON := Color(0.3, 0.9, 0.5)
const COLOR_OFF := Color(0.25, 0.28, 0.32)
const COLOR_BROKEN := Color(1.0, 0.25, 0.2)
const DUST_TINT := Color(0.75, 0.6, 0.45)
const MACHINE_OFF_TINT := Color(0.45, 0.45, 0.5)
const MACHINE_BROKEN_TINT := Color(1.0, 0.45, 0.4)
const DRILLED_TINT := Color(0.35, 0.35, 0.4)
## Glow of the coal generator's firebox while it burns.
const COAL_GLOW := Color(1.0, 0.55, 0.15)

var _player: Node2D
var _target: Node2D
var _target_site := ""
var _repair_progress := 0.0
var _prompt: Label
var _alert: Label
var _end_panel: PanelContainer
var _end_label: Label
var _end_title: Label
var _wasted: ColorRect
var _blink := 0.0
var _drops: SupplyDrops
var _dangers: DangerEvents
var _toasts: Array[Dictionary] = []
var _toast_label: Label
var _speed_label: Label
var _vignette: TextureRect
var _danger := false
var _shake := 0.0
var _ff_blocked := false
var _repairs := 0
## True once the rescue ship has landed and is waiting for the player to board.
var _awaiting_boarding := false
var _debrief: MathDebrief
var _panel_closed_frame := -10
## Whether the coal generator was burning last frame, to notice it running out.
var _coal_burning := false
var _progress_bar: CompletionBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_actions()
	_player = get_parent().get_node("Player")
	_build_ui()
	_drops = SupplyDrops.new()
	_drops.main = get_parent()
	_drops.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_drops)
	_drops.pod_landed.connect(_on_pod_landed)
	_drops.pod_collected.connect(_on_pod_collected)
	_drops.pod_lost.connect(_on_pod_lost)
	_dangers = DangerEvents.new()
	_dangers.main = get_parent()
	_dangers.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_dangers)
	_dangers.warning_started.connect(func() -> void:
		_toast("The %s is coming! Shelter in the ice tunnels" % _dangers.kind_name(), Color(1.0, 0.55, 0.3)))
	_dangers.arrived.connect(func() -> void:
		_shake = 10.0)
	_dangers.passed.connect(func() -> void:
		_toast("The %s has gone: repair the damaged machines" % _dangers.kind_name(), Color(0.6, 1.0, 0.6)))
	_dangers.caught.connect(_on_caught_outside)
	_dangers.shutdown_started.connect(func() -> void:
		_toast("Systems shut down: the base is frozen and you move at quarter speed", Color(0.55, 0.8, 1.0)))
	_dangers.shelter_stocked.connect(func(hours: float) -> void:
		_toast("Stocked the shelter with %s of supplies" % _fmt_hours(hours), Color(0.6, 1.0, 0.6)))
	Base.failure_started.connect(_on_failure_started)
	Base.failure_repaired.connect(_on_failure_repaired)
	Base.game_over.connect(_on_game_over)
	Base.game_won.connect(_on_game_won)
	add_to_group("systems_controller")
	_debrief = MathDebrief.new()
	add_child(_debrief)


func _process(delta: float) -> void:
	if get_tree().paused:
		if _end_panel.visible and Input.is_action_just_pressed("restart"):
			_restart()
		elif _end_panel.visible and Input.is_action_just_pressed("debrief"):
			if _debrief.visible:
				_debrief.close()
			else:
				_debrief.open(_repairs, _drops.collected)
		return
	_blink = fmod(_blink + delta, 1.0)
	_update_visuals()
	_find_target()
	_progress_bar.visible = false
	_handle_input(delta)
	_update_speed()
	_update_alert()
	_update_toasts(delta)
	_update_juice(delta)


func _find_target() -> void:
	_target = null
	_target_site = ""
	var best := reach_px
	for console: Node2D in get_tree().get_nodes_in_group("system_consoles"):
		var d := absf(console.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = console
			_target_site = console.get_meta("system", "")
	for panel: Node2D in get_tree().get_nodes_in_group("solar_panels"):
		var d := absf(panel.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = panel
			_target_site = "panel"
	for hatch: Node2D in get_tree().get_nodes_in_group("hatches"):
		var d := absf(hatch.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = hatch
			_target_site = "hatch"
	for panel: Node2D in get_tree().get_nodes_in_group("control_panels"):
		var d := absf(panel.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = panel
			_target_site = "control"
	for vein: Node2D in get_tree().get_nodes_in_group("ice_veins"):
		var d := absf(vein.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = vein
			_target_site = "ice"
	for seam: Node2D in get_tree().get_nodes_in_group("coal_seams"):
		var d := absf(seam.global_position.x - _player.global_position.x)
		if d < best:
			best = d
			_target = seam
			_target_site = "seam"


func _handle_input(delta: float) -> void:
	if not _target:
		_prompt.visible = false
		_repair_progress = 0.0
		return
	if _target_site == "hatch":
		_repair_progress = 0.0
		if Input.is_action_just_pressed("interact"):
			_prompt.visible = false
			get_parent().travel(_target.get_meta("target"), _target.get_meta("arrive"))
			return
		_show_prompt("%s\nE to %s" % [_target.get_meta("label"), _target.get_meta("action")])
		return
	if _target_site == "ice":
		_handle_drill(delta)
		return
	if _target_site == "seam":
		_handle_mine(delta)
		return
	if _target_site == "control":
		# During a warning, hold E here to pack a survival pack to carry down.
		if _dangers.phase == "warning" and _dangers.pack_blocked() == "" and Input.is_action_pressed("interact"):
			_repair_progress += delta
			if _repair_progress >= repair_seconds:
				_repair_progress = 0.0
				_dangers.pack()
				_toast("Packed %s of air, water and food: carry it down to the tunnels" % _fmt_hours(_dangers.pack_hours), Color(0.6, 0.9, 1.0))
		else:
			_repair_progress = 0.0
		_show_prompt("CONTROL PANEL\n" + _dangers.status_text())
		return
	var site := "solar" if _target_site == "panel" else _target_site
	var broken := Base.failures_at(site)
	var text := ""

	if broken.size() > 0 and not (_target_site == "solar"):
		var failure: String = broken[0]
		if Input.is_action_pressed("interact"):
			_repair_progress += delta
			if _repair_progress >= repair_seconds:
				Base.repair(failure)
				_repair_progress = 0.0
		else:
			_repair_progress = 0.0
		text = "%s\nHold E to repair" % Base.FAILURE_NAMES[failure]
	elif _target_site in Base.SYSTEMS:
		_repair_progress = 0.0
		var on: bool = Base.switches[_target_site]
		if Input.is_action_just_pressed("interact") and Engine.get_process_frames() > _panel_closed_frame + 1:
			_open_panel(_target_site)
			return
		text = "%s: %s\nE to open the console" % [
			SYSTEM_LABELS[_target_site].capitalize(), "ON" if on else "OFF"]
		if _target_site == "solar":
			text += "\nSolar %.1f kW, draw %.1f kW" % [Base.solar_power(), Base.power_draw()]
			if Base.failures.has("dust"):
				text += "\nPanels dusty: clean them on the Solar Array"
		elif _target_site == "coal":
			text += "\nHopper %.1f / %.0f kg of coal, burns %s" % [Base.coal, Base.config.coal_max,
					_fmt_hours(Base.coal_hours())]
			if Base.coal <= 0.0:
				text += "\nEmpty: dig coal from the dark seams in these tunnels"
	else:
		_prompt.visible = false
		return

	_show_prompt(text)


func _show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = true
	_prompt.global_position = _target.global_position + Vector2(-_prompt.size.x / 2.0, -95.0 - _prompt.size.y)
	# Holding E fills a completion bar just under the prompt.
	_progress_bar.visible = _repair_progress > 0.0
	_progress_bar.global_position = _target.global_position + Vector2(0, -86.0)
	_progress_bar.fraction = clampf(_repair_progress / repair_seconds, 0.0, 1.0)
	_progress_bar.queue_redraw()


## Hold E at an ice vein in the tunnels to drill one load of water. Each load is
## r times the last (Base.ice_load), and melting it costs battery energy.
func _handle_drill(delta: float) -> void:
	var vein := String(_target.name)
	var litres := Base.ice_load(vein)
	if litres <= 0.0:
		_repair_progress = 0.0
		_show_prompt("Ice vein\nDrilled dry")
		return
	var cost := litres * Base.config.ice_energy_per_litre
	# Like supply pods, a load only comes up when the base can take it: the
	# water must fit under the tank's max and the melt must not flatten the
	# battery, or drilling would end the run on the spot.
	var blocked := ""
	if Base.water + litres >= Base.max_of("water"):
		blocked = "Tanks too full for this load: use some water first"
	elif Base.energy - cost <= Base.min_of("energy"):
		blocked = "Battery too low to melt this load"
	if Input.is_action_pressed("interact") and blocked == "":
		_repair_progress += delta
		if _repair_progress >= repair_seconds:
			_repair_progress = 0.0
			Base.drill_ice(vein)
			_toast("Drilled ice: H₂O +%.1f L, battery −%.1f kWh" % [litres, cost], Color(0.6, 0.9, 1.0))
			return
	else:
		_repair_progress = 0.0
	var a := Base.config.ice_first_load
	var r := Base.config.ice_load_ratio
	var n: int = Base.ice_drills.get(vein, 0)
	var text := "Ice vein: pass %d brings %.2f L (= %.1f × %.1f^%d)\n" % [n + 1, litres, a, r, n]
	text += "About %.1f L left (= %.2f ÷ (1 − %.1f)), costs %.1f kWh\n" % [Base.ice_left(vein), litres, r, cost]
	text += "⚠ " + blocked if blocked != "" else "Hold E to drill"
	_show_prompt(text)


## Hold E at a coal seam in the tunnels to dig a load of coal straight into the
## coal generator's hopper.
func _handle_mine(delta: float) -> void:
	var seam := String(_target.name)
	var left := Base.coal_left(seam)
	if left <= 0.0:
		_repair_progress = 0.0
		_show_prompt("Coal seam\nDug out")
		return
	var kg := minf(left, Base.config.coal_per_pass)
	var room := Base.config.coal_max - Base.coal
	var blocked := ""
	if room <= 0.01:
		blocked = "The generator's hopper is full: burn some first"
	if Input.is_action_pressed("interact") and blocked == "":
		_repair_progress += delta
		if _repair_progress >= repair_seconds:
			_repair_progress = 0.0
			var got := Base.mine_coal(seam)
			_toast("Dug coal: +%.1f kg, hopper %.1f kg (%s of power)" % [got, Base.coal,
					_fmt_hours(Base.coal_hours())], Color(1.0, 0.75, 0.45))
			return
	else:
		_repair_progress = 0.0
	var c := Base.config
	var text := "Coal seam: %.0f kg left\n" % left
	text += "Each kg burns for %s at %.0f kW = %.1f kWh\n" % [
			_fmt_hours(1.0 / c.coal_burn_rate), c.coal_generator_power, c.coal_generator_power / c.coal_burn_rate]
	text += "⚠ " + blocked if blocked != "" else "Hold E to dig %.0f kg" % minf(kg, room)
	_show_prompt(text)


## Open the machine screen (scripts/system_panel.gd), which pauses the game.
func _open_panel(site: String) -> void:
	_prompt.visible = false
	var panel := SystemPanel.new(site)
	panel.closed.connect(func() -> void:
		_panel_closed_frame = Engine.get_process_frames()
		_update_visuals())
	add_child(panel)


func _update_visuals() -> void:
	var flash := _blink < 0.5
	for console: Node2D in get_tree().get_nodes_in_group("system_consoles"):
		var site: String = console.get_meta("system", "")
		var machine := console.get_node_or_null("Machine") as Sprite2D
		if machine:
			_update_machine(console, machine, site)
			continue
		var screen := console.get_node_or_null("Screen") as ColorRect
		if not screen:
			continue
		if Base.failures_at(site).size() > 0:
			screen.color = COLOR_BROKEN if flash else COLOR_OFF
		elif site == "coal":
			screen.color = COAL_GLOW if Base.coal_running() else COLOR_OFF
		elif site in Base.SYSTEMS:
			screen.color = COLOR_ON if Base.switches[site] else COLOR_OFF
		else:
			screen.color = COLOR_ON if Base.is_day() else COLOR_OFF
	if _coal_burning and not Base.coal_running() and Base.switches.coal:
		_toast("The coal generator ran out of coal: dig more in the tunnels", Color(1.0, 0.7, 0.4))
	_coal_burning = Base.coal_running()
	# Coal seams fade as they are dug out.
	for seam: Node2D in get_tree().get_nodes_in_group("coal_seams"):
		var full := Base.coal_left(seam.name) / Base.config.coal_per_seam
		seam.modulate = DRILLED_TINT.lerp(Color.WHITE, full)
	# Ice veins fade as they are drilled out.
	for vein: Node2D in get_tree().get_nodes_in_group("ice_veins"):
		var full := Base.ice_load(vein.name) / Base.config.ice_first_load
		vein.modulate = DRILLED_TINT.lerp(Color.WHITE, full)
	var dusty := Base.failures.has("dust")
	for panel: Node2D in get_tree().get_nodes_in_group("solar_panels"):
		panel.modulate = DUST_TINT if dusty else Color.WHITE


## Consoles drawn as a sprite swap between their on, off and broken art
## (set as metadata on the Console node). A machine with only on art is
## dimmed when off and flashes red when broken instead.
func _update_machine(console: Node2D, machine: Sprite2D, site: String) -> void:
	var state := "on" if Base.switches.get(site, false) else "off"
	if Base.failures_at(site).size() > 0:
		state = "broken"
	var key := state + "_texture"
	var texture := console.get_meta(key) as Texture2D if console.has_meta(key) else null
	if texture:
		machine.texture = texture
		machine.modulate = Color.WHITE
	elif state == "off":
		machine.modulate = MACHINE_OFF_TINT
	elif state == "broken":
		machine.modulate = MACHINE_BROKEN_TINT if _blink < 0.5 else Color.WHITE


func _update_alert() -> void:
	if _awaiting_boarding:
		_danger = false
		_alert.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_alert.text = "The rescue ship is waiting on the Landing Pad: walk up to it and press E to board"
		_alert.modulate.a = 1.0 if _blink < 0.7 else 0.6
		return
	var lines: PackedStringArray = []
	for f: String in Base.failures:
		var where := "the %s console" % SYSTEM_LABELS[Base.FAILURE_SITES[f]]
		if f == "dust":
			where = "the Solar Array"
		elif f == "blight":
			where = "the Greenhouse out on the Solar Array"
		lines.append("⚠ %s: repair at %s" % [Base.FAILURE_NAMES[f], where])
	var warned := false
	for key in Base.RESOURCES:
		var t := Base.time_until_empty(key)
		if t >= warning_hours:
			continue
		warned = true
		var high := Base.heading_to_max(key)
		var hint: String = HINTS_HIGH[key] if high else HINTS_LOW[key]
		if key == "food" and not high:
			hint = hint % int(Base.config.crop_best_temperature)
		# Point at the repair when the fix is a broken machine.
		if key == "temperature" and not high and Base.failures.has("heater_fault"):
			hint = "repair the heater"
		elif key == "oxygen" and not high and Base.failures.has("generator_jam"):
			hint = "unjam the oxygen generator"
		elif key == "oxygen" and not high and Base.failures.has("oxygen_leak"):
			hint = "fix the oxygen leak"
		elif key == "water" and not high and Base.failures.has("water_leak"):
			hint = "fix the water leak"
		elif key == "food" and not high and Base.failures.has("blight"):
			hint = "clear the blight at the Greenhouse on the Solar Array"
		elif key == "energy" and not high and Base.failures.has("dust"):
			hint = "clean the solar panels or switch systems off"
		lines.append("⚠ %s %s in %s: %s" % [
			NAMES[key], "too high" if high else "too low", _fmt_hours(t), hint])
	_danger = warned or not Base.failures.is_empty()
	_alert.text = "\n".join(lines)
	_alert.modulate.a = 1.0 if _blink < 0.7 else 0.6


## Hold F to fast-forward. A new failure drops back to normal speed until F is
## pressed again, so nothing sneaks past.
func _update_speed() -> void:
	if not Input.is_action_pressed("fast_forward"):
		_ff_blocked = false
	var fast := Input.is_action_pressed("fast_forward") and not _ff_blocked
	Base.time_scale = fast_forward_scale if fast else 1.0
	_speed_label.visible = fast
	_speed_label.text = "▶▶ ×%d" % int(fast_forward_scale)


func _update_juice(delta: float) -> void:
	var target := 0.0
	if _danger:
		target = 0.35 + 0.25 * sin(_blink * TAU)
	_vignette.modulate.a = move_toward(_vignette.modulate.a, target, delta * 2.0)
	var cam := get_viewport().get_camera_2d()
	if cam:
		_shake = maxf(_shake - delta * 20.0, 0.0)
		cam.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))


func _toast(text: String, color: Color = Color.WHITE) -> void:
	_toasts.append({"text": text, "color": color, "time": 5.0})
	if _toasts.size() > 3:
		_toasts.pop_front()


func _update_toasts(delta: float) -> void:
	for t in _toasts:
		t.time -= delta
	_toasts = _toasts.filter(func(t): return t.time > 0.0)
	var lines: PackedStringArray = []
	for t in _toasts:
		lines.append(t.text)
	_toast_label.text = "\n".join(lines)
	# Under the calamity banner (top of the screen) while it shows.
	var banner := _dangers.banner_bottom()
	_toast_label.offset_top = banner + 6.0 if banner > 0.0 else 184.0
	if not _toasts.is_empty():
		_toast_label.add_theme_color_override("font_color", _toasts[-1].color)
	# Point at waiting pods so the player knows where to go.
	var waiting: PackedStringArray = []
	for pod in _drops.pods:
		waiting.append("Supply pod (%s) waiting at the %s: %s left" % [
			pod.kind.capitalize(), pod.site_name, _fmt_hours(_drops.hours_left(pod))])
	if not waiting.is_empty():
		_toast_label.text += ("\n" if not lines.is_empty() else "") + "\n".join(waiting)


func _on_pod_landed(pod: Dictionary) -> void:
	_toast("Supply pod landing on the %s!" % pod.site_name, Color(0.6, 1.0, 0.6))


func _on_pod_collected(pod: Dictionary) -> void:
	_toast("Collected: %s" % SupplyDrops.KINDS[pod.kind][2], Color(0.6, 1.0, 0.6))


func _on_pod_lost(pod: Dictionary) -> void:
	_toast("A %s pod drifted away" % pod.kind, Color(1.0, 0.7, 0.4))


func _fmt_hours(h: float) -> String:
	var m := int(round(h * 60.0))
	return "%dh %02dm" % [m / 60, m % 60]


func _on_failure_started(failure: String) -> void:
	_blink = 0.0
	_shake = 10.0
	_ff_blocked = true
	_toast("ALARM: %s!" % Base.FAILURE_NAMES[failure], COLOR_BROKEN)


func _on_failure_repaired(failure: String) -> void:
	_repair_progress = 0.0
	_repairs += 1
	_toast("Fixed: %s" % Base.FAILURE_NAMES[failure], Color(0.6, 1.0, 0.6))


func _on_game_over(resource: String, hour: float, too_high: bool) -> void:
	var c := Base.config
	var low := {
		"oxygen": "Oxygen fell below %.1f kg and you passed out" % c.oxygen_min,
		"energy": "The battery went flat",
		"water": "The water ran out",
		"temperature": "The base froze below %d °C" % int(c.temperature_min),
		"food": "The food ran out",
	}
	var high := {
		"oxygen": "Oxygen built up past %.1f kg and the air caught fire" % c.oxygen_max,
		"energy": "The battery overcharged past %d kWh and burned out" % int(c.energy_max),
		"water": "The water tank overflowed",
		"temperature": "The base overheated past %d °C" % int(c.temperature_max),
		"food": "The pantry overflowed",
	}
	var reason: String = high[resource] if too_high else low[resource]
	_shake = 14.0
	_show_end("%s at hour %.1f.\nThe rescue ship was %.1f hours away." % [
		reason, hour, Base.hours_until_rescue()], false)


func _on_caught_outside() -> void:
	Base.ended = true
	_shake = 18.0
	_show_end(_dangers.caught_text() + "\nShelter in the ice tunnels when the Control Panel warns you.", false)


## The rescue ship has landed: the model stops and the player has to reach it.
func _on_game_won() -> void:
	_awaiting_boarding = true
	Base.time_scale = 1.0
	_toast("The rescue ship has landed! Get to the Landing Pad and board it", Color(0.6, 1.0, 0.6))


## Called by the rescue rocket once it has flown off with the player aboard.
func rocket_departed() -> void:
	_awaiting_boarding = false
	_alert.visible = false
	var s := "You made it onto the rescue ship. You survived 72 hours!\n"
	s += "Left: %.2f kg oxygen, %.1f kWh, %.1f L water, %.1f kg food, %.1f °C" % [
		Base.oxygen, Base.energy, Base.water, Base.food, Base.temperature]
	_show_end(s, true)


## Score: 10 per hour survived, 40 per repair, 60 per pod, 1000 for the rescue.
func _score(won: bool) -> int:
	return int(Base.hour) * 10 + _repairs * 40 + _drops.collected * 60 + (1000 if won else 0)


func _show_end(text: String, won: bool) -> void:
	var score := _score(won)
	var cfg := ConfigFile.new()
	cfg.load(BEST_PATH)
	var best: int = cfg.get_value("score", "best", 0)
	var record := score > best
	if record:
		cfg.set_value("score", "best", score)
		cfg.save(BEST_PATH)
	text += "\n\nScore %d  (%dh survived, %d repairs, %d pods%s)" % [
		score, int(Base.hour), _repairs, _drops.collected, ", rescued" if won else ""]
	text += "\nNEW BEST!" if record else "\nBest %d" % best
	_end_title.text = "SURVIVED"
	_end_title.visible = won
	_wasted.visible = not won
	_end_label.text = text + "\n\nM  math debrief: graphs and equations of your run\nR  try again"
	_end_panel.visible = true
	_prompt.visible = false
	get_tree().paused = true


func _restart() -> void:
	get_tree().paused = false
	Base.reset()
	get_tree().reload_current_scene()


func _build_ui() -> void:
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.z_index = 20
	_prompt.visible = false
	add_child(_prompt)

	_progress_bar = CompletionBar.new()
	_progress_bar.visible = false
	add_child(_progress_bar)

	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)

	_alert = Label.new()
	_alert.anchor_left = 0.0
	_alert.anchor_right = 1.0
	_alert.anchor_top = 1.0
	_alert.anchor_bottom = 1.0
	# Above the HUD's resource strip along the bottom of the screen.
	_alert.offset_top = -216.0
	_alert.offset_bottom = -126.0
	_alert.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_alert.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert.add_theme_font_size_override("font_size", 16)
	_alert.add_theme_color_override("font_color", COLOR_BROKEN)
	_alert.add_theme_color_override("font_outline_color", Color.BLACK)
	_alert.add_theme_constant_override("outline_size", 4)
	_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_alert)

	_toast_label = Label.new()
	_toast_label.anchor_left = 0.0
	_toast_label.anchor_right = 1.0
	_toast_label.offset_top = 184.0
	_toast_label.offset_bottom = 300.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 4)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast_label)

	_speed_label = Label.new()
	_speed_label.anchor_left = 0.5
	_speed_label.anchor_right = 0.5
	_speed_label.anchor_top = 1.0
	_speed_label.anchor_bottom = 1.0
	_speed_label.offset_left = -60.0
	_speed_label.offset_right = 60.0
	_speed_label.offset_top = -130.0
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_font_size_override("font_size", 22)
	_speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_speed_label.add_theme_constant_override("outline_size", 4)
	_speed_label.visible = false
	layer.add_child(_speed_label)

	# Red glow around the screen edges that pulses while something is wrong.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 0, 0, 0))
	gradient.set_color(1, Color(1, 0.05, 0.05, 0.9))
	gradient.set_offset(0, 0.55)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	layer.add_child(_vignette)
	layer.move_child(_vignette, 0)

	# The end screen darkens the whole window (the frozen game shows through),
	# with its contents centred.
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	_end_panel.add_theme_stylebox_override("panel", style)
	_end_panel.visible = false
	# Its own layer above the location-name overlay (10) so nothing covers it.
	var end_layer := CanvasLayer.new()
	end_layer.layer = 11
	add_child(end_layer)
	end_layer.add_child(_end_panel)
	var end_box := VBoxContainer.new()
	end_box.alignment = BoxContainer.ALIGNMENT_CENTER
	end_box.add_theme_constant_override("separation", 16)
	_end_panel.add_child(end_box)
	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 72)
	_end_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_end_title.add_theme_constant_override("outline_size", 8)
	_end_title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	end_box.add_child(_end_title)
	# The WASTED banner: the art's black bar stretched edge to edge, with its
	# letters (the art minus the black) drawn in the middle.
	var art: Image = load("res://assests/background/Wasted-Screen.png").get_image()
	art = art.get_region(art.get_used_rect())
	art.convert(Image.FORMAT_RGBA8)
	for y in art.get_height():
		for x in art.get_width():
			var px := art.get_pixel(x, y)
			if px.r + px.g + px.b < 0.25:
				art.set_pixel(x, y, Color(0, 0, 0, 0))
	_wasted = ColorRect.new()
	_wasted.color = Color(0, 0, 0, 0.6)
	_wasted.custom_minimum_size.y = art.get_height() * 3.0
	_wasted.visible = false
	end_box.add_child(_wasted)
	var letters := TextureRect.new()
	letters.texture = ImageTexture.create_from_image(art)
	letters.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	letters.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	letters.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	letters.set_anchors_preset(Control.PRESET_FULL_RECT)
	letters.modulate.a = 0.6
	_wasted.add_child(letters)
	_end_label = Label.new()
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 20)
	# The run's numbers sit in their own box under the title.
	var data_box := PanelContainer.new()
	var data_style := StyleBoxFlat.new()
	data_style.bg_color = Color(0.04, 0.06, 0.1)
	data_style.border_color = Color(0.3, 0.36, 0.45)
	data_style.set_border_width_all(2)
	data_style.set_corner_radius_all(6)
	data_style.set_content_margin_all(24)
	data_box.add_theme_stylebox_override("panel", data_style)
	data_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	data_box.add_child(_end_label)
	end_box.add_child(data_box)


func _ensure_input_actions() -> void:
	var bindings := {"interact": KEY_E, "restart": KEY_R, "debrief": KEY_M, "fast_forward": KEY_F}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)


## A small bar that fills while E is held for a repair, a drill or a pack.
class CompletionBar:
	extends Node2D

	const WIDTH := 120.0
	const HEIGHT := 10.0
	var fraction := 0.0

	func _ready() -> void:
		z_index = 20

	func _draw() -> void:
		var r := Rect2(-WIDTH / 2.0, 0.0, WIDTH, HEIGHT)
		draw_rect(r.grow(2.0), Color.BLACK)
		draw_rect(r, Color(0.15, 0.18, 0.22))
		draw_rect(Rect2(r.position, Vector2(WIDTH * fraction, HEIGHT)),
				Color(0.35, 0.9, 0.55).lerp(Color(1.0, 0.85, 0.3), 1.0 - fraction))

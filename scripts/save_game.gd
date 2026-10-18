class_name SaveGame
extends RefCounted
## Saving and loading a run to one of SLOTS files in user://.
##
## A save holds everything that changes during a run: the Base model (clock,
## resources, switches, failures, ice veins, history), the calamity schedule
## (DangerEvents), supply pods (SupplyDrops), the repair count, whether the
## rescue ship is waiting to be boarded, and where the astronaut is. Loading reloads the main scene and then applies the save, so
## everything else starts fresh exactly as on a restart.

const SLOTS := 3
const VERSION := 1

## A save waiting to be applied once the reloaded scene is ready.
static var pending: ConfigFile


static func path(slot: int) -> String:
	return "user://save_%d.cfg" % slot


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


## One line describing a slot for the menu, e.g. "Hour 23.4 · Landing Pad · 2026-10-17 22:40".
static func describe(slot: int) -> String:
	if not exists(slot):
		return "Empty"
	var cfg := ConfigFile.new()
	if cfg.load(path(slot)) != OK:
		return "Unreadable"
	return "Hour %.1f · %s · %s" % [cfg.get_value("meta", "hour", 0.0),
			cfg.get_value("meta", "location_name", "?"),
			str(cfg.get_value("meta", "saved_at", "")).replace("T", " ").left(16)]


## Write the current run to a slot. `main` is the Main scene node.
static func save(slot: int, main: Node) -> Error:
	var ctrl := _controller(main)
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("meta", "saved_at", Time.get_datetime_string_from_system())
	cfg.set_value("meta", "hour", Base.hour)
	cfg.set_value("meta", "location_name", main.current.display_name)

	for key in ["hour", "oxygen", "energy", "water", "temperature", "food"]:
		cfg.set_value("base", key, Base.get(key))
	cfg.set_value("base", "switches", Base.switches.duplicate())
	cfg.set_value("base", "failures", Base.failures.duplicate())
	cfg.set_value("base", "ice_drills", Base.ice_drills.duplicate())
	cfg.set_value("base", "coins", Base.coins)
	cfg.set_value("base", "food_sold", Base.food_sold)
	cfg.set_value("base", "history", Base.history.duplicate(true))

	if ctrl:
		var d: DangerEvents = ctrl._dangers
		cfg.set_value("danger", "phase", d.phase)
		cfg.set_value("danger", "kind", d.kind)
		cfg.set_value("danger", "arrive_hour", d.arrive_hour)
		cfg.set_value("danger", "carried", d.carried.duplicate())
		cfg.set_value("danger", "shelter", d.shelter.duplicate())
		var s: SupplyDrops = ctrl._drops
		cfg.set_value("pods", "pods", s.pods.duplicate(true))
		cfg.set_value("pods", "collected", s.collected)
		cfg.set_value("pods", "next_hour", s._next_hour)
		cfg.set_value("pods", "next_id", s._next_id)
		cfg.set_value("score", "repairs", ctrl._repairs)
		# Hour 72: the ship has landed and is waiting for the player to board.
		cfg.set_value("rescue", "awaiting_boarding", ctrl._awaiting_boarding)

	var player: Node2D = main.get_node("Player")
	cfg.set_value("player", "location", main.current.scene_file_path)
	cfg.set_value("player", "position", player.position)
	return cfg.save(path(slot))


## Load a slot: reload the scene, then apply() it from GameMenu once ready.
static func load_slot(slot: int, tree: SceneTree) -> Error:
	var cfg := ConfigFile.new()
	var err := cfg.load(path(slot))
	if err != OK:
		return err
	pending = cfg
	StartScreen.started = true
	tree.paused = false
	Base.reset()
	tree.reload_current_scene()
	return OK


## Apply the pending save to the freshly loaded scene.
static func apply_pending(main: Node) -> void:
	var cfg := pending
	pending = null
	if not cfg:
		return
	for key in ["hour", "oxygen", "energy", "water", "temperature", "food"]:
		Base.set(key, cfg.get_value("base", key, Base.get(key)))
	Base.switches = cfg.get_value("base", "switches", Base.switches)
	Base.failures = cfg.get_value("base", "failures", {})
	Base.ice_drills = cfg.get_value("base", "ice_drills", {})
	Base.coins = cfg.get_value("base", "coins", 0.0)
	Base.food_sold = cfg.get_value("base", "food_sold", 0.0)
	Base.history.assign(cfg.get_value("base", "history", []))
	Base._invalidate_forecast()

	var ctrl := _controller(main)
	if ctrl:
		var d: DangerEvents = ctrl._dangers
		d.phase = cfg.get_value("danger", "phase", d.phase)
		d.kind = cfg.get_value("danger", "kind", d.kind)
		d.arrive_hour = cfg.get_value("danger", "arrive_hour", d.arrive_hour)
		d.carried = cfg.get_value("danger", "carried", d.carried)
		d.shelter = cfg.get_value("danger", "shelter", d.shelter)
		var s: SupplyDrops = ctrl._drops
		s.pods.assign(cfg.get_value("pods", "pods", []))
		s.collected = cfg.get_value("pods", "collected", 0)
		s._next_hour = cfg.get_value("pods", "next_hour", s._next_hour)
		s._next_id = cfg.get_value("pods", "next_id", s._next_id)
		ctrl._repairs = cfg.get_value("score", "repairs", 0)
		if cfg.get_value("rescue", "awaiting_boarding", false):
			# Back to the ship waiting on the pad: the model stays stopped and
			# the rocket offers boarding, without replaying the landing.
			Base.ended = true
			ctrl._awaiting_boarding = true

	var location: String = cfg.get_value("player", "location", "")
	if location != "" and ResourceLoader.exists(location):
		main._enter(location)
	var player: CharacterBody2D = main.get_node("Player")
	player.position = cfg.get_value("player", "position", player.position)
	player.velocity = Vector2.ZERO
	main.get_node("Player/Camera2D").reset_smoothing()


static func _controller(main: Node) -> SystemsController:
	for child in main.get_children():
		if child is SystemsController:
			return child
	return null

extends Node
## The base's life support as a system of coupled rate equations (autoload "Base").
##
## State: oxygen O (kg), energy E (kWh), water W (L), cabin temperature T (°C).
## Time t is in in-game hours. Every frame each dR/dt is evaluated from the
## current state and the system is advanced with Euler's method:
##   R(t + dt) = R(t) + (dR/dt) * dt
##
##   dO/dt = g*u_gen - c_O - L_O
##   dE/dt = eta*A*S(t) - (P_base + u_gen*P_gen + u_rec*P_rec + u_heat*H)
##   dW/dt = -(1 - r*u_rec)*c_W - k_e*g*u_gen - L_W
##   dT/dt = [H*u_heat - k*(T - T_out(t))] / C
##
## The equations are coupled: the oxygen generator draws water and energy and
## the heater draws energy. Each u_i is 1 when that system is switched on and
## working, else 0. Failures arrive as a Poisson process and change the terms
## until repaired. All constants live in BaseConfig (data/base_config.tres).
##
## The model pushes its numbers into the HUD (group "hud") every frame; other
## scenes can read the getters below or connect to the signals.

## Emitted after every simulation step.
signal updated
## Emitted once per whole in-game hour, after that hour's values are recorded.
signal hour_passed(hour: int)
signal system_toggled(system: String, on: bool)
signal failure_started(failure: String)
signal failure_repaired(failure: String)
## A resource left its safe range: too_high is true if it went over the
## maximum, false if it fell to the minimum. The model stops.
signal game_over(resource: String, hour: float, too_high: bool)
## The rescue ship arrived with every resource above zero. The model stops.
signal game_won
## A supply pod added `amount` to a resource.
signal supplies_added(resource: String, amount: float)

const CONFIG_PATH := "res://data/base_config.tres"
const RESOURCES := ["oxygen", "energy", "water", "temperature"]
## Switchable systems, matching the `system` meta on the base's consoles.
const SYSTEMS := ["solar", "oxygen", "water", "heater"]
## Where each failure is repaired: a system console, or the solar panels.
const FAILURE_SITES := {
	"dust": "solar",
	"oxygen_leak": "oxygen",
	"generator_jam": "oxygen",
	"water_leak": "water",
	"heater_fault": "heater",
}
const FAILURE_NAMES := {
	"dust": "Dust on the solar panels",
	"oxygen_leak": "Oxygen leak",
	"generator_jam": "Oxygen generator jammed",
	"water_leak": "Water pipe leak",
	"heater_fault": "Heater broken",
}

var config: BaseConfig
## In-game hours since the meteor strike.
var hour := 0.0
var oxygen := 0.0
var energy := 0.0
var water := 0.0
var temperature := 0.0
## u_i: which systems the player has switched on.
## The strike happens in the morning, so the heater starts off.
var switches := {"solar": true, "oxygen": true, "water": true, "heater": false}
## Active failures, by id (keys of FAILURE_SITES).
var failures := {}
## When false the clock is frozen (title screen, end screen, tests).
var running := true
## Multiplies the clock speed; the player holds F to fast-forward.
var time_scale := 1.0
## Set once the game is won or lost; the model no longer steps.
var ended := false
## One entry per in-game hour: {hour, oxygen, energy, water, temperature}.
var history: Array[Dictionary] = []

## Forecast settings: Euler step, how far ahead to look, and how often to
## re-run it to absorb drift (all in in-game hours).
const FORECAST_STEP_HOURS := 0.2
const FORECAST_HORIZON_HOURS := 240.0
const FORECAST_REFRESH_HOURS := 0.5

var _rng := RandomNumberGenerator.new()
var _forecast := {}
var _forecast_hour := 0.0
var _hud: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
	else:
		config = BaseConfig.new()
	reset()


## Start a fresh game: restore starting values, clear failures, rewind the clock.
func reset() -> void:
	hour = 0.0
	oxygen = config.oxygen_start
	energy = config.energy_start
	water = config.water_start
	temperature = config.temperature_start
	switches = {"solar": true, "oxygen": true, "water": true, "heater": false}
	failures.clear()
	history.clear()
	ended = false
	running = true
	time_scale = 1.0
	_invalidate_forecast()
	if config.seed == 0:
		_rng.randomize()
	else:
		_rng.seed = config.seed
	_record()


func _process(delta: float) -> void:
	if running and not ended:
		step(delta * config.hours_per_second * time_scale)
	_push_to_hud()


## Advance the model by dt in-game hours with one Euler step, then roll for
## failures and check for the end of the game.
func step(dt: float) -> void:
	if ended or dt <= 0.0:
		return
	var rates := rates()
	oxygen += rates.oxygen * dt
	energy += rates.energy * dt
	water += rates.water * dt
	temperature += rates.temperature * dt

	var previous_hour := int(hour)
	hour += dt
	for h in range(previous_hour + 1, int(hour) + 1):
		_record()
		hour_passed.emit(h)

	_roll_failures(dt)
	updated.emit()
	_check_end()


# --- The rate equations -----------------------------------------------------

## u_gen: 1 if the oxygen generator is on and not jammed.
func generator_running() -> bool:
	return switches.oxygen and not failures.has("generator_jam")


## u_rec: 1 if the water recycler is on.
func recycler_running() -> bool:
	return switches.water


## u_heat: 1 if the heater is on and not broken.
func heater_running() -> bool:
	return switches.heater and not failures.has("heater_fault")


## S(t): sunlight on the panels in kW/m^2, a half sine wave by day, 0 at night.
func sunlight(t: float = hour) -> float:
	var angle := TAU * (t + config.day_phase) / config.day_length
	return config.sunlight_peak * maxf(0.0, sin(angle))


func is_day(t: float = hour) -> bool:
	return sunlight(t) > 0.0


## T_out(t): outside temperature, following the sunlight between night and noon.
func outside_temperature(t: float = hour) -> float:
	var light := sunlight(t) / config.sunlight_peak
	return lerpf(config.outside_night, config.outside_noon, light)


## eta*A*S(t): solar power in kW, cut by dust when that failure is active,
## and 0 while the panels are disconnected at the Solar Control console.
func solar_power(t: float = hour) -> float:
	if not switches.solar:
		return 0.0
	var eta := config.panel_efficiency
	if failures.has("dust"):
		eta *= 1.0 - config.dust_loss
	return eta * config.panel_area * sunlight(t)


## sum(u_i*P_i): power drawn by everything that is running, in kW.
func power_draw() -> float:
	var p := config.power_base
	if generator_running():
		p += config.power_generator
	if recycler_running():
		p += config.power_recycler
	if heater_running():
		p += config.power_heater
	return p


## All four dR/dt at the current state, per in-game hour.
func rates() -> Dictionary:
	return rates_at(hour, oxygen, energy, water, temperature)


## All four dR/dt at any time and state, with the current switches and failures.
func rates_at(t: float, _o: float, e: float, _w: float, temp: float) -> Dictionary:
	var c := config
	var u_gen := 1.0 if generator_running() else 0.0
	var u_rec := 1.0 if recycler_running() else 0.0
	var u_heat := 1.0 if heater_running() else 0.0
	var leak_o := c.oxygen_leak_rate if failures.has("oxygen_leak") else 0.0
	var leak_w := c.water_leak_rate if failures.has("water_leak") else 0.0

	var d_energy := solar_power(t) - power_draw()

	return {
		"oxygen": c.generator_output * u_gen - c.oxygen_use - leak_o,
		"energy": d_energy,
		"water": -(1.0 - c.recycle_efficiency * u_rec) * c.water_use
				- c.water_per_oxygen * c.generator_output * u_gen - leak_w,
		"temperature": (c.power_heater * u_heat
				- c.heat_loss * (temp - outside_temperature(t))) / c.heat_capacity,
	}


func rate(resource: String) -> float:
	return rates()[resource]


func value(resource: String) -> float:
	return get(resource)


# --- Survival time ----------------------------------------------------------

## Hours until a resource leaves its safe range (falls to its min or climbs to
## its max) if the switches stay as they are and nothing new breaks, or INF if
## that doesn't happen within the forecast horizon.
##
## The simple estimate t_empty = R / |dR/dt| only holds while dR/dt is
## constant, but here the rates change on their own: sunlight S(t) rises and
## sets, and Newton's cooling slows as T approaches T_out. So the forecast runs
## the same Euler model forward from the current state (forecast()) and reports
## when each resource crosses a limit. Between forecasts the answer just counts
## down with the clock, since the forecast already accounts for what happens
## in that time.
func time_until_empty(resource: String) -> float:
	if _forecast.is_empty() or hour - _forecast_hour >= FORECAST_REFRESH_HOURS:
		_forecast = forecast()
		_forecast_hour = hour
	return maxf(_forecast[resource] - (hour - _forecast_hour), 0.0)


## True if the forecast has this resource leaving its range over the top
## (too much) rather than through the bottom (too little).
func heading_high(resource: String) -> bool:
	time_until_empty(resource)
	return _forecast.get(resource + "_high", false)


## Run the model ahead from now (no new failures, switches unchanged) and
## return, per resource, the hours until it reaches its min or max, or INF if
## that doesn't happen within FORECAST_HORIZON_HOURS. "<resource>_high" says
## which limit it hits.
func forecast() -> Dictionary:
	var state := {"oxygen": oxygen, "energy": energy, "water": water,
			"temperature": temperature}
	var result := {}
	for key in RESOURCES:
		if not _in_range(key, state[key]):
			result[key] = 0.0
			result[key + "_high"] = state[key] >= max_of(key)
	var dt := FORECAST_STEP_HOURS
	var elapsed := 0.0
	while elapsed < FORECAST_HORIZON_HOURS and result.size() < 2 * RESOURCES.size():
		var r := rates_at(hour + elapsed, state.oxygen, state.energy, state.water, state.temperature)
		for key in RESOURCES:
			if result.has(key):
				continue
			var before: float = state[key]
			var after: float = before + r[key] * dt
			state[key] = after
			if not _in_range(key, after):
				# Interpolate inside the step to the limit it crossed, for a
				# smooth countdown.
				var limit := max_of(key) if after >= max_of(key) else min_of(key)
				result[key] = elapsed + dt * (limit - before) / (after - before)
				result[key + "_high"] = after >= max_of(key)
		elapsed += dt
	for key in RESOURCES:
		if not result.has(key):
			result[key] = INF
	return result


## Throw away the cached forecast; called whenever the equations change.
func _invalidate_forecast() -> void:
	_forecast.clear()


## t_survive = min(t_O, t_E, t_W, t_T).
func survival_time() -> float:
	var best := INF
	for key in RESOURCES:
		best = minf(best, time_until_empty(key))
	return best


## The resource that sets the survival time, or "" if nothing is running out.
func limiting_resource() -> String:
	var best := INF
	var which := ""
	for key in RESOURCES:
		var t := time_until_empty(key)
		if t < best:
			best = t
			which = key
	return which


func hours_until_rescue() -> float:
	return maxf(config.rescue_hours - hour, 0.0)


# --- Systems and failures ---------------------------------------------------

func set_system(system: String, on: bool) -> void:
	assert(system in SYSTEMS, "Unknown system: %s" % system)
	if switches[system] == on:
		return
	switches[system] = on
	_invalidate_forecast()
	system_toggled.emit(system, on)


func toggle_system(system: String) -> void:
	set_system(system, not switches[system])


## Active failures repaired at this site ("solar", "oxygen", "water", "heater").
func failures_at(site: String) -> Array[String]:
	var found: Array[String] = []
	for f: String in failures:
		if FAILURE_SITES[f] == site:
			found.append(f)
	return found


func repair(failure: String) -> void:
	if failures.erase(failure):
		_invalidate_forecast()
		failure_repaired.emit(failure)


## Add a supply delivery to a resource. It can push a resource past its max,
## so grabbing oxygen when the tanks are nearly full is a real risk.
func add_supplies(resource: String, amount: float) -> void:
	set(resource, value(resource) + amount)
	_invalidate_forecast()
	supplies_added.emit(resource, amount)
	_check_end()


## Start a failure now (used by the Poisson roll, and handy for testing).
func trigger_failure(failure: String) -> void:
	assert(FAILURE_SITES.has(failure), "Unknown failure: %s" % failure)
	if failures.has(failure):
		return
	failures[failure] = hour
	_invalidate_forecast()
	failure_started.emit(failure)


## Total failure rate lambda over the failure types that can still happen.
func failure_rate() -> float:
	var total := 0.0
	for f: String in config.failure_rates:
		if not failures.has(f):
			total += config.failure_rates[f]
	return total


## P(at least one new failure within the next t hours) = 1 - e^(-lambda*t).
func failure_chance(t: float) -> float:
	return 1.0 - exp(-failure_rate() * t)


## Each failure type is its own Poisson process: within a step of dt hours it
## happens with probability 1 - e^(-lambda*dt).
func _roll_failures(dt: float) -> void:
	if hour < config.failure_grace_hours:
		return
	for f: String in config.failure_rates:
		if failures.has(f):
			continue
		var p := 1.0 - exp(-float(config.failure_rates[f]) * dt)
		if _rng.randf() < p:
			trigger_failure(f)


# --- Bookkeeping ------------------------------------------------------------

func _check_end() -> void:
	for key in RESOURCES:
		if not _in_range(key, value(key)):
			ended = true
			game_over.emit(key, hour, value(key) >= max_of(key))
			return
	if hour >= config.rescue_hours:
		ended = true
		game_won.emit()
		return


## Lowest safe value of a resource (oxygen_min, energy_min, ...).
func min_of(resource: String) -> float:
	return config.get(resource + "_min")


## Highest safe value of a resource (oxygen_max, energy_max, ...).
func max_of(resource: String) -> float:
	return config.get(resource + "_max")


func _in_range(resource: String, v: float) -> bool:
	return v > min_of(resource) and v < max_of(resource)


func _record() -> void:
	history.append({
		"hour": hour,
		"oxygen": oxygen,
		"energy": energy,
		"water": water,
		"temperature": temperature,
	})


## Feed the HUD (scripts/hud.gd) through its public interface.
func _push_to_hud() -> void:
	if not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud")
		if not _hud:
			return
	var r := rates()
	for key in RESOURCES:
		_hud.set_resource(key, maxf(value(key), 0.0) if key != "temperature" else temperature,
				r[key], time_until_empty(key))
	_hud.set_clock(hour)

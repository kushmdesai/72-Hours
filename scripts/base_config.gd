class_name BaseConfig
extends Resource
## Every tunable constant of the base model, in one place.
##
## Units: time in in-game hours (h), oxygen in kg, energy in kWh, power in kW,
## water in litres, temperature in °C, food in kg. Edit data/base_config.tres in the
## inspector to rebalance without touching code.

@export_group("Clock")
## In-game hours that pass per real second. 0.08 makes the 72 h game last 15 min.
@export var hours_per_second: float = 0.08
## Hours from the meteor strike until the rescue ship lands.
@export var rescue_hours: float = 72.0

@export_group("Starting values")
@export var oxygen_start: float = 2.0
@export var energy_start: float = 30.0
@export var water_start: float = 30.0
@export var temperature_start: float = 21.0
## About a day and a half of food: not enough without the greenhouse.
@export var food_start: float = 2.5

@export_group("Safe ranges")
## Each resource must stay strictly between its min and max; touching either
## limit ends the game.
## Below the minimum the astronaut can't breathe; above the maximum the cabin
## air is oxygen-rich enough to be a fire risk.
@export var oxygen_min: float = 0.5
@export var oxygen_max: float = 4.0
## A flat battery shuts down life support; charging past capacity overheats it.
@export var energy_min: float = 0.0
@export var energy_max: float = 100.0
## The tank holds 40 L, and nothing refills it, so only the minimum matters.
@export var water_min: float = 0.0
@export var water_max: float = 40.0
## Too cold to live below the minimum, heat stroke above the maximum.
@export var temperature_min: float = 5.0
@export var temperature_max: float = 35.0
## Running out of food ends the game. The max is only the pantry's size: food
## grown past it spoils instead of ending the game.
@export var food_min: float = 0.0
@export var food_max: float = 6.0

@export_group("Oxygen  dO/dt = g*u_gen - c_O - L_O")
## g: oxygen generator output in kg/h while switched on.
@export var generator_output: float = 0.09
## c_O: astronaut use, 0.84 kg/day.
@export var oxygen_use: float = 0.035
## L_O: extra drain in kg/h while the oxygen leak failure is active.
@export var oxygen_leak_rate: float = 0.08

@export_group("Energy  dE/dt = eta*A*S(t) - sum(u_i*P_i)")
## eta: solar panel efficiency (0-1).
@export var panel_efficiency: float = 0.22
## A: total panel area in m^2.
@export var panel_area: float = 36.0
## Peak sunlight in kW/m^2 (the solar constant at the Moon, ~1.36).
@export var sunlight_peak: float = 1.36
## Fraction of panel output lost while the dust failure is active.
@export var dust_loss: float = 0.6
## Power draw in kW. Life support, lights and computers are always on.
@export var power_base: float = 0.4
@export var power_generator: float = 1.2
@export var power_recycler: float = 0.4
## H: heater power in kW. The heater turns this much electricity into heat.
@export var power_heater: float = 2.5
## P_gh: greenhouse grow lights and pumps in kW.
@export var power_greenhouse: float = 0.3

@export_group("Water  dW/dt = -(1 - r*u_rec)*c_W - k_e*g*u_gen - L_W")
## c_W: astronaut water use in L/h (12 L/day for drinking, food and hygiene).
@export var water_use: float = 0.5
## r: fraction of used water the recycler recovers while switched on.
@export var recycle_efficiency: float = 0.9
## k_e: litres of water split per kg of oxygen made (H2O is 16/18 oxygen by mass).
@export var water_per_oxygen: float = 1.125
## L_W: extra drain in L/h while the water leak failure is active.
@export var water_leak_rate: float = 1.5

@export_group("Temperature  dT/dt = [H*u_heat - k*(T - T_out)] / C")
## k: heat lost per degree of difference with outside, in kW/°C.
@export var heat_loss: float = 0.012
## C: heat capacity of the habitat in kWh/°C.
@export var heat_capacity: float = 0.9
## Outside temperature at local midnight (lunar surface at night).
@export var outside_night: float = -173.0
## Effective outside temperature at noon around the shaded, insulated hull.
@export var outside_noon: float = 10.0

@export_group("Food  dF/dt = y*u_gh*f(T) - c_F")
## c_F: astronaut food use, 1.8 kg/day.
@export var food_use: float = 0.075
## y: greenhouse crop yield in kg/h at the best temperature.
@export var crop_yield: float = 0.18
## T_opt: cabin temperature the crop grows best at.
@export var crop_best_temperature: float = 23.0
## T_span: growth falls to zero this many °C either side of T_opt, following
## f(T) = max(0, 1 - ((T - T_opt)/T_span)^2).
@export var crop_temperature_span: float = 14.0
## p: kg of oxygen the plants give off per kg of food grown (photosynthesis).
@export var crop_oxygen: float = 0.08
## w_gh: water the plants drink and breathe out in L/h while the greenhouse is on.
@export var greenhouse_water: float = 0.15

@export_group("Ice mining  load_n = a * r^n,  vein total = a / (1 - r)")
## a: litres of water the first pass of the drill brings up from an ice vein.
@export var ice_first_load: float = 3.0
## r: each pass brings up this fraction of the previous one, so a vein holds a
## geometric series of water.
@export_range(0.0, 0.95) var ice_load_ratio: float = 0.5
## kWh of battery spent per litre to drill and melt the ice. Warming ice from
## about -200 °C and melting it takes about 0.21 kWh/L; the drill doubles that.
@export var ice_energy_per_litre: float = 0.5
## A vein counts as empty once the next load would be smaller than this, in L.
@export var ice_min_load: float = 0.2

@export_group("Trading  price(s) = P0 * q^s")
## P0: coins paid for the first kilogram of food sold.
@export var food_price_start: float = 20.0
## q: every kilogram sold so far multiplies the price by q, so the market
## pays less the more you flood it (exponential decay in the amount sold).
@export_range(0.5, 1.0) var food_price_ratio: float = 0.9
## Coins to order a supply pod of each kind to the Landing Pad.
@export var pod_prices: Dictionary = {
	"oxygen": 30,
	"water": 25,
	"food": 25,
	"toolkit": 45,
}

@export_group("Coal  dC/dt = -b*u_coal,  power P_c*u_coal")
## P_c: power the coal generator adds to the battery while it burns, in kW.
@export var coal_generator_power: float = 3.0
## b: kg of coal it burns per hour. Coal holds about 8 kWh of heat per kg and
## a small generator turns about 37% of that into power, so 1 kg/h gives 3 kW.
@export var coal_burn_rate: float = 1.0
## Most coal the generator's hopper holds, in kg.
@export var coal_max: float = 12.0
## kg of coal in each seam in the tunnels.
@export var coal_per_seam: float = 8.0
## kg dug with each pass of the pick.
@export var coal_per_pass: float = 2.0

@export_group("Day and night  S(t) = S_peak * max(0, sin(2*pi*(t + phase)/period))")
## Length of one day/night cycle in in-game hours. A real lunar day lasts
## 29.5 Earth days; it is compressed so the 72 h game sees three nights.
@export var day_length: float = 24.0
## Hours into the cycle at the moment of the strike (0 = sunrise).
@export var day_phase: float = 3.0

@export_group("Failures  P(fail within t) = 1 - e^(-lambda*t)")
## Failure rate lambda for each failure type, per in-game hour.
@export var failure_rates: Dictionary = {
	"dust": 0.02,
	"oxygen_leak": 0.012,
	"generator_jam": 0.012,
	"water_leak": 0.012,
	"heater_fault": 0.01,
	"blight": 0.01,
}
## No failures in the first few hours so the player can learn the controls.
@export var failure_grace_hours: float = 4.0
## Random seed for failures; 0 picks a new seed every game.
@export var seed: int = 0

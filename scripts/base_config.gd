class_name BaseConfig
extends Resource
## Every tunable constant of the base model, in one place.
##
## Units: time in in-game hours (h), oxygen in kg, energy in kWh, power in kW,
## water in litres, temperature in °C. Edit data/base_config.tres in the
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
}
## No failures in the first few hours so the player can learn the controls.
@export var failure_grace_hours: float = 4.0
## Random seed for failures; 0 picks a new seed every game.
@export var seed: int = 0

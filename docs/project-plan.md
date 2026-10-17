# Moonbase: 72 Hours: Project Plan

Step-by-step build order. Each step ends with something playable, so the game stays demo-ready if time runs out.

## 1. Movement (done)
- Astronaut moves left/right and jumps under moon gravity (1.62 m/s², 32 px/m) in `scenes/main.tscn`.

## 2. Base map (done)
- Three locations in `scenes/locations/`, swapped by `scripts/main.gd` when the player walks off either end: Solar Array ← Moonbase → Landing Pad. The outer ends of the Solar Array and Landing Pad are crater cliffs too high to jump.
- The Moonbase is a row of rooms on a TileMapLayer: West Airlock, Solar Control, Oxygen Generator, Water Recycler, Heater, Habitat (start point), East Airlock. Each system room has a `Console` node (group `system_consoles`, meta `system`) ready for step 5.
- The Solar Array has the panels (group `solar_panels`) for dust failures, plus a crater and a boulder to jump. The Landing Pad has a `ShipLandingPoint` for the rescue ship.
- Camera follows the player with limits at the map edges.

## 3. Resource simulation (done)
- Autoload `Base` (`scripts/base.gd`) holds `oxygen`, `energy`, `water`, `temperature` and steps every `dR/dt` with Euler's method each frame. It emits `updated`, `hour_passed`, `system_toggled`, `failure_started`, `failure_repaired`, `game_over` and `game_won`, records one history entry per in-game hour, and pushes values, rates and time-to-empty into the HUD.
- Game clock: 1 real second = 0.08 h, so 72 h takes 15 minutes.
- All constants are in `BaseConfig` (`scripts/base_config.gd`), editable in `data/base_config.tres`.
- `tests/balance_sim.gd` plays the model headless with fixed strategies: everything on runs the battery flat (~22 h), everything off freezes (~10 h), careful play survives even with failures.

## 4. HUD
- Four bars with the current value, rate (+/− per hour) and time until empty.
- A big survival clock showing `t_survive = min(R / |dR/dt|)` next to the hours left until rescue.
- Turn a bar red when its time to empty is less than the rescue time.

## 5. Systems and switches (done)
- `scripts/systems_controller.gd`: press E at a console to switch the oxygen generator, water recycler or heater; screens show green on, grey off, flashing red broken.
- An interactable panel in each room (press E near it) to turn that system on or off.
- Each switch changes its `uᵢ` term in the equations, so the HUD reacts instantly.
- Add the coupling: the oxygen generator uses water and energy, the heater uses energy.

## 6. Day/night cycle (model done, visuals to do)
- `S(t)` is a half sine over a 24 h cycle and `T_out` follows it down to −173 °C at night; the background tint is still to do.
- Sunlight `S(t)` follows the lunar day/night, and outside temperature drops to about −173 °C at night.
- Tint the background and dim the solar input to make it visible.

## 7. Failures (done, sound to do)
- Five Poisson failures (dust, oxygen leak, generator jam, water leak, heater fault) with an alert banner; hold E at the console, or at a solar panel for dust, to repair.
- Random failures as a Poisson process: each hour a system fails with probability `1 − e^(−λ·Δt)`.
- Failure types: dust on panels (lower `η`), oxygen leak (`L_O`), water leak (`L_W`), heater breakdown.
- Show an alarm and a warning icon in the broken room; walking there and holding E repairs it.

## 8. Win and lose (basic version done)
- An end panel names what ran out and when, or the win summary; R restarts.
- Lose screen when any resource leaves its safe min–max range (`BaseConfig` "Safe ranges"), naming which one, whether it went too low or too high, and when.
- Win screen at hour 72 with a summary.

## 9. Math explainer (for judges)
- An end-of-game graph of each resource over the 72 hours (record values every in-game hour and draw them with `Line2D`).
- An in-game "Model" screen showing the equations and the live values plugged in.

## 10. Polish and balance
- Playtest and tune the constants so a careful player survives with a small margin.
- Sound effects for alarms, footsteps and repairs; simple sprites for rooms and astronaut.
- Title screen with a short intro to the emergency.

## 11. Submission
- Export builds (web export so judges can play in a browser).
- Record a 1–2 minute demo video showing a decision changing the survival clock.
- Final README and the project description in `docs/project-description.md`.

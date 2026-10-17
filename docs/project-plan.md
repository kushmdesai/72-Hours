# Moonbase: 72 Hours: Project Plan

Step-by-step build order. Each step ends with something playable, so the game stays demo-ready if time runs out.

## 1. Movement (done)
- Astronaut moves left/right and jumps under moon gravity (1.62 m/s², 32 px/m) in `scenes/main.tscn`.

## 2. Base map (done)
- Three locations in `scenes/locations/`, swapped by `scripts/main.gd` when the player walks off either end: Solar Array ← Moonbase → Landing Pad. The outer ends of the Solar Array and Landing Pad are crater cliffs too high to jump.
- The Moonbase is a row of rooms on a TileMapLayer: West Airlock, Solar Control, Oxygen Generator, Water Recycler, Heater, Habitat (start point), East Airlock. Each system room has a `Console` node (group `system_consoles`, meta `system`) ready for step 5.
- The Solar Array has the panels (group `solar_panels`) for dust failures, plus a crater and a boulder to jump. The Landing Pad has a `ShipLandingPoint` for the rescue ship.
- Camera follows the player with limits at the map edges.

## 3. Resource simulation
- Create an autoload singleton `Base.gd` holding `oxygen`, `energy`, `water`, `temperature`.
- Each frame, compute every `dR/dt` from the rate equations and apply Euler's step `R += rate * delta`.
- Add a game clock: 72 in-game hours mapped to about 15 real minutes (1 real second ≈ 0.08 h). Tune later.
- Put all constants (consumption, generator output, panel efficiency, heat loss `k`) in one config file for easy tuning.

## 4. HUD
- Four bars with the current value, rate (+/− per hour) and time until empty.
- A big survival clock showing `t_survive = min(R / |dR/dt|)` next to the hours left until rescue.
- Turn a bar red when its time to empty is less than the rescue time.

## 5. Systems and switches
- An interactable panel in each room (press E near it) to turn that system on or off.
- Each switch changes its `uᵢ` term in the equations, so the HUD reacts instantly.
- Add the coupling: the oxygen generator uses water and energy, the heater uses energy.

## 6. Day/night cycle
- Sunlight `S(t)` follows the lunar day/night, and outside temperature drops to about −173 °C at night.
- Tint the background and dim the solar input to make it visible.

## 7. Failures
- Random failures as a Poisson process: each hour a system fails with probability `1 − e^(−λ·Δt)`.
- Failure types: dust on panels (lower `η`), oxygen leak (`L_O`), water leak (`L_W`), heater breakdown.
- Show an alarm and a warning icon in the broken room; walking there and holding E repairs it.

## 8. Win and lose
- Lose screen when any resource hits zero (or temperature falls below the safe limit), naming which one ran out and when.
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

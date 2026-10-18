# How the code works

*Moonbase: 72 Hours* is a 2D side-scroller made in Godot 4 with GDScript. Under the game sits one mathematical model of the base's life support, and almost every other script either feeds that model (switches, repairs, supplies, calamities) or shows it to the player (HUD, machine screens, alerts). This document walks through how the pieces fit. For the equations themselves and why they were chosen, see [math.md](math.md).

## Contents

1. [The big picture](#1-the-big-picture)
2. [Project layout](#2-project-layout)
3. [Startup and the scene tree](#3-startup-and-the-scene-tree)
4. [The model: `Base` (scripts/base.gd)](#4-the-model-base-scriptsbasegd)
5. [All the numbers: `BaseConfig`](#5-all-the-numbers-baseconfig)
6. [The world: locations, doors and travel](#6-the-world-locations-doors-and-travel)
7. [The astronaut: `Player`](#7-the-astronaut-player)
8. [The glue: `SystemsController`](#8-the-glue-systemscontroller)
9. [Machine screens: `SystemPanel`](#9-machine-screens-systempanel)
10. [The HUD](#10-the-hud)
11. [Supply pods](#11-supply-pods)
12. [Trading: coins for food, pods for coins](#12-trading-coins-for-food-pods-for-coins)
13. [Calamities](#13-calamities)
14. [Rescue, the end screen and the math debrief](#14-rescue-the-end-screen-and-the-math-debrief)
15. [Sound effects](#15-sound-effects)
16. [Title screen, tutorial, menus and saving](#16-title-screen-tutorial-menus-and-saving)
17. [The balance test](#17-the-balance-test)
18. [One frame, start to finish](#18-one-frame-start-to-finish)
19. [How to change things](#19-how-to-change-things)

---

## 1. The big picture

```
                 ┌──────────────────────────────────────────┐
                 │  Base (autoload, scripts/base.gd)         │
                 │  state: hour, O, E, W, T, F               │
                 │  switches u_i, failures, ice veins        │
 config ───────▶ │  rates() → Euler step → check limits      │
 (BaseConfig)    │  forecast() → time until each limit       │
                 └──────▲───────────────┬───────────────────┘
   writes: switches,    │               │ reads: values, rates, forecasts
   repairs, supplies,   │               │ signals: failure_started, game_over…
   frozen, failures     │               ▼
 ┌──────────────────────┴──┐     ┌────────────────────────────┐
 │ SystemsController        │     │ HUD, SystemPanel, alerts,   │
 │ SupplyDrops, DangerEvents│     │ machine sprites, end screen │
 │ (input + game events)    │     │ (display)                   │
 └──────────────────────────┘     └────────────────────────────┘
```

The design rule is that **the model knows nothing about the screen**. `Base` holds numbers and equations only. Everything visual reads from it, and everything the player does goes through a small set of methods on it (`set_system`, `repair`, `add_supplies`, `drill_ice`, `trigger_failure`). This keeps the math in one file that can be tested on its own (see the [balance test](#15-the-balance-test)).

## 2. Project layout

| Path | What it is |
|---|---|
| `project.godot` | Engine settings. Registers `Base` and `Sfx` as autoloads and sets `scenes/main.tscn` as the main scene. |
| `scenes/main.tscn` | The root scene: background, starfield, the `Player` with its camera, the HUD and an overlay for fades. |
| `scenes/hud.tscn` | A `CanvasLayer` that runs `scripts/hud.gd`. |
| `scenes/locations/*.tscn` | The four areas: `solar_field`, `base`, `landing_pad`, `tunnels`. |
| `scripts/base.gd` | The resource model (autoload `Base`). |
| `scripts/base_config.gd` | `BaseConfig`, the class declaring every tunable constant. |
| `data/base_config.tres` | The saved instance of `BaseConfig` that the game loads. |
| `scripts/main.gd` | Owns the current location and moves the player between them. |
| `scripts/location.gd` | `Location`, the base class for each area scene. |
| `scripts/player.gd` | `Player`, the astronaut with lunar physics. |
| `scripts/airlock_door.gd` | `AirlockDoor`, doors that open as you approach. |
| `scripts/systems_controller.gd` | `SystemsController`: interaction, alerts, toasts, fast-forward, the end screen. |
| `scripts/system_panel.gd` | `SystemPanel`, the pop-up machine screen with equations and a what-if graph. |
| `scripts/hud.gd` | `Hud`, the resource bars, survival clock and systems panel. |
| `scripts/supply_drops.gd` | `SupplyDrops`, parachuted supply pods. |
| `scripts/danger_events.gd` | `DangerEvents`, the black hole, alien UFO and asteroid shower. |
| `scripts/trade_terminal.gd` | `TradeTerminal`, the TRADE console on the Landing Pad. |
| `scripts/trade_panel.gd` | `TradePanel`, the trade screen: sell food, buy pods, with a price graph. |
| `scripts/rescue_rocket.gd` | The rescue ship's landing and take-off. |
| `scripts/math_debrief.gd` | `MathDebrief`, the end-of-run graphs and equations (M on the end screen). |
| `scripts/sfx.gd` | The `Sfx` autoload: every sound effect, synthesised in code. |
| `scripts/start_screen.gd` | `StartScreen`, the title screen. |
| `scripts/tutorial.gd` | `Tutorial`, the guided first run (T on the title screen). |
| `scripts/game_menu.gd` | `GameMenu`, the pause menu with save and load. |
| `scripts/save_game.gd` | `SaveGame`, static helpers that write and read save files. |
| `tests/balance_sim.gd` | A headless script that plays the model with fixed strategies. |
| `docs/` | The original pitch (`project-description.md`) and build plan (`project-plan.md`). |
| `assests/` and root `.png` files | Pixel art. |

## 3. Startup and the scene tree

1. Godot loads the **autoloads** before any scene. `Base`'s `_ready()` loads `data/base_config.tres` (falling back to a default `BaseConfig` if the file is missing) and calls `reset()` to set the starting values. `Sfx` builds its sounds and connects to `Base`'s signals.
2. The main scene `scenes/main.tscn` loads. Its root node runs `scripts/main.gd`, whose `_ready()` creates three more nodes in code:
   - `SystemsController`, which in turn creates `SupplyDrops`, `DangerEvents` and `MathDebrief` as its children,
   - `StartScreen`, which pauses the tree until the player presses Enter,
   - `GameMenu`, the hidden pause menu,
   - `Tutorial`, but only if the title screen started one (`Tutorial.active`).
3. `main.gd` then loads the start location (`base.tscn`) and puts the player on its `PlayerStart` marker.

The resulting tree looks like this:

```
root
├── Base                     (autoload, the model)
├── Sfx                      (autoload, sound effects)
└── Main                     (main.gd)
    ├── <current Location>   (always child 0, swapped on travel)
    ├── Background, Stars
    ├── Player
    │   └── Camera2D
    ├── HUD                  (hud.gd, group "hud")
    ├── Overlay              (fade + location name)
    ├── SystemsController
    │   ├── SupplyDrops
    │   ├── DangerEvents
    │   └── MathDebrief      (hidden until M on the end screen)
    ├── StartScreen          (removed once the game starts)
    ├── GameMenu
    └── Tutorial             (only in a tutorial run)
```

**Pausing.** Godot's `get_tree().paused` stops every node whose `process_mode` is `PAUSABLE`. `Base`, `SupplyDrops` and `DangerEvents` are pausable, so the clock stops. The title screen, the pause menu, the machine screens and `SystemsController` are `ALWAYS`, so they keep reacting to keys while the world is frozen.

## 4. The model: `Base` (scripts/base.gd)

`Base` is the heart of the game. It is an autoload, so any script can write `Base.oxygen` or `Base.repair("dust")`.

### State

| Variable | Meaning |
|---|---|
| `hour` | In-game hours since the meteor strike. |
| `oxygen`, `energy`, `water`, `temperature`, `food` | The five resources (kg, kWh, L, °C, kg). |
| `switches` | `{"solar", "oxygen", "water", "heater", "greenhouse", "coal"}` → on/off. These are the `uᵢ` terms of the equations. |
| `coal` | kg of coal in the coal generator's hopper. It is not one of the five survival resources (running out just stops the generator), but it is stepped with them. |
| `failures` | Active failures by id, mapped to the hour they started. |
| `ice_drills` | How many times each ice vein has been drilled. |
| `coal_mined` | kg already dug out of each coal seam. |
| `coins`, `food_sold` | The coin balance, and how many kg of food have been sold (which sets the market price). |
| `history` | One snapshot of every resource per whole in-game hour. |
| `running`, `ended`, `frozen`, `time_scale` | Clock control: paused, game over, calamity freeze, fast-forward multiplier. |

### The simulation step

Every frame, `_process(delta)` converts real seconds into in-game hours and calls `step(dt)`:

```gdscript
step(delta * config.hours_per_second * time_scale)
```

With `hours_per_second = 0.08`, one real second is 0.08 in-game hours (4.8 minutes), so the 72-hour game lasts 15 real minutes. Holding F sets `time_scale` to 6.

`step(dt)` does four things in order:

1. **Euler update.** It asks `rates()` for every `dR/dt`, then adds `rate × dt` to each resource. Food is clamped to its pantry size (extra food spoils), and coal is clamped at zero.
2. **Clock.** It advances `hour`. Each time a whole hour is crossed it appends a `history` entry and emits `hour_passed`.
3. **Failures.** `_roll_failures(dt)` rolls the dice for each failure type that is not already active.
4. **End check.** `_check_end()` ends the game if any resource has left its safe range (`game_over`), or if the rescue hour has arrived (`game_won`).

When `frozen` is true (set during a calamity), steps 1 and 3 are skipped: the clock runs but the resources and failures hold still.

### The rate equations

`rates_at(t, o, e, w, temp, coal)` is the single function that implements the model. It returns a dictionary of rates (the five resources plus coal) for any time and state, using the current switches and failures. `rates()` is just `rates_at` at the current state. Small helpers each compute one term:

| Helper | Term |
|---|---|
| `generator_running()`, `recycler_running()`, `heater_running()`, `greenhouse_running()` | the `uᵢ` switches, which are 0 if the system is off **or** broken |
| `sunlight(t)` | `S(t)`, a half sine wave |
| `outside_temperature(t)` | `T_out(t)`, between −173 °C and 10 °C following the sunlight |
| `solar_power(t)` | `η·A·S(t)`, cut by dust and zero when the panels are disconnected |
| `coal_running(c)`, `coal_power(c)`, `coal_hours()` | `u_coal` (switched on **and** coal left), the generator's `P_c·u_coal`, and how long the hopper lasts `C/b` |
| `power_draw()` | `Σ uᵢ·Pᵢ` |
| `growth_factor(T)`, `crop_growth(T)` | the greenhouse's temperature curve `f(T)` and food output |

Because every other script (the forecast, the machine screens, the balance test) calls this same `rates_at`, there is exactly one copy of the physics.

### Forecasts and the survival clock

`forecast()` copies the current state and runs the same Euler model ahead in steps of 0.2 h for up to 240 h, assuming the switches stay as they are and nothing new breaks. It also burns down a copy of the coal, so a forecast made with a nearly empty hopper sees the generator stop partway through. For each resource it records when it first crosses its min or max, interpolating inside the step for a smooth countdown, and whether it went out the top (`_forecast_hits_max`).

Running 1,200 steps every frame would be wasteful, so `time_until_empty(resource)` caches the forecast and only recomputes it every 0.5 in-game hours. Between refreshes it subtracts the hours that have passed. Anything that changes the equations (a switch, a failure, a repair, a supply pod) calls `_invalidate_forecast()` so the next read recomputes straight away.

On top of that:
- `survival_time()` is the minimum over all five resources.
- `limiting_resource()` names which one it is.
- `heading_to_max(resource)` tells the HUD and alerts whether the danger is "too high" or "too low".

### Player actions on the model

| Method | What it does |
|---|---|
| `set_system(name, on)` / `toggle_system(name)` | Flip a `uᵢ`. Emits `system_toggled`. |
| `repair(failure)` | Remove a failure. Emits `failure_repaired`. |
| `trigger_failure(failure)` | Start a failure (used by the random roll and by calamities). |
| `add_supplies(resource, amount)` | Add (or subtract) an amount directly, then check the limits. Used by pods and by drilling. |
| `ice_load(vein)`, `ice_left(vein)`, `drill_ice(vein)` | The geometric-series ice veins. |
| `mine_coal(seam)`, `coal_left(seam)` | Dig one load (2 kg) from a coal seam into the hopper, up to the hopper's 12 kg. |
| `failure_rate()`, `failure_chance(t)` | The total Poisson rate and the chance of a breakdown within `t` hours, shown on the HUD. |
| `food_price()`, `food_sale_value(kg)`, `sell_food(kg)` | The food market: the current price per kg, what a sale would pay, and the sale itself. |
| `pod_price(kind)`, `buy_pod(kind)` | Pay coins for a supply pod (returns false if you can't afford it). |

### Talking to the HUD

At the end of each `_process`, `_push_to_hud()` finds the node in group `"hud"` and calls `set_resource(key, value, rate, time_left)` for each resource and `set_clock(hour)`. It reads the HUD's `CONFIG` constant first and skips any resource the HUD has no row for, so the two can evolve separately.

### Signals

`updated`, `hour_passed(hour)`, `system_toggled(system, on)`, `failure_started(failure)`, `failure_repaired(failure)`, `game_over(resource, hour, too_high)`, `game_won`, `supplies_added(resource, amount)`, `coins_changed(coins)`. Other scripts connect to these rather than polling.

## 5. All the numbers: `BaseConfig`

`scripts/base_config.gd` declares a `Resource` class with one `@export` variable per constant, grouped by equation (Clock, Starting values, Safe ranges, Oxygen, Energy, Water, Temperature, Food, Ice mining, Trading, Coal, Day and night, Failures). Each group's heading is the equation it feeds, and each variable's comment gives its symbol and unit.

`data/base_config.tres` is an instance of that class. It currently stores no overrides, so every value is the default written in the `.gd` file, but opening the `.tres` in the Godot inspector lets you rebalance the whole game with sliders without touching code.

The safe ranges follow a naming convention, `<resource>_min` and `<resource>_max`, so `Base.min_of("water")` is just `config.get("water_min")`.

## 6. The world: locations, doors and travel

### Locations

Each area is its own scene whose root runs `Location` (`scripts/location.gd`). A location knows its `display_name`, its width and depth in metres, and which scene lies off its `left_exit` and `right_exit`. The map is:

```
Solar Array  ⇄  Moonbase  ⇄  Landing Pad
                                 │ hatch / ladder
                             Ice Tunnels
```

- **Solar Array**: the solar panels (group `solar_panels`, cleaned of dust here) and the Greenhouse console.
- **Moonbase**: a row of rooms (West Airlock, Solar Control, Oxygen Generator, Water Recycler, Heater, Habitat with the Control Panel, East Airlock). Each machine room has a `Console` node in group `system_consoles` with a `system` meta naming which switch it controls, and `on_texture`, `off_texture`, `broken_texture` metas for its art.
- **Landing Pad**: the `ShipLandingPoint` where supply pods fall and the rescue ship lands, the TRADE terminal, and a `TunnelHatch` (group `hatches`).
- **Ice Tunnels**: the shelter from calamities, with three ice veins (group `ice_veins`), three coal seams (group `coal_seams`), the coal generator (a `system_consoles` node with `system = "coal"`), and a ladder back up.

Coordinates use 32 pixels per metre (`Location.PIXELS_PER_METER`), with the ground surface at `y = 0`. When a location loads, `_regenerate_ground()` reshuffles which moon tile each ground cell uses (seeded per run and per scene), so the terrain looks different each game but the collision shape never changes.

### Moving between locations

`main.gd` checks the player's x every physics frame. If they pass the exit point on either side and there is a neighbouring scene, `_enter(path)` frees the current location, instantiates the new one as child 0, sets the camera limits to its size, and fades in its name.

The exit point is the airlock door on that side if the location has one (an `AirlockDoor` with `exit_side` set, in group `exit_doors`), otherwise the map edge. On arrival the player is placed just inside the matching door or edge.

`travel(path, arrive)` is the other way to move: hatches and ladders call it to jump straight to a named node in another scene, which is how the tunnels connect to the Landing Pad.

`AirlockDoor` itself is tiny: each frame it swaps to its open texture when the player is within `open_distance` pixels.

## 7. The astronaut: `Player`

`scripts/player.gd` is a `CharacterBody2D` whose tunables are all in SI units (metres, seconds) and multiplied by `pixels_per_meter` when applied. Each physics frame it:

1. adds gravity `g = 1.62 m/s²` to the vertical velocity while airborne,
2. starts a jump at `v₀ = 3.13 m/s` if jump was pressed recently (a 0.12 s **jump buffer**) and the player was on the ground recently (0.12 s of **coyote time**),
3. halves the upward speed if jump is released early, for variable jump height,
4. accelerates horizontally towards the target speed with different rates on the ground, while braking and in the air (less grip in low gravity),
5. slows to a quarter speed while `Base.frozen` is true,
6. calls `move_and_slide()` and picks a sprite (standing, a walk cycle advanced by distance walked, or jumping).

`jump_apex_m()` and `jump_air_time_s()` return the predicted height and hang time from the projectile formulas, which [math.md](math.md#10-lunar-gravity-and-the-jump) derives.

## 8. The glue: `SystemsController`

`scripts/systems_controller.gd` connects the model to the map and runs most of the game feel. Every frame it:

- **Finds a target.** It looks for the nearest console, solar panel, hatch, control panel or ice vein within `reach_px` (48 px) of the player, horizontally.
- **Handles input on that target.** Anything that needs E held (repairing, drilling, packing) fills a small completion bar under the prompt.
  - At a **broken** machine (or any solar panel when the panels are dusty), holding E fills a repair bar over `repair_seconds` (2 s), then calls `Base.repair()`.
  - At a **working** machine, pressing E opens its `SystemPanel`.
  - At a **hatch**, E calls `main.travel()`.
  - At a **coal seam**, holding E digs 2 kg straight into the generator's hopper (`Base.mine_coal`), blocked when the hopper is full. The prompt shows what each kilogram is worth: 1 h of burning at 3 kW, or 3 kWh.
  - At the **Control Panel**, the prompt shows the calamity status, and during a warning holding E packs a survival pack for the shelter (see [Calamities](#13-calamities)).
  - At an **ice vein**, holding E drills one load, showing the geometric-series formula with the real numbers. Drilling is blocked if the water would overflow the tank or the melt would flatten the battery, so a single press can never end the run.
- **Updates visuals.** Machines swap between on, off and broken art (or tint when an art is missing). The coal generator's screen glows orange while it burns, and a toast fires when it runs out of coal. Ice veins and coal seams fade as they empty. Solar panels turn brown when dusty.
- **Writes the alert banner.** For each failure, a line saying where to repair it. For each resource whose `time_until_empty` is under `warning_hours` (3 h), a line like "Water too low in 2h 10m: switch the water recycler on", with the hint chosen by whether it is heading too high or too low and by which failure is causing it.
- **Fast-forward.** While F is held, `Base.time_scale = 6`. A new failure cancels fast-forward until F is pressed again, so nothing slips past.
- **Juice.** A red vignette pulses while anything is wrong, and the camera shakes on failures and calamities. Short "toasts" announce failures, repairs, pods and calamities, and a line lists every pod still waiting.
- **The end screen.** On `game_over`, on being caught outside in a calamity, or after the rescue ship flies off, it builds the summary text, computes the score, saves a best score to `user://moonbase_best.cfg`, shows either SURVIVED or the WASTED banner, and pauses. R restarts.

On the end screen M opens the [math debrief](#14-rescue-the-end-screen-and-the-math-debrief) and R restarts.

The score is `10 × hours survived + 40 × repairs + 60 × pods collected + 1000 if rescued`.

### The coal generator

Coal is a second power source for the night. The generator sits in the Ice Tunnels next to three seams of 8 kg each. Switched on at its console, it adds `P_c = 3 kW` to the battery and burns `b = 1 kg/h` from its 12 kg hopper; when the hopper empties, `u_coal` drops to 0 by itself and the generator stops. The HUD's systems panel lists it as "Coal gen", showing +3.0 kW while it burns or the kg left in the hopper while it doesn't, and the net power includes it. Coal and the seams' progress are saved with the run.

## 9. Machine screens: `SystemPanel`

Pressing E at a working console creates a `SystemPanel` (`scripts/system_panel.gd`), a `CanvasLayer` that pauses the game and shows:

- **The equation** for that system with today's numbers substituted, built in `_equation_text()` as BBCode. The coal generator's screen shows `dC/dt = −b·u_coal`, how long the hopper lasts (`C/b`), the power it adds, and the battery equation with the coal term. For example the heater screen shows `dT/dt = [H·u_heat − k·(T − T_out)] / C` and then the same line with `2.5`, `0.012`, the current cabin and outside temperatures and the resulting °C/h.
- **A legend** of every symbol (`_symbol_text()`).
- **An ON/OFF button** (Space or Enter), which calls `Base.toggle_system()`.
- **A what-if table and graph.** `_simulate(on)` temporarily forces the switch on or off, runs `Base.rates_at` forward in 0.1 h steps for up to 96 h, and restores the switch. It returns the primary resource's curve over the next 24 h, the rates right now, and when each resource would hit a limit. The screen runs it twice, once ON and once OFF, and shows both side by side so the player can see the consequence of the switch before making it. The graph (`WhatIfGraph`) draws both curves over the safe-range band, with the current choice thicker.

E or Esc closes the screen and unpauses.

## 10. The HUD

`scripts/hud.gd` builds its whole layout in code (`_build()`): a strip along the bottom with one card per resource and a survival card, plus a systems panel.

Each resource card shows a `RangeBar` from the resource's min to max (with the outer 15% at each end tinted red), the current value, the rate with an arrow, and when it will hit a limit ("min 5h 20m", "max 12h 03m", or "safe"). The survival card shows the in-game hour, a bar towards rescue, `t_survive`, and a verdict such as "4h 10m to spare · water min first".

Colours come from `_status_color(t, rescue)`: red if the limit comes before rescue, amber if the margin is under 25%, green otherwise.

A small coin counter sits next to the systems panel in the top left (shown only when `Base` has a `coins` value).

The systems panel lists each system with ON, OFF or BROKEN and its power, the net power, whether it is day or night with time to sunset or sunrise and the outside temperature, and the chance of a breakdown in the next hour.

The HUD is deliberately loosely coupled: it only receives numbers through `set_resource` and `set_clock`. If `Base` is missing it runs a `demo` mode with placeholder values, and if no forecast is passed in it falls back to a straight-line estimate `(R − min)/|rate|`.

## 11. Supply pods

`SupplyDrops` (`scripts/supply_drops.gd`) drops a pod every 5 to 9 in-game hours (uniformly random) onto the Landing Pad, within 6 m of the `ShipLandingPoint`, hanging 2.6 to 4.4 m up under a parachute. The player has to jump into it before it drifts away after 8 hours.

`_pick_kind()` chooses the pod type with weighted randomness tilted towards what the base needs: if two or more things are broken it always sends a toolkit; it sends less oxygen when the tanks are nearly full, more water when water is low, and so on.

| Pod | Effect |
|---|---|
| Oxygen | +1 kg O₂ |
| Water | +6 L |
| Food | +1.5 kg |
| Toolkit | repairs every active failure |

`order(kind)` drops a pod of a chosen kind straight away; the trade screen uses it for pods bought with coins.

A pod only opens if the base has room (`has_room()`), so a pod can never push a resource over its max. Pods that don't fit are drawn greyed out with "No room".

Pods live as plain dictionaries in `pods`, independent of whichever location is loaded. `_sync_visuals()` creates a `PodVisual` node only for pods at the location on screen, casting a ray down to find the ground height under each one.

## 12. Trading: coins for food, pods for coins

The Landing Pad has a TRADE terminal (`scripts/trade_terminal.gd`). Like the machine consoles, standing near it and pressing E opens a screen, here a `TradePanel` (`scripts/trade_panel.gd`), which pauses the game.

- **Selling food.** Buttons sell 0.5, 1 or 2 kg from the pantry. Each calls `Base.sell_food(kg)`, which removes the food, adds the coins and raises `food_sold`. The market pays less the more you have sold: the price per kg is `p(s) = P0·qˢ` (20 coins, falling 10% per kg sold), and a sale is paid the area under that curve. The screen shows both formulas with the live numbers, plus a `PriceGraph` of the price curve with the next 1 kg sale shaded. [math.md](math.md#9-the-food-market-exponential-decay-and-an-integral) explains the math.
- **Buying pods.** Buttons order an oxygen (30), water (25), food (25) or toolkit (45) pod. `Base.buy_pod(kind)` takes the coins, then `SupplyDrops.order(kind)` drops that pod on the pad right away, where it still has to be jumped for and still only opens if there's room.

The trade-off: each kilogram sold is 13.3 hours of eating gone, so selling only makes sense with the greenhouse running well and a pod you really need.

Coins, `food_sold` and the HUD's coin counter all live on `Base`, and the save file stores them.

## 13. Calamities

`DangerEvents` (`scripts/danger_events.gd`) schedules big events that force the player underground. Three kinds take turns in a fixed order (black hole → alien UFO → asteroid shower), starting from a random one. Each is a small state machine:

```
calm ──(6 h before arrival)──▶ warning ──(arrival)──▶ active ──(2 h later)──▶ calm
```

- The first one arrives between hour 14 and 20, and each later one 16 to 22 hours after the last one ended. No calamity is scheduled if it would still be going when the rescue ship lands.
- During **warning**, a banner along the top of the screen counts down and the Control Panel shows its danger art. The threat grows in the sky (the black hole swells and spins, the UFO sweeps in, asteroids streak past more and more often and burst into puffs of dust where they hit the ground).
- **Packing the shelter.** During the warning, holding E at the Control Panel packs a survival pack: one hour's worth of air, water and food (`pack_contents()`, `pack_hours = 1`) taken out of the base's stores, refused if that would push a store to its minimum. The astronaut carries packs (`carried`) down to the Ice Tunnels, where they are stocked in the `shelter`. The banner shows the hours stocked plus carried against the 2 hours the calamity lasts.
- For the last hour of the warning and the whole **active** phase, `Base.frozen` is true: the base's resources stop changing, the player moves at quarter speed, and the machines ice over blue. Their consoles read FROZEN and refuse switching or repairs until the calamity passes. A banner countdown and a toast warn an hour before this shutdown.
- On **arrival**, the calamity triggers its list of failures (for example the UFO breaks the generator, heater and pipes).
- While it is **active**, the astronaut lives off the shelter: `_use_shelter(dt)` subtracts the normal breathing, drinking and eating rates from the stocked supplies. If any of them runs out before the calamity passes, the run ends.
- If the player is anywhere other than the Ice Tunnels while it is active, `caught` is emitted and the run ends.

## 14. Rescue, the end screen and the math debrief

When `Base.hour` reaches `rescue_hours` (72) with everything in range, `Base` emits `game_won` and stops. The rescue rocket (`scripts/rescue_rocket.gd`, on the Landing Pad) has been descending for the last 1.5 hours. Once landed it waits, and `SystemsController` shows "walk up to it and press E to board". Boarding hides the player, lights the engine and launches the rocket; after 3.2 seconds it calls `rocket_departed()` on the controller, which shows the SURVIVED screen with the leftover resources and the score.

From either end screen (SURVIVED or WASTED), M opens the **math debrief** (`scripts/math_debrief.gd`). It reads `Base.history` (one sample per in-game hour, plus the final moment) and draws one card per resource: a line graph of the whole run over its shaded safe range, the rate equation that drove it, its start, end, lowest and highest values, and the average rate `ΔR/Δt` over the run. A summary card gives hours survived, repairs and pods, and the breakdown math (`λ`, the expected number of breakdowns `λ·t`, and `P(≥1 in 24 h) = 1 − e^(−λ·24)`). M again closes it; R restarts.

## 15. Sound effects

`Sfx` (`scripts/sfx.gd`) is an autoload that makes every sound from code, with no audio files. At startup it builds each sound sample by sample into an `AudioStreamWAV`: tones whose pitch slides between two frequencies under an attack-then-exponential-decay envelope, bursts of filtered noise for thumps and rumbles, and a looping machine hum. It plays them through a pool of 8 `AudioStreamPlayer` voices.

It hooks itself up so that no other script has to call it: it listens to `Base`'s signals (switches, failures, repairs, supplies, coins, game over, win) and to nodes as they enter the tree (the player for footsteps and landings, calamities and pods). Any script can still call `Sfx.play("coin")`. N mutes and unmutes.

## 16. Title screen, tutorial, menus and saving

- **`StartScreen`** pauses the game behind a title card until Enter, Space or a click. A static `started` flag stops it reappearing after a restart. L opens the load page, and T starts the tutorial.
- **`Tutorial`** (`scripts/tutorial.gd`) is a guided first run in the real Moonbase. T on the title screen sets `Tutorial.active`, resets `Base` and reloads the scene, and `main.gd` adds a `Tutorial` node on top. It sets `Base.running = false`, so the clock is stopped: nothing breaks, no pods fall and no calamity comes. A card in the top right gives one task at a time from its `STEPS` list and moves on as soon as the task is done. It checks progress in `_process` (distance walked, a jump that lands, passing the Heater room door), listens to signals (a `SystemPanel` entering the tree, `Base.system_toggled`, `Base.failure_repaired`), or waits for Enter on reading steps. The 12 steps cover moving, jumping (with the `h = v₀²/2g` and `t = 2v₀/g` numbers), doors, opening the heater's machine screen and flipping its `uᵢ`, the HUD bars, the systems panel and survival clock, fast-forwarding (the one step that lets the clock run, for 1.5 in-game hours), a repair (it breaks the heater on purpose with `Base.trigger_failure`), and short notes on trading, mining and calamities. While a machine screen is open the card collapses to a one-line banner, and on the HUD steps a blinking frame marks the part being described. Q leaves at any time; finishing or leaving resets `Base` and goes back to the title screen.
- **`GameMenu`** opens on Esc or P (only if nothing else has paused the game) with Resume, Save, Load, Restart and Quit. Save and Load each show three slots.
- **`SaveGame`** writes a `ConfigFile` to `user://save_<n>.cfg` holding everything that changes during a run: the model's clock, resources, switches, failures, ice veins, coins, food sold and history; the calamity phase, kind and schedule; the pods; the repair count; whether the ship is waiting; and the player's location and position. Loading stores the file in `SaveGame.pending`, resets `Base`, reloads the scene, and `GameMenu._ready()` applies the pending save once the fresh scene exists. This means a load always starts from a clean scene, exactly like a restart.

## 17. The balance test

`tests/balance_sim.gd` is a `SceneTree` script that runs without graphics:

```bash
godot --headless --script res://tests/balance_sim.gd
```

It creates a `Base` with a fixed seed and plays the full 72 hours in steps of 0.01 h with several scripted strategies: do nothing, everything on, everything off, and a "careful" policy (thermostat-style rules for the heater, oxygen generator, solar disconnect and greenhouse), the last with and without failures and with fast or slow repairs. For each it prints whether it won or lost and the lowest and highest value each resource reached. This is how the constants in `BaseConfig` were tuned so that doing nothing loses, careless play loses, and careful play wins.

## 18. One frame, start to finish

1. `Base._process` turns the frame's `delta` into in-game hours, takes an Euler step, rolls for failures, checks for the end, and pushes values, rates and forecasts to the HUD.
2. `Player._physics_process` applies moon gravity and input and moves the astronaut.
3. `Main._physics_process` checks whether the player walked through an exit and swaps locations if so.
4. `SystemsController._process` finds what the player is standing at, handles E, updates machine art, alerts, toasts, fast-forward, the vignette and camera shake.
5. `Tutorial._process` (in a tutorial run only) checks whether the current task is done.
6. `SupplyDrops._process` drops, expires and collects pods.
7. `DangerEvents._process` advances the calamity state machine and sets `Base.frozen`.
8. `Hud._process` redraws the bars, clocks and systems panel from the numbers it was given.

(Godot runs these in tree order within each of its process and physics passes, so the exact order between scripts can differ slightly, but none of them depend on running before another in the same frame.)

## 19. How to change things

- **Change the market:** `food_price_start`, `food_price_ratio` and `pod_prices` in the Trading group of `BaseConfig`.
- **Add a sound:** build it in `Sfx._build_sounds()` with `_tone` or `_noise`, then `Sfx.play("name")` or connect it to a signal in `Sfx._ready()`.
- **Rebalance the game:** edit `data/base_config.tres` in the inspector (or the defaults in `scripts/base_config.gd`), then run the balance test.
- **Add a resource:** add it to `Base.RESOURCES`, give it a variable, `_min`/`_max` and a start value in `BaseConfig`, a rate in `rates_at`, and a row in the HUD's `CONFIG`.
- **Change coal:** the Coal group of `BaseConfig` (`coal_generator_power`, `coal_burn_rate`, `coal_max`, `coal_per_seam`, `coal_per_pass`).
- **Add a switchable machine:** add it to `Base.SYSTEMS` and `switches`, give it a `*_running()` helper and a term in `rates_at` / `power_draw`, then place a `Console` node with a matching `system` meta in a location scene.
- **Add a failure:** add it to `config.failure_rates`, `Base.FAILURE_SITES` and `FAILURE_NAMES`, and make `rates_at` check `failures.has("<id>")`.
- **Add a location:** make a scene whose root uses `location.gd`, set its exits, and point a neighbour's exit at it.

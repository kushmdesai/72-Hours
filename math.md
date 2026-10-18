# The math behind Moonbase: 72 Hours

The whole game is a **mathematical model** of a damaged lunar base that the player steers in real time. This document explains each piece of that math twice: first **the idea**, in plain words and pictures you can hold in your head, then **the details**, with the equations, the real numbers the game uses, and where each piece lives in the code. It also explains how the project follows the mathematical modelling process. For how the code is organised, see [explanation.md](explanation.md).

All constants quoted here are the defaults in `scripts/base_config.gd` (loaded through `data/base_config.tres`). Time `t` is always in in-game **hours**.

## Contents

0. [The whole game in one picture](#0-the-whole-game-in-one-picture)
1. [What "mathematical modelling" means here](#1-what-mathematical-modelling-means-here)
2. [The state and the system of equations](#2-the-state-and-the-system-of-equations)
3. [Each equation in detail](#3-each-equation-in-detail)
4. [Solving it: Euler's method](#4-solving-it-eulers-method)
5. [Forecasting: time until a limit, and the survival clock](#5-forecasting-time-until-a-limit-and-the-survival-clock)
6. [What-if analysis on the machine screens](#6-what-if-analysis-on-the-machine-screens)
7. [Random failures: the Poisson process](#7-random-failures-the-poisson-process)
8. [Ice and coal mining: geometric and arithmetic sequences](#8-ice-and-coal-mining-geometric-and-arithmetic-sequences)
9. [The food market: exponential decay and an integral](#9-the-food-market-exponential-decay-and-an-integral)
10. [Lunar gravity and the jump](#10-lunar-gravity-and-the-jump)
11. [Other bits of math in the game](#11-other-bits-of-math-in-the-game)
12. [The math debrief: looking back at the run](#12-the-math-debrief-looking-back-at-the-run)
13. [Validating the model: the balance simulation](#13-validating-the-model-the-balance-simulation)
14. [Assumptions and limitations](#14-assumptions-and-limitations)
15. [Symbol reference](#15-symbol-reference)

---

## 0. The whole game in one picture

Picture the base as **five water tanks** standing side by side: one each for oxygen, battery charge, water, warmth and food. Every tank has **taps** pouring in and **drains** letting out:

```
            taps (sources)                       drains (uses)
   oxygen   generator, plants          ──▶ [ O ] ──▶ breathing, leaks
   battery  solar panels, coal         ──▶ [ E ] ──▶ every machine that is on
   water    recycler (saves some)      ──▶ [ W ] ──▶ drinking, oxygen-making, plants, leaks
   warmth   heater                     ──▶ [ T ] ──▶ heat escaping into the lunar night
   food     greenhouse                 ──▶ [ F ] ──▶ eating
```

Each tank has a **safe band** marked on its side. Let a tank run too low (no air, flat battery, freezing) **or** too high (oxygen-rich air that can catch fire, an overcharged battery, an overheating cabin) and the run is over.

The player's switches open and close taps. The catch is that **the taps are connected**: the oxygen generator's tap fills the oxygen tank but secretly drains the water and battery tanks; the heater fills the warmth tank but is the biggest drain on the battery; the greenhouse fills the food tank, but only well when the warmth tank is near the middle. Turning one knob always moves more than one level.

Everything else in this document is that picture made precise:

- **How fast** each level moves is a *rate*, written `dR/dt` (section 2 and 3).
- **Moving the levels forward in time** is done by adding up "rate × a short time" over and over (Euler's method, section 4).
- **"How long until a tank hits its line?"** is the survival clock (section 5).
- **Things break at random**, like raindrops landing at unpredictable moments, but with a predictable average (Poisson process, section 7).

## 1. What "mathematical modelling" means here

> **The idea:** a mathematical model is a deliberately simplified copy of a real situation, written in maths, that you can run forwards to ask "what happens if…?". The game is one such copy, and the player uses it the way an engineer would.

Mathematical modelling is the process of turning a real situation into mathematics, solving the mathematics, and checking whether the answer makes sense back in the real situation. It is usually drawn as a cycle:

```
  real problem ──▶ assumptions ──▶ mathematical model ──▶ solve
       ▲                                                    │
       └──── refine ◀──── validate / interpret ◀────────────┘
```

The game walks through every stage of that cycle:

| Stage | In the game |
|---|---|
| **Real problem** | A crew member must keep a damaged lunar habitat alive for 72 hours until rescue. |
| **Assumptions** | The base is described by five numbers (oxygen, energy, water, temperature, food). Each machine is either fully on or off. Rates depend only on the current state, the time of day, and which machines and failures are active. See [section 14](#14-assumptions-and-limitations). |
| **Model** | A system of five coupled **ordinary differential equations** (rates of change), plus a **Poisson process** for breakdowns. |
| **Solve** | **Euler's method**, a numerical integration, every frame. The same solver runs ahead in time to **forecast** when each resource will fail. |
| **Learn the model** | The tutorial walks a new player through every piece by doing it: the jump formulas, a machine screen's equation and its what-if graph, flipping a `uᵢ` from 0 to 1, reading rates and time-to-limit off the HUD, the falling food price `p(s) = P₀qˢ` and the area a sale pays, the coal generator's `C/b` hours, the ice vein's geometric series, and a calamity drill where supplies are budgeted in hours. |
| **Interpret** | The HUD turns the numbers into "Water reaches its minimum in 5h 20m", and the machine screens compare what happens if a machine is on or off. |
| **Look back** | The math debrief at the end graphs every resource over the run against its equation. |
| **Validate and refine** | A headless simulation (`tests/balance_sim.gd`) plays the model with fixed strategies, and the constants were tuned until the results matched how the game should feel. |

The player is not just watching the model; they are part of it. Every switch they flip changes a coefficient in the equations, so playing well means **reasoning about the model**: which resource is the limiting one, what the knock-on effects of a switch are, and whether the margin is big enough to survive a breakdown.

## 2. The state and the system of equations

> **The idea:** at any instant, five numbers tell you everything about the base: how full each tank is. That list of five numbers is the **state**. For each one there is a rule, "this is how fast it is changing right now", which is just *taps minus drains*. The five rules together are the **system of equations**.

At any moment the base is described by a **state vector**

```
x(t) = (O, E, W, T, F)
```

| Symbol | Resource | Unit | Start | Safe range |
|---|---|---|---|---|
| O | oxygen in the air | kg | 2.0 | 0.5 < O < 4.0 (too little: suffocation; too much: fire risk) |
| E | battery energy | kWh | 30 | 0 < E < 100 (flat battery, or overcharge) |
| W | water in the tank | L | 30 | 0 < W < 40 |
| T | cabin temperature | °C | 21 | 5 < T < 35 |
| F | food | kg | 2.5 | F > 0 (the 6 kg max is only the pantry size: extra food spoils) |

Each resource changes according to a rate equation `dR/dt` ("the change in R per hour"). Together they form the system implemented in `Base.rates_at()` (`scripts/base.gd`):

```
dO/dt = g·u_gen + p·G − c_O − L_O
dE/dt = η·A·S(t)·u_sol + P_c·u_coal − (P_base + u_gen·P_gen + u_rec·P_rec + u_heat·H + u_gh·P_gh)
dW/dt = −(1 − r·u_rec)·c_W − k_e·g·u_gen − w_gh·u_gh − L_W
dT/dt = [H·u_heat − k·(T − T_out(t))] / C
dF/dt = G − c_F
dC/dt = −b·u_coal                                  (coal in the generator's hopper)

where  G = y·u_gh·f(T)   and   f(T) = max(0, 1 − ((T − T_opt)/T_span)²)
```

Read every line the same way: **positive terms are taps, negative terms are drains**. For example the oxygen line says "the generator adds `g`, the plants add `p·G`, you breathe out `c_O`, and a leak (if there is one) loses `L_O`".

The `u` terms are **control variables**: on/off switches, each either 0 or 1. Multiplying a term by `u` is the mathematical way of saying "this tap only runs when the switch is on". A `u` is 1 only when the player has switched that machine on **and** it is not broken (and, for the coal generator, has coal left). These are the only things the player directly controls, and they are what make the game a **control problem**: choose the `u`'s over time to keep `x(t)` inside its safe box until `t = 72`.

### Why "coupled"?

> **The idea:** the equations share terms, so you can't fix one tank in isolation. Every decision is a trade.

The equations are linked through shared terms:

- The oxygen generator (`u_gen`) makes oxygen **but** splits water and draws 1.2 kW.
- The heater (`u_heat`) keeps you warm **but** draws 2.5 kW, the largest load in the base.
- The greenhouse (`u_gh`) makes food and a little oxygen **but** drinks water and draws power, and how much it grows depends on the **temperature**.
- The recycler (`u_rec`) saves water **but** draws power.
- The coal generator (`u_coal`) adds power **but** only while there is coal, which has to be dug out by hand in the tunnels.

So fixing one resource usually pushes on another. Turning the heater on at night saves the temperature but can run the battery flat; turning the generator off saves water and power but lets oxygen fall. This web of trade-offs is the strategy of the game, and it is exactly what a coupled system means mathematically: you cannot solve one equation without knowing the others.

## 3. Each equation in detail

### 3.1 Oxygen: a balance equation

> **The idea:** a bank account. The generator is your salary, breathing is your rent, a leak is a thief. If salary beats rent you save up (and eventually have *too much*, which is a fire risk); if not, you go broke at a predictable date.

```
dO/dt = g·u_gen + p·G − c_O − L_O
```

This is a **conservation (input − output) model**: the rate of change equals what comes in minus what goes out.

| Term | Value | Meaning |
|---|---|---|
| `g` | 0.09 kg/h | oxygen generator output |
| `p·G` | 0.08 × crop growth | oxygen the plants give off by photosynthesis |
| `c_O` | 0.035 kg/h | what the astronaut breathes (0.84 kg/day, a realistic figure for one adult) |
| `L_O` | 0.08 kg/h | extra loss only while the oxygen-leak failure is active |

**Worked example.** With the generator on and no leak, `dO/dt ≈ 0.09 − 0.035 = +0.055 kg/h`, so oxygen climbs about 1.3 kg per day and will eventually cross the 4 kg fire limit: you cannot just leave it on. With it off, `dO/dt = −0.035 kg/h`, and starting from 2.0 kg it takes

```
t = (2.0 − 0.5) / 0.035 ≈ 42.9 h
```

to reach the 0.5 kg minimum. So the player cycles the generator on and off, like a thermostat clicking a boiler on and off to hold a room between two temperatures. Engineers call this **bang-bang control**: switching between fully on and fully off to keep a value inside a band.

### 3.2 Energy: solar input minus loads

> **The idea:** a phone battery with a solar charger. During the day the charger can outpace everything you run (and you must stop it before the battery overfills); at night the charger gives nothing and every machine eats into the battery. The coal generator is a power bank you have to refill by hand.

```
dE/dt = η·A·S(t)·u_sol − Σ uᵢ·Pᵢ
```

**Solar input.** Panel power is efficiency × area × sunlight: `η = 0.22`, `A = 36 m²`, and the peak sunlight is the solar constant at the Moon, `S_peak = 1.36 kW/m²`. At noon that gives

```
0.22 × 36 × 1.36 ≈ 10.8 kW
```

Dust (a failure) cuts `η` by 60%. Disconnecting the panels at Solar Control sets `u_sol = 0`.

**Sunlight over the day** is modelled as a clipped sine wave:

```
S(t) = S_peak · max(0, sin(2π(t + φ)/P))      P = 24 h,  φ = 3 h
```

Intuitively: a sine wave goes smoothly up, over the top and down, which is exactly how the sun rises, peaks at noon and sets. The bottom half of the wave would be "negative sunlight", which doesn't exist, so `max(0, …)` flattens it to zero: that flat part is night.

```
S(t)
 │    ╭──╮            ╭──╮            ╭──╮
 │   ╱    ╲          ╱    ╲          ╱    ╲
 │  ╱      ╲        ╱      ╲        ╱      ╲
 └─╯────────╰──────╯────────╰──────╯────────╰────── t
   day  night        day  night       day  night
```

With `φ = 3`, the strike happens 3 hours after sunrise, the first sunset is at hour 9, and there are three nights (hours 9–21, 33–45, 57–69) before rescue. (A real lunar day lasts 29.5 Earth days; it is compressed so the game sees several cycles.)

**Seeing `S(t)`.** The same function drives what the player sees (`scripts/day_night.gd`). Each frame the world is tinted by

```
tint = lerp(night_tint, white, S(t)/S_peak)
```

so the brightness of the ground is the normalised sunlight itself: dim blue at night, full colour at noon, and every shade of the half sine in between. The sun crosses the sky on the same angle `θ = 2π(t + φ)/P` used inside the sine. Its horizontal position is proportional to `θ/π`, so it moves left to right at a constant rate from sunrise (`θ = 0`) to sunset (`θ = π`), and its height above the horizon is proportional to `sin θ`, the same quantity that sets the light. So the sun's height **is** a graph of the solar power, drawn in the sky: `x ∝ θ` and `y ∝ sin θ` trace one arch of a sine curve. For `θ > π`, `sin θ < 0`, which is exactly the part the `max(0, …)` cuts off, and the sun is hidden. The sky itself is never tinted, because with no atmosphere to scatter light the Moon's sky is black even at noon.

**A day's worth of sunshine.** The energy collected is the **area under** the sunlight curve, which is what integration measures:

```
∫₀^P S_peak·max(0, sin(2πt/P)) dt = S_peak · P/π
```

so the panels collect about `10.8 × 24/π ≈ 82 kWh` per day, an average of about 3.4 kW. (Intuition check: the panels peak at 10.8 kW but only shine half the day, and a sine hump averages about 64% of its peak, so `10.8 × ½ × 0.64 ≈ 3.4 kW`.)

**Loads.** Life support, lights and computers always draw `P_base = 0.4 kW`. On top of that: generator 1.2 kW, recycler 0.4 kW, heater 2.5 kW, greenhouse 0.3 kW. With everything on the base draws 4.8 kW, or about 115 kWh per day, which is far more than the panels collect. Running everything all the time is not sustainable over a day, even before the heater overheats the cabin (which, as the balance test shows, happens first if you heat by day).

**Coal: a second power source.** The coal generator in the Ice Tunnels adds `P_c = 3 kW` while it burns `b = 1 kg/h`, giving the extra terms

```
dE/dt = … + P_c·u_coal          dC/dt = −b·u_coal
```

Unlike the other switches, `u_coal` depends on the **state**: it is 1 only while the player has it on **and** `C > 0`, like a campfire that goes out by itself when the wood is gone. So with a full 12 kg hopper,

```
C(t) = 12 − t        for 0 ≤ t ≤ 12 h, then C = 0 and u_coal = 0
```

The coal term is a **piecewise** function of time: a constant 3 kW for exactly `C/b = 12 h`, then nothing. Each kilogram is worth `P_c/b = 3 kWh` of electricity. The constants are grounded in physics: coal holds about 8 kWh of heat per kg, and a small generator converts roughly 37% of that, `8 × 0.37 ≈ 3 kWh`. A full hopper (36 kWh) runs for 12 hours, the length of one night, and nearly covers the night-time draw with the heater on (`0.4 + 0.4 + 2.5 = 3.3 kW`). The three seams hold `3 × 8 = 24 kg`, enough for two full hoppers, so coal can carry the base through two of the three nights, if the player puts in the digging trips. The catch is the same two-sided battery limit: burning coal by day on top of the sun overcharges the battery faster.

**Too much is also bad.** At noon with the heater off, `dE/dt ≈ 10.8 − 2.3 = +8.5 kW`. Starting at 30 kWh, the 100 kWh battery limit is reached in a few hours, so the player has to disconnect the panels or turn on loads. The energy equation is a two-sided constraint: there is a floor *and* a ceiling.

### 3.3 Water: recycling as a fraction

> **The idea:** you "spend" half a litre an hour, but the recycler hands 90% of it straight back. So with the recycler on you only really lose the 10% it can't catch, and the tank drains ten times more slowly.

```
dW/dt = −(1 − r·u_rec)·c_W − k_e·g·u_gen − w_gh·u_gh − L_W
```

| Term | Value | Meaning |
|---|---|---|
| `c_W` | 0.5 L/h | water used for drinking, food and hygiene (12 L/day) |
| `r` | 0.9 | the recycler recovers 90% of used water |
| `k_e·g` | 1.125 × 0.09 ≈ 0.10 L/h | water split by the oxygen generator |
| `w_gh` | 0.15 L/h | water the greenhouse plants use |
| `L_W` | 1.5 L/h | extra loss only while a pipe is leaking |

**Recycling.** The term `(1 − r·u_rec)` is the fraction of used water that is actually lost. With the recycler off (`u_rec = 0`) it is `1`, so the loss is the full 0.5 L/h and 30 L lasts 60 h; with it on it is `1 − 0.9 = 0.1`, so the loss is `0.1 × 0.5 = 0.05 L/h`, ten times slower.

**Where oxygen comes from: electrolysis.** The generator makes oxygen by splitting water with electricity:

```
2 H₂O → 2 H₂ + O₂
```

Weighing both sides: 36 g of water gives 32 g of oxygen, so each kilogram of oxygen uses `36/32 = 1.125` kg (≈ litres) of water. That is where `k_e = 1.125` comes from: it is real chemistry, not a made-up number. It is also why making air costs you water.

### 3.4 Temperature: Newton's law of cooling

> **The idea:** a cup of hot coffee on a desk. When it's much hotter than the room it cools quickly; as it gets close to room temperature it cools more and more slowly, and it never quite overshoots. The cabin is the coffee and the lunar night (−173 °C) is a very cold room. The heater is like holding the cup over a candle: it settles at the temperature where the candle's heat exactly matches what leaks away.

```
dT/dt = [H·u_heat − k·(T − T_out(t))] / C
```

This is an **energy balance** on the cabin. Heat in is the heater's power `H = 2.5 kW`. Heat out through the walls follows **Newton's law of cooling**: it is proportional to the temperature difference with the outside, with `k = 0.012 kW/°C`. Dividing by the heat capacity `C = 0.9 kWh/°C` (how much energy it takes to warm the cabin by one degree; a big heavy cabin changes temperature slowly) turns the net power into a rate of temperature change.

The outside temperature follows the sunlight between −173 °C at night and 10 °C at noon (the effective temperature around the shaded, insulated hull):

```
T_out(t) = −173 + (10 − (−173)) · S(t)/S_peak
```

**Exact solution.** When `T_out` and `u_heat` are constant this is a **first-order linear ODE** with a closed-form solution. Write it as `dT/dt = −(T − T_eq)/τ` with

```
τ = C/k = 0.9/0.012 = 75 h                    (time constant)
T_eq = T_out + H·u_heat/k                      (equilibrium temperature)
```

Then

```
T(t) = T_eq + (T₀ − T_eq)·e^(−t/τ)
```

In words: the temperature always heads towards the **balance point** `T_eq` (where heat in = heat out), and the gap shrinks by the same fraction every hour. The **time constant** `τ = 75 h` is how long it takes the gap to shrink to about 37% of what it was; the cabin is heavy and well insulated, so it is slow. Some consequences the player discovers by playing:

- **Night, heater off:** `T_eq = −173 °C`. From 21 °C the cabin falls at about `0.012 × 194 / 0.9 ≈ 2.6 °C/h`, and reaches the 5 °C limit after `τ·ln((21 + 173)/(5 + 173)) ≈ 75 × 0.086 ≈ 6.5 h`. A night lasts 12 h, so you **must** heat at night.
- **Night, heater on:** `T_eq = −173 + 2.5/0.012 ≈ 35.3 °C`, just above the 35 °C limit. Left on all night the heater would very slowly overheat the cabin, so even at night it needs watching.
- **Day, heater on:** `T_eq` is in the hundreds of degrees, so the heater must be off by day.

### 3.5 Food: a temperature-dependent growth curve

> **The idea:** plants are like people: happiest at room temperature, sluggish when it's cold or hot, and they stop entirely at the extremes. The growth curve is a hill with its peak at 23 °C.

```
dF/dt = G − c_F,      G = y·u_gh·f(T),      f(T) = max(0, 1 − ((T − T_opt)/T_span)²)
```

The astronaut eats `c_F = 0.075 kg/h` (1.8 kg/day). The 2.5 kg starting food lasts `2.5/0.075 ≈ 33 h` without the greenhouse, so the greenhouse is required.

The greenhouse grows `y = 0.3 kg/h` at its best, scaled by `f(T)`, an **inverted parabola** centred on `T_opt = 23 °C` that falls to zero `T_span = 20 °C` either side (at 3 °C and 43 °C):

```
 f(T)
 1.0 ┤            ╭───╮
     │        ╭───╯   ╰───╮
 0.5 ┤     ╭──╯           ╰──╮
     │   ╭─╯                 ╰─╮
 0.0 ┼───┴──────────┬──────────┴──── T (°C)
     3              23             43
```

| Cabin T | f(T) | Crop growth G | dF/dt |
|---|---|---|---|
| 23 °C | 1.00 | 0.300 kg/h | +0.225 kg/h |
| 21 °C | 0.99 | 0.297 kg/h | +0.222 kg/h |
| 16 °C | 0.88 | 0.263 kg/h | +0.188 kg/h |
| 12 °C | 0.70 | 0.209 kg/h | +0.134 kg/h |
| 9 °C | 0.51 | 0.153 kg/h | +0.078 kg/h |
| 5 °C | 0.19 | 0.057 kg/h | −0.018 kg/h |

So temperature couples into food: a cold cabin starves you even with the greenhouse on. Plants also return a little oxygen (`p = 0.08` kg per kg grown) and drink `w_gh = 0.15 L/h` of water. Food above 6 kg spoils, so the code clamps `F` at its max rather than ending the game.

## 4. Solving it: Euler's method

> **The idea:** imagine driving with no map, only a speedometer. To guess where you'll be in one second, take where you are and add "speed × one second". Do that again and again, and you trace out the whole journey. Euler's method does exactly this with the five tank levels: "level + rate × a tiny time step", sixty times a second.

These equations don't have a single neat formula for `x(t)`: the sunlight changes all the time, the player flips switches, and failures come and go. So the game solves them **numerically** with **Euler's method**, the simplest way to integrate a differential equation:

```
R(t + Δt) = R(t) + (dR/dt)(t) · Δt
```

In words: look at how fast each resource is changing right now, assume it keeps changing at that rate for a short time `Δt`, and move forward. Repeat.

In code (`Base.step()`):

```gdscript
var rates := rates()
oxygen += rates.oxygen * dt
energy += rates.energy * dt
...
hour += dt
```

**Step size.** `dt` is the real frame time multiplied by `hours_per_second = 0.08`. At 60 frames per second, `Δt ≈ 0.08/60 ≈ 0.0013 h` (about 5 in-game seconds). Even at 6× fast-forward it is only about 0.008 h.

**How accurate is it?** Each step assumes the rate stays the same for the whole step, which is slightly wrong whenever the rate is changing (it's like assuming your speed is constant for the next second). The smaller the step, the smaller that error: Euler's method has a local error proportional to `Δt²` per step and a global error proportional to `Δt` over a fixed time. For the cooling equation one step multiplies `(T − T_eq)` by `1 − Δt/τ` instead of the exact `e^(−Δt/τ)`. Even with the forecast's larger step `Δt = 0.2 h`:

```
1 − 0.2/75 = 0.997333…      e^(−0.2/75) = 0.997337…
```

The difference is about 4 parts in a million per step, so Euler is easily accurate enough because `Δt` is tiny compared with the system's time scales (the 75 h thermal time constant, the 24 h day).

## 5. Forecasting: time until a limit, and the survival clock

> **The idea:** "if nothing changes, how long until something kills me?" For each tank you ask how long until it hits its line, and the answer that matters is the **shortest** one: a chain breaks at its weakest link.

The most important number on the HUD is the **survival time**: how long until the first resource leaves its safe range if nothing changes.

**When rates are constant** the answer is simple algebra: distance to the line divided by speed. A falling resource reaches its minimum after

```
t_R = (R − R_min) / |dR/dt|
```

and a rising one reaches its maximum after `(R_max − R) / (dR/dt)`. The survival time is the smallest of these:

```
t_survive = min(t_O, t_E, t_W, t_T, t_F)
```

The resource that gives the minimum is the **limiting resource**, the one to deal with first.

**But the rates are not constant.** Sunlight rises and falls, and Newton's cooling slows as the temperature approaches `T_out`. A straight-line estimate made at noon would wildly overestimate how long the battery lasts into the night, like assuming the sun will keep shining because it's shining now. So `Base.forecast()` does something better: it **runs the same Euler model forward** from the current state, in steps of 0.2 h for up to 240 h, assuming the switches stay as they are and nothing new breaks, and records when each resource first crosses a limit. It's a weather forecast for the base. The coal in the hopper is burned down inside the forecast too, so if the generator will run dry at 2 a.m., the battery forecast already includes the power stopping then. With constant rates this gives exactly the formula above; with changing rates it gives the right answer.

To make the countdown smooth, when a resource crosses its limit inside a step the code **linearly interpolates** within that step (it draws a straight line between the two steps and finds where it crosses):

```
t_cross = t_before + Δt · (limit − R_before) / (R_after − R_before)
```

The forecast is cached and re-run every 0.5 in-game hours (or immediately when a switch, failure, repair or supply changes the equations); in between, the answer just counts down with the clock.

**Reading the HUD.** Each card is coloured by comparing its time to limit with the hours left until rescue: **red** if the limit comes first, **amber** if the margin is under 25% (`t < 1.25 × hours to rescue`), **green** otherwise. The survival card says how many hours you have to spare, or how many you are short, and which resource runs out first.

## 6. What-if analysis on the machine screens

> **The idea:** before you flip a switch, the machine screen shows you two futures side by side: the next 24 hours with the machine ON and with it OFF. You get to "try" the decision without paying for it.

When the player opens a machine screen, `SystemPanel._simulate()` runs the Euler model forward **twice** from the current state: once with that machine forced ON and once forced OFF, for up to 96 hours in 0.1 h steps. It shows:

- the machine's equation with the current numbers substituted,
- a table of each resource's rate and time-to-limit in both cases,
- a graph of the main resource over the next 24 hours in both cases, over its safe band.

This is **sensitivity analysis**: changing one input (one `u`) while holding everything else fixed, and comparing outcomes. It lets the player test a decision on the model before committing to it in the "real" base, exactly as an engineer would.

## 7. Random failures: the Poisson process

> **The idea:** breakdowns are like raindrops on a window. You can't say *when* the next one lands, but you know roughly how many land per hour. Two consequences: the risk is the same every hour (a machine doesn't "get due" for a breakdown), and over a long stretch it becomes almost certain that *something* breaks.

Equipment breaks at random. Each failure type is modelled as a **Poisson process** with a rate `λ` (lambda, the expected number of failures per hour):

| Failure | λ (per hour) | Effect on the equations |
|---|---|---|
| Dust on the panels | 0.020 | `η` reduced by 60% |
| Oxygen leak | 0.012 | adds `L_O = 0.08 kg/h` |
| Generator jam | 0.012 | forces `u_gen = 0` |
| Water pipe leak | 0.012 | adds `L_W = 1.5 L/h` |
| Heater fault | 0.010 | forces `u_heat = 0` |
| Crop blight | 0.006 | forces `u_gh = 0` |

So dust, at `λ = 0.02`, happens on average once every `1/0.02 = 50` hours of exposure.

**The key formula.** For a Poisson process, the waiting time until the next event is **exponentially distributed**, so the probability that a failure happens within the next `t` hours is

```
P(at least one failure in t) = 1 − e^(−λt)
```

Why that shape? The chance of getting through one hour safely is `e^(−λ)`; getting through `t` hours means surviving each hour in turn, so you multiply: `e^(−λ)·e^(−λ)·… = e^(−λt)`. One minus "nothing happened" is "at least one thing happened".

Each frame, for each failure type not already active, the game draws a uniform random number and triggers that failure if it is below `1 − e^(−λ·Δt)` (`Base._roll_failures()`). Because `Δt` is small this is almost exactly `λ·Δt`, the rate times the time.

**Combining failure types.** Independent Poisson processes add: the chance that **any** failure happens is governed by the sum of the rates. With nothing broken,

```
λ_total = 0.02 + 3 × 0.012 + 0.01 + 0.006 = 0.072 per hour
```

So the HUD's "Breakdown risk" is `1 − e^(−0.072) ≈ 7%` per hour, the chance of at least one breakdown in the next 10 hours is `1 − e^(−0.72) ≈ 51%` (a coin flip), and the mean time between breakdowns is `1/0.072 ≈ 14 h`. Over the 68 hours after the 4-hour grace period you should expect around `0.072 × 68 ≈ 5` breakdowns. Broken systems drop out of `λ_total` (they cannot break again until fixed), which `Base.failure_rate()` accounts for.

**Memorylessness.** The exponential distribution has no memory: a machine that has run for 30 hours is no more or less likely to break in the next hour than a new one. This makes every hour equally risky, which is why the game is about keeping a **safety margin** in the survival clock rather than predicting exactly when things will break.

Calamities ([section 11](#11-other-bits-of-math-in-the-game)) also trigger several failures at once on a schedule, on top of the random ones.

## 8. Ice and coal mining: geometric and arithmetic sequences

> **The idea:** the first spoonful from a jar of honey is a big one; each scrape after that gets less, until it isn't worth scraping. An ice vein works the same way: every pass of the drill brings up **half** of the previous pass. A coal seam is the opposite: every swing of the pick brings up the same amount until it's empty.

Under the Landing Pad are three ice veins. Each pass of the drill brings up less than the one before: pass `n` (counting from 0) yields

```
load_n = a · rⁿ        a = 3 L,  r = 0.5
```

so the loads are 3, 1.5, 0.75, 0.375 L, … This is a **geometric sequence** (each term is the last one times a fixed ratio), and the total water in a vein is the sum of the infinite **geometric series**

```
Σ a·rⁿ = a / (1 − r) = 3 / (1 − 0.5) = 6 L        (for |r| < 1)
```

Why does an infinite number of passes add up to a finite 6 L? Picture walking halfway to a wall, then half the remaining distance, then half again: you take infinitely many steps but never pass the wall. 3 + 1.5 + 0.75 + … creeps up on 6 the same way.

After `n` passes the water still in the vein is the tail of the series, `a·rⁿ / (1 − r)`, which is what the drill prompt shows as "About … L left". The prompt writes out the formula with the real numbers, for example `pass 3 brings 0.75 L (= 3.0 × 0.5^2)`.

In practice a vein is called empty once the next load would be under `0.2 L`, so you get four passes per vein, `3 + 1.5 + 0.75 + 0.375 = 5.625 L`, or about 16.9 L from all three veins. Melting costs `0.5 kWh` per litre (warming ice from about −200 °C and melting it takes about 0.21 kWh/L, and the drill roughly doubles that), so every litre of water is traded against the battery, another coupling. The game refuses to drill a load that would overflow the tank or flatten the battery.

The geometric series models **diminishing returns**: the first effort pays off most, and each repeat pays half as much.

**Coal seams, for contrast,** are **linear**: each pass of the pick digs a constant 2 kg until the seam's 8 kg is gone (4 passes), an **arithmetic** sequence (8, 6, 4, 2, 0 kg left) rather than a geometric one. Both kinds of deposit sit in the same tunnel, so the player sees side by side the difference between a resource that runs out in equal steps and one that tapers off.

## 9. The food market: exponential decay and an integral

> **The idea:** the first time you sell tomatoes at the market, buyers pay well. Flood the market and the price drops, each kilo fetching a bit less than the last. And because the price drops *while* you are selling, a big sale is paid at the falling price all the way through, not at the price you started with.

At the TRADE terminal on the Landing Pad the player can sell greenhouse food for coins and spend the coins on supply pods. The market gets saturated: the more food you have sold this run, the less the next kilogram is worth. After `s` kg have been sold, the price per kg is

```
p(s) = P0 · qˢ        P0 = 20 coins/kg,  q = 0.9
```

This is **exponential decay**, but in the amount sold rather than in time: every kilogram sold multiplies the price by 0.9, a 10% drop. After 5 kg the price is `20 × 0.9⁵ ≈ 11.8` coins/kg; after 10 kg, about 7.0.

**Paying a sale with an integral.** The price changes continuously as you sell, so a sale of `Δ` kg can't simply be paid at the starting price. Instead, think of the sale as many tiny slivers, each paid at the price at that moment, all added up. Adding up infinitely many tiny slivers is exactly what an integral does, and the result is the **area under the price curve** from `s` to `s + Δ`:

```
value = ∫ₛ^(s+Δ) P0·qˣ dx = P0 · (qˢ − q^(s+Δ)) / (−ln q)
```

(using `∫ qˣ dx = qˣ / ln q`). `Base.food_sale_value()` computes exactly this, and the trade screen writes it out with the live numbers and shades the area on its graph.

| Sale | Value | Average price |
|---|---|---|
| first 0.5 kg | 9.7 coins | 19.5 /kg |
| first 1 kg | 19.0 coins | 19.0 /kg |
| first 2 kg | 36.1 coins | 18.0 /kg |
| second 1 kg (from s = 1) | 17.1 coins | 17.1 /kg |

Two things follow from the integral:

- **It doesn't matter how you split a sale.** Selling 1 kg then another 1 kg pays `19.0 + 17.1 = 36.1`, exactly the same as selling 2 kg at once, because areas under a curve add up over adjacent intervals. So there's no trick to beat the market by selling in tiny pieces.
- **There is a ceiling.** As `Δ → ∞` the total converges: `∫₀^∞ P0·qˣ dx = P0 / (−ln q) ≈ 20 / 0.105 ≈ 190 coins`. However much food you sell, the market will never pay more than about 190 coins in a run. This is the continuous cousin of the geometric series in [section 8](#8-ice-and-coal-mining-geometric-and-arithmetic-sequences): infinitely many ever-smaller pieces adding up to a finite total.

**The trade-off.** Pods cost 25 to 45 coins, so roughly 1.5 to 2.5 kg of food buys one. But food is also life: at `c_F = 0.075 kg/h`, each kilogram sold is `1/0.075 ≈ 13.3` hours of eating gone. Selling is only worth it when the greenhouse is producing a surplus and the pod fixes a more urgent problem, which is a small **optimisation** decision layered on top of the model.

## 10. Lunar gravity and the jump

> **The idea:** the Moon pulls on you about one sixth as hard as Earth does, so the same push off the ground carries you about six times higher and keeps you in the air about six times longer.

The astronaut moves under constant gravity `g = 1.62 m/s²`, about one sixth of Earth's `9.81 m/s²`. The code keeps all physics in metres and seconds and converts to pixels at 32 px per metre, so on screen gravity is `1.62 × 32 ≈ 51.8 px/s²`.

A jump starts with an upward speed `v₀ = 3.13 m/s`. Gravity then takes away `g` metres per second of upward speed every second. This is **projectile motion** with constant acceleration:

```
y(t) = v₀·t − ½·g·t²
v(t) = v₀ − g·t
```

The top of the jump is where the upward speed has all been used up, `v = 0`, at `t = v₀/g`. Putting that time back into `y(t)` gives the height, and the fall takes as long as the rise:

```
apex height   h = v₀² / (2g)
air time      t_air = 2·v₀ / g
```

| | Earth (g = 9.81) | Moon (g = 1.62) |
|---|---|---|
| Apex height | 3.13² / 19.62 ≈ **0.50 m** | 3.13² / 3.24 ≈ **3.0 m** |
| Air time | 6.26 / 9.81 ≈ **0.64 s** | 6.26 / 1.62 ≈ **3.9 s** |

(The tutorial's jumping step quotes these same two formulas and numbers while the player tries it.)

Both scale with `1/g`, so the same push gives a jump about `9.81/1.62 ≈ 6` times higher and longer. `Player.jump_apex_m()` and `Player.jump_air_time_s()` compute these predictions.

Each frame the code integrates the motion the same way as the base model, with Euler steps on the velocity: `velocity.y += g · Δt`. Releasing jump early multiplies the upward speed by 0.5, and since height goes as `v²`, that cuts the remaining rise to a quarter, which gives fine control over jump height.

**Why it matters for play.** Supply pods hang 2.6 to 4.4 m up. Standing, the astronaut reaches about 2 m; a full jump adds about 3 m. So every pod needs a jump and the highest need a full one, a direct consequence of `h = v₀²/2g`.

## 11. Other bits of math in the game

**Time scaling.** `hours_per_second = 0.08`, so 72 in-game hours take `72 / 0.08 = 900 s = 15 min`. Holding F multiplies the rate by 6. Converting between real and in-game time is a simple linear scale factor.

**The rescue ship's landing.** For the last `T = 1.5` hours the ship's height above the pad is

```
y = H · (t_left / T)²
```

Squaring makes the height fall fast at first and gently at the end. Differentiating, its speed is proportional to `t_left`, so it slows at a **constant deceleration** and touches down with zero speed exactly at hour 72, like a real powered landing. On take-off it climbs with constant thrust, `y = ½·a·t²` (the jump formula again, pointing up).

**Uniform random timing.** Supply pods arrive every 5 to 9 hours and calamities every 16 to 22 hours (the first between hour 14 and 20), each drawn from a **uniform distribution**: every gap in the range is equally likely, like a spinner with evenly spaced numbers. The mean gap between pods is therefore 7 hours, the middle of the range.

**Weighted random choice.** A pod's contents are a **categorical distribution**: oxygen, water, food and toolkit have weights 1, 1, 0.8 and 0.6, which are adjusted to the base's needs (more water when water is low, less oxygen when the tanks are nearly full, always a toolkit if two things are broken). Think of a raffle where some items have more tickets in the hat: a uniform number in `[0, total weight)` picks the kind.

**Calamity freeze and the shelter.** From one hour before a calamity until it passes, the base's rates are set to zero (`Base.frozen`), so `dR/dt = 0` and the forecasts show infinity. The astronaut instead lives off supplies carried down to the tunnel shelter, like packing a lunchbox for a two-hour trip. One survival pack holds exactly one hour of each consumable at the normal rates (0.035 kg of oxygen, 0.5 L of water, 0.075 kg of food), and the shelter lasts

```
t_shelter = min(O_s / c_O,  W_s / c_W,  F_s / c_F)
```

hours, the same "the scarcest resource decides" minimum as the survival clock in [section 5](#5-forecasting-time-until-a-limit-and-the-survival-clock). A calamity lasts 2 hours, so the player needs at least two packs' worth of every consumable stocked before it arrives. During the calamity the shelter's stores fall linearly (constant rates, so here the straight-line formula is exact), and the run ends if one reaches zero first. Each frame drains `c·Δt` with Δt = min(t, t_end) − max(t_prev, t_arrive), the overlap of the frame with the calamity window, so the drains add up to exactly `c × 2 h` however the frames fall, and two packs are always enough.

**Score.** A linear function: `score = 10·hours + 40·repairs + 60·pods + 1000·rescued`.

**Sound from math.** There are no audio files: `Sfx` (`scripts/sfx.gd`) computes every sound sample by sample at 22,050 samples per second. A sound is just a list of numbers describing how far a speaker cone is pushed out or pulled in at each instant.

- A **tone** is a periodic wave (sine, square, triangle or sawtooth) whose frequency slides linearly between two pitches, `f(t) = f₀ + (f₁ − f₀)·t/T`, a *chirp* (the "pew" of a sci-fi blaster is a falling chirp). The code accumulates the phase (`phase += f/RATE`) rather than computing `sin(2π·f(t)·t)` directly, because the phase is the integral of the frequency and this keeps the sweep smooth.
- Its loudness follows an **envelope**: a linear rise over the attack time, then exponential decay `e^(−t/τ)`, the same shape as the cabin cooling in [section 3.4](#34-temperature-newtons-law-of-cooling). It's why a sound "pings" and fades rather than starting and stopping abruptly.
- Thumps and rumbles are random noise passed through a one-pole **low-pass filter**, `yₙ = s·yₙ₋₁ + (1 − s)·xₙ`, an exponential moving average: each new sample is mostly the previous one with a little of the new noise mixed in, which smooths away the hiss. The closer `s` is to 1, the darker the sound.
- The **volume** setting is converted to decibels, `dB = 20·log₁₀(v)`, because loudness is perceived logarithmically: halving the slider is about −6 dB, and a tenth is −20 dB.
- The background machine hum mixes 60 Hz and 90 Hz sine waves. Both fit a whole number of cycles in exactly one second, so the one-second sample loops forever without a click.

## 12. The math debrief: looking back at the run

> **The idea:** during play you see speedometers (rates right now); at the end you see the whole road trip on a map (the curves over the full 72 hours).

When a run ends, M opens a debrief built from `Base.history`, which records every resource once per in-game hour. For each resource it shows:

- a **graph of the run**: the solution `R(t)` that Euler's method produced, plotted over the shaded safe range, so you can see exactly where the nights pulled the battery down or where the temperature started its exponential slide;
- the **rate equation** that produced it;
- the start, end, lowest and highest values;
- the **average rate of change** over the run, `ΔR/Δt = (R_end − R_start) / (t_end − t_start)`, the slope of the straight line (secant) from the first point to the last, in contrast with the instantaneous rate `dR/dt` the HUD showed during play. It's the difference between your average speed over a whole trip and the number on the speedometer at one moment.

A summary card applies the Poisson model to a whole game: with `λ = 0.072` per hour, the expected number of breakdowns in 72 h is `λ·t ≈ 5.2`, and the chance of at least one in any 24-hour stretch is `1 − e^(−0.072 × 24) ≈ 82%`.

This is the **interpret** stage of the modelling cycle after the fact: the player sees the curves their decisions produced and can connect each bend in a graph to a term in its equation.

## 13. Validating the model: the balance simulation

> **The idea:** before trusting a model, test it on cases where you already know the right answer. A lazy player *should* lose, a careful one *should* win. If the model disagrees, the model is wrong.

A model is only useful if it behaves sensibly, so the project checks it with `tests/balance_sim.gd`, which plays the full 72 hours without graphics using `Δt = 0.01 h` and fixed strategies:

| Strategy | What it does | Result (current constants) |
|---|---|---|
| do nothing | leave the starting switches alone | loses: the cabin freezes at hour 12.7, in the first night |
| all on | turn the heater on as well | loses: the cabin overheats past 35 °C at hour 6.1 (heating by day) |
| all off | every machine off | loses: freezes at hour 12.7 |
| careful | thermostat rules: heater between 18 and 24 °C, generator between 1 and 3 kg of oxygen and mostly by day, panels disconnected above 55 kWh, recycler unless the battery is low, greenhouse by day | wins |
| careful + failures | as above with random breakdowns (2 to 8 per run), each repaired after 1 h, seeds 1 to 5 | wins all 5 |
| careful + slow repair | repairs only after 6 h, seeds 1 to 5 | wins 3, loses 2 (battery runs flat at hours 39.4 and 66.2) |

The scripted strategies never mine ice or coal, collect pods or trade, so they show what the core equations allow on their own; the extra sources give a human player more slack than this. For each run it prints the outcome and the lowest and highest value each resource reached. This is the **validation** step of the modelling cycle: the constants in `BaseConfig` (panel area, heater power, leak rates, failure rates and so on) were tuned until careless strategies lose, careful ones win, and slow responses to failures are punished. The "careful" strategy is itself a small **feedback controller** built from hysteresis bands (switch on below one threshold, off above another), which is the same idea a real thermostat uses so that it doesn't click on and off every second.

## 14. Assumptions and limitations

> **The idea:** a map is useful precisely because it leaves things out. Every model simplifies; the skill is knowing what you left out and whether it matters.

The main simplifications here, and why they are acceptable for the game:

- **Lumped model.** The whole cabin has one temperature and one oxygen level; there are no rooms or air flow. Fine when we only care about the base as a whole.
- **On/off machines.** Each `u` is 0 or 1, with fixed power and output. Real machines have partial settings, start-up costs and wear.
- **Ideal battery.** No charging losses or capacity fade; energy in equals energy stored.
- **Compressed day.** A real lunar day is 29.5 Earth days; the game uses 24 h so the player sees three nights.
- **Simple sunlight.** A clipped sine wave, ignoring the panels' angle, latitude and shadows.
- **Constant consumption.** The astronaut breathes, drinks and eats at fixed rates regardless of activity.
- **Independent failures.** Failure rates don't depend on how hard a machine is used or how long since its last repair (the memoryless property).
- **Numerical, not exact.** Euler's method has a small error, but with steps this small it is far below anything visible.

A natural next step in the modelling cycle would be to **refine** any of these, for example making failure rates rise with use, or giving the battery a charging efficiency below 100%.

## 15. Symbol reference

| Symbol | Meaning | Value |
|---|---|---|
| `O, E, W, T, F` | oxygen, energy, water, temperature, food | state |
| `u_gen, u_rec, u_heat, u_gh, u_sol, u_coal` | generator, recycler, heater, greenhouse, solar, coal switches (0 or 1) | control |
| `g` | oxygen generator output | 0.09 kg/h |
| `c_O` | oxygen breathed | 0.035 kg/h |
| `L_O` | oxygen leak | 0.08 kg/h |
| `η` | panel efficiency | 0.22 |
| `A` | panel area | 36 m² |
| `S_peak` | peak sunlight | 1.36 kW/m² |
| `P`, `φ` | day length, starting phase | 24 h, 3 h |
| `P_base, P_gen, P_rec, H, P_gh` | power of base, generator, recycler, heater, greenhouse | 0.4, 1.2, 0.4, 2.5, 0.3 kW |
| `c_W` | water use | 0.5 L/h |
| `r` | recycling efficiency | 0.9 |
| `k_e` | water per kg of oxygen | 1.125 L/kg |
| `w_gh` | greenhouse water | 0.15 L/h |
| `L_W` | water leak | 1.5 L/h |
| `k` | heat loss coefficient | 0.012 kW/°C |
| `C` | heat capacity | 0.9 kWh/°C |
| `T_out` | outside temperature | −173 °C (night) to 10 °C (noon) |
| `τ = C/k` | thermal time constant | 75 h |
| `y` | crop yield | 0.3 kg/h |
| `T_opt, T_span` | best growing temperature, growth width | 23 °C, 20 °C |
| `p` | oxygen per kg of crop | 0.08 |
| `c_F` | food eaten | 0.075 kg/h |
| `a, r` (ice) | first drill load, ratio | 3 L, 0.5 |
| `λ` | failure rates | 0.006 to 0.02 per hour (0.072 in total) |
| `C` (coal) | coal in the hopper | 0 to 12 kg |
| `P_c, b` | coal generator power, burn rate | 3 kW, 1 kg/h |
| `P0, q` | starting food price, price ratio per kg sold | 20 coins/kg, 0.9 |
| `s` | food sold so far | kg |
| `g_moon` | lunar gravity | 1.62 m/s² |
| `v₀` | jump take-off speed | 3.13 m/s |

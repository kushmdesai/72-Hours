# The math behind Moonbase: 72 Hours

The whole game is a **mathematical model** of a damaged lunar base that the player steers in real time. This document explains each piece of the math, shows where it lives in the code, works through the real numbers the game uses, and explains how the project follows the mathematical modelling process. For how the code is organised, see [explanation.md](explanation.md).

All constants quoted here are the defaults in `scripts/base_config.gd` (loaded through `data/base_config.tres`). Time `t` is always in in-game **hours**.

## Contents

1. [What "mathematical modelling" means here](#1-what-mathematical-modelling-means-here)
2. [The state and the system of equations](#2-the-state-and-the-system-of-equations)
3. [Each equation in detail](#3-each-equation-in-detail)
4. [Solving it: Euler's method](#4-solving-it-eulers-method)
5. [Forecasting: time until a limit, and the survival clock](#5-forecasting-time-until-a-limit-and-the-survival-clock)
6. [What-if analysis on the machine screens](#6-what-if-analysis-on-the-machine-screens)
7. [Random failures: the Poisson process](#7-random-failures-the-poisson-process)
8. [Ice mining: a geometric series](#8-ice-mining-a-geometric-series)
9. [The food market: exponential decay and an integral](#9-the-food-market-exponential-decay-and-an-integral)
10. [Lunar gravity and the jump](#10-lunar-gravity-and-the-jump)
11. [Other bits of math in the game](#11-other-bits-of-math-in-the-game)
12. [The math debrief: looking back at the run](#12-the-math-debrief-looking-back-at-the-run)
13. [Validating the model: the balance simulation](#13-validating-the-model-the-balance-simulation)
14. [Assumptions and limitations](#14-assumptions-and-limitations)
15. [Symbol reference](#15-symbol-reference)

---

## 1. What "mathematical modelling" means here

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
| **Interpret** | The HUD turns the numbers into "Water reaches its minimum in 5h 20m", and the machine screens compare what happens if a machine is on or off. |
| **Look back** | The math debrief at the end graphs every resource over the run against its equation. |
| **Validate and refine** | A headless simulation (`tests/balance_sim.gd`) plays the model with fixed strategies, and the constants were tuned until the results matched how the game should feel. |

The player is not just watching the model; they are part of it. Every switch they flip changes a coefficient in the equations, so playing well means **reasoning about the model**: which resource is the limiting one, what the knock-on effects of a switch are, and whether the margin is big enough to survive a breakdown.

## 2. The state and the system of equations

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

Each resource changes according to a rate equation `dR/dt`. Together they form the system implemented in `Base.rates_at()` (`scripts/base.gd`):

```
dO/dt = g·u_gen + p·G − c_O − L_O
dE/dt = η·A·S(t)·u_sol − (P_base + u_gen·P_gen + u_rec·P_rec + u_heat·H + u_gh·P_gh)
dW/dt = −(1 − r·u_rec)·c_W − k_e·g·u_gen − w_gh·u_gh − L_W
dT/dt = [H·u_heat − k·(T − T_out(t))] / C
dF/dt = G − c_F

where  G = y·u_gh·f(T)   and   f(T) = max(0, 1 − ((T − T_opt)/T_span)²)
```

The `u` terms are **control variables**, each either 0 or 1. A `u` is 1 only when the player has switched that machine on **and** it is not broken. These are the only things the player directly controls, and they are what make the game a **control problem**: choose the `u`'s over time to keep `x(t)` inside its safe box until `t = 72`.

### Why "coupled"?

The equations are linked through shared terms:

- The oxygen generator (`u_gen`) makes oxygen **but** splits water and draws 1.2 kW.
- The heater (`u_heat`) keeps you warm **but** draws 2.5 kW, the largest load in the base.
- The greenhouse (`u_gh`) makes food and a little oxygen **but** drinks water and draws power, and how much it grows depends on the **temperature**.
- The recycler (`u_rec`) saves water **but** draws power.

So fixing one resource usually pushes on another. Turning the heater on at night saves the temperature but can run the battery flat; turning the generator off saves water and power but lets oxygen fall. This web of trade-offs is the strategy of the game, and it is exactly what a coupled system means mathematically: you cannot solve one equation without knowing the others.

## 3. Each equation in detail

### 3.1 Oxygen: a balance equation

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

to reach the 0.5 kg minimum. The player has to cycle the generator, which is a simple example of **bang-bang control** (switching between fully on and fully off to hold a value in a band).

### 3.2 Energy: solar input minus loads

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

The `sin` makes the sun rise, peak at noon and set smoothly; the `max(0, …)` cuts off the negative half, which is night. With `φ = 3`, the strike happens 3 hours after sunrise, the first sunset is at hour 9, and there are three nights (hours 9–21, 33–45, 57–69) before rescue. (A real lunar day lasts 29.5 Earth days; it is compressed so the game sees several cycles.)

Integrating the half sine gives the energy collected over one full day:

```
∫₀^P S_peak·max(0, sin(2πt/P)) dt = S_peak · P/π
```

so the panels collect about `10.8 × 24/π ≈ 82 kWh` per day, an average of about 3.4 kW.

**Loads.** Life support, lights and computers always draw `P_base = 0.4 kW`. On top of that: generator 1.2 kW, recycler 0.4 kW, heater 2.5 kW, greenhouse 0.3 kW. With everything on the base draws 4.8 kW, or about 115 kWh per day, which is far more than the panels collect. Running everything all the time is not sustainable over a day, even before the heater overheats the cabin (which, as the balance test shows, happens first if you heat by day).

**Too much is also bad.** At noon with the heater off, `dE/dt ≈ 10.8 − 2.3 = +8.5 kW`. Starting at 30 kWh, the 100 kWh battery limit is reached in a few hours, so the player has to disconnect the panels or turn on loads. The energy equation is a two-sided constraint.

### 3.3 Water: recycling as a fraction

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

**Recycling.** The term `(1 − r·u_rec)` is the fraction of used water that is actually lost. With the recycler off the loss is the full 0.5 L/h and 30 L lasts 60 h; with it on the loss is `(1 − 0.9) × 0.5 = 0.05 L/h`, ten times slower.

**Electrolysis and the stoichiometry of `k_e`.** The generator makes oxygen by splitting water:

```
2 H₂O → 2 H₂ + O₂
```

36 g of water gives 32 g of oxygen, so each kilogram of oxygen uses `36/32 = 1.125` kg (≈ litres) of water. That is where `k_e = 1.125` comes from: it is real chemistry, not a made-up number.

### 3.4 Temperature: Newton's law of cooling

```
dT/dt = [H·u_heat − k·(T − T_out(t))] / C
```

This is an **energy balance** on the cabin. Heat in is the heater's power `H = 2.5 kW`. Heat out through the walls follows **Newton's law of cooling**: it is proportional to the temperature difference with the outside, with `k = 0.012 kW/°C`. Dividing by the heat capacity `C = 0.9 kWh/°C` turns the net power into a rate of temperature change.

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

The temperature decays exponentially towards `T_eq`. Some consequences the player discovers by playing:

- **Night, heater off:** `T_eq = −173 °C`. From 21 °C the cabin falls at about `0.012 × 194 / 0.9 ≈ 2.6 °C/h`, and reaches the 5 °C limit after `τ·ln((21 + 173)/(5 + 173)) ≈ 75 × 0.086 ≈ 6.5 h`. A night lasts 12 h, so you **must** heat at night.
- **Night, heater on:** `T_eq = −173 + 2.5/0.012 ≈ 35.3 °C`, just above the 35 °C limit. Left on all night the heater would very slowly overheat the cabin, so even at night it needs watching.
- **Day, heater on:** `T_eq` is in the hundreds of degrees, so the heater must be off by day.

### 3.5 Food: a temperature-dependent growth curve

```
dF/dt = G − c_F,      G = y·u_gh·f(T),      f(T) = max(0, 1 − ((T − T_opt)/T_span)²)
```

The astronaut eats `c_F = 0.075 kg/h` (1.8 kg/day). The 2.5 kg starting food lasts `2.5/0.075 ≈ 33 h` without the greenhouse, so the greenhouse is required.

The greenhouse grows `y = 0.18 kg/h` at its best, scaled by `f(T)`, an **inverted parabola** centred on `T_opt = 23 °C` that falls to zero `T_span = 14 °C` either side (at 9 °C and 37 °C):

| Cabin T | f(T) | Crop growth G | dF/dt |
|---|---|---|---|
| 23 °C | 1.00 | 0.180 kg/h | +0.105 kg/h |
| 21 °C | 0.98 | 0.176 kg/h | +0.101 kg/h |
| 16 °C | 0.75 | 0.135 kg/h | +0.060 kg/h |
| 12 °C | 0.38 | 0.069 kg/h | −0.006 kg/h |
| 9 °C | 0 | 0 | −0.075 kg/h |

So temperature couples into food: a cold cabin starves you even with the greenhouse on. Plants also return a little oxygen (`p = 0.08` kg per kg grown) and drink `w_gh = 0.15 L/h` of water. Food above 6 kg spoils, so the code clamps `F` at its max rather than ending the game.

## 4. Solving it: Euler's method

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

**How accurate is it?** Euler's method has a local error proportional to `Δt²` per step and a global error proportional to `Δt` over a fixed time. For the cooling equation one step multiplies `(T − T_eq)` by `1 − Δt/τ` instead of the exact `e^(−Δt/τ)`. Even with the forecast's larger step `Δt = 0.2 h`:

```
1 − 0.2/75 = 0.997333…      e^(−0.2/75) = 0.997337…
```

The difference is about 4 parts in a million per step, so Euler is easily accurate enough because `Δt` is tiny compared with the system's time scales (the 75 h thermal time constant, the 24 h day).

## 5. Forecasting: time until a limit, and the survival clock

The most important number on the HUD is the **survival time**: how long until the first resource leaves its safe range if nothing changes.

**When rates are constant** the answer is simple algebra. A falling resource reaches its minimum after

```
t_R = (R − R_min) / |dR/dt|
```

and a rising one reaches its maximum after `(R_max − R) / (dR/dt)`. The survival time is the smallest of these:

```
t_survive = min(t_O, t_E, t_W, t_T, t_F)
```

The resource that gives the minimum is the **limiting resource**, the one to deal with first.

**But the rates are not constant.** Sunlight rises and falls, and Newton's cooling slows as the temperature approaches `T_out`. A straight-line estimate made at noon would wildly overestimate how long the battery lasts into the night. So `Base.forecast()` does something better: it **runs the same Euler model forward** from the current state, in steps of 0.2 h for up to 240 h, assuming the switches stay as they are and nothing new breaks, and records when each resource first crosses a limit. With constant rates this gives exactly the formula above; with changing rates it gives the right answer.

To make the countdown smooth, when a resource crosses its limit inside a step the code **linearly interpolates** within that step:

```
t_cross = t_before + Δt · (limit − R_before) / (R_after − R_before)
```

The forecast is cached and re-run every 0.5 in-game hours (or immediately when a switch, failure, repair or supply changes the equations); in between, the answer just counts down with the clock.

**Reading the HUD.** Each card is coloured by comparing its time to limit with the hours left until rescue: **red** if the limit comes first, **amber** if the margin is under 25% (`t < 1.25 × hours to rescue`), **green** otherwise. The survival card says how many hours you have to spare, or how many you are short, and which resource runs out first.

## 6. What-if analysis on the machine screens

When the player opens a machine screen, `SystemPanel._simulate()` runs the Euler model forward **twice** from the current state: once with that machine forced ON and once forced OFF, for up to 96 hours in 0.1 h steps. It shows:

- the machine's equation with the current numbers substituted,
- a table of each resource's rate and time-to-limit in both cases,
- a graph of the main resource over the next 24 hours in both cases, over its safe band.

This is **sensitivity analysis**: changing one input (one `u`) while holding everything else fixed, and comparing outcomes. It lets the player test a decision on the model before committing to it in the "real" base, exactly as an engineer would.

## 7. Random failures: the Poisson process

Equipment breaks at random. Each failure type is modelled as a **Poisson process** with a rate `λ` (expected failures per hour):

| Failure | λ (per hour) | Effect on the equations |
|---|---|---|
| Dust on the panels | 0.020 | `η` reduced by 60% |
| Oxygen leak | 0.012 | adds `L_O = 0.08 kg/h` |
| Generator jam | 0.012 | forces `u_gen = 0` |
| Water pipe leak | 0.012 | adds `L_W = 1.5 L/h` |
| Heater fault | 0.010 | forces `u_heat = 0` |
| Crop blight | 0.010 | forces `u_gh = 0` |

**The key formula.** For a Poisson process, the waiting time until the next event is **exponentially distributed**, so the probability that a failure happens within the next `t` hours is

```
P(at least one failure in t) = 1 − e^(−λt)
```

Each frame, for each failure type not already active, the game draws a uniform random number and triggers that failure if it is below `1 − e^(−λ·Δt)` (`Base._roll_failures()`). Because `Δt` is small this is almost exactly `λ·Δt`, the rate times the time.

**Combining failure types.** Independent Poisson processes add: the chance that **any** failure happens is governed by the sum of the rates. With nothing broken,

```
λ_total = 0.02 + 3 × 0.012 + 0.01 + 0.01 = 0.076 per hour
```

So the HUD's "Breakdown risk" is `1 − e^(−0.076) ≈ 7%` per hour, the chance of at least one breakdown in the next 10 hours is `1 − e^(−0.76) ≈ 53%`, and the mean time between breakdowns is `1/0.076 ≈ 13 h`. Over the 68 hours after the 4-hour grace period you should expect around `0.076 × 68 ≈ 5` breakdowns. Broken systems drop out of `λ_total` (they cannot break again until fixed), which `Base.failure_rate()` accounts for.

**Memorylessness.** The exponential distribution has no memory: a machine that has run for 30 hours is no more or less likely to break in the next hour than a new one. This makes every hour equally risky, which is why the game is about keeping a **safety margin** in the survival clock rather than predicting exactly when things will break.

Calamities ([section 11](#11-other-bits-of-math-in-the-game)) also trigger several failures at once on a schedule, on top of the random ones.

## 8. Ice mining: a geometric series

Under the Landing Pad are three ice veins. Each pass of the drill brings up less than the one before: pass `n` (counting from 0) yields

```
load_n = a · rⁿ        a = 3 L,  r = 0.5
```

so the loads are 3, 1.5, 0.75, 0.375 L, … This is a **geometric sequence**, and the total water in a vein is the sum of the infinite **geometric series**

```
Σ a·rⁿ = a / (1 − r) = 3 / (1 − 0.5) = 6 L        (for |r| < 1)
```

After `n` passes the water still in the vein is the tail of the series, `a·rⁿ / (1 − r)`, which is what the drill prompt shows as "About … L left". The prompt writes out the formula with the real numbers, for example `pass 3 brings 0.75 L (= 3.0 × 0.5^2)`.

In practice a vein is called empty once the next load would be under `0.2 L`, so you get four passes per vein, `3 + 1.5 + 0.75 + 0.375 = 5.625 L`, or about 16.9 L from all three veins. Melting costs `0.5 kWh` per litre (warming ice from about −200 °C and melting it takes about 0.21 kWh/L, and the drill roughly doubles that), so every litre of water is traded against the battery, another coupling. The game refuses to drill a load that would overflow the tank or flatten the battery.

The geometric series models **diminishing returns**: the first effort pays off most, and each repeat pays half as much. It teaches why a series with `|r| < 1` converges to a finite total even though you could, in principle, keep drilling forever.

## 9. The food market: exponential decay and an integral

At the TRADE terminal on the Landing Pad the player can sell greenhouse food for coins and spend the coins on supply pods. The market gets saturated: the more food you have sold this run, the less the next kilogram is worth. After `s` kg have been sold, the price per kg is

```
p(s) = P0 · qˢ        P0 = 20 coins/kg,  q = 0.9
```

This is **exponential decay**, but in the amount sold rather than in time: every kilogram sold multiplies the price by 0.9, a 10% drop. After 5 kg the price is `20 × 0.9⁵ ≈ 11.8` coins/kg; after 10 kg, about 7.0.

**Paying a sale with an integral.** The price changes continuously as you sell, so a sale of `Δ` kg can't simply be paid at the starting price. Instead it is paid the **area under the price curve** from `s` to `s + Δ`:

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
- **There is a ceiling.** As `Δ → ∞` the total converges: `∫₀^∞ P0·qˣ dx = P0 / (−ln q) ≈ 20 / 0.105 ≈ 190 coins`. However much food you sell, the market will never pay more than about 190 coins in a run, the continuous version of the geometric series in [section 8](#8-ice-mining-a-geometric-series).

**The trade-off.** Pods cost 25 to 45 coins, so roughly 1.5 to 2.5 kg of food buys one. But food is also life: at `c_F = 0.075 kg/h`, each kilogram sold is `1/0.075 ≈ 13.3` hours of eating gone. Selling is only worth it when the greenhouse is producing a surplus and the pod fixes a more urgent problem, which is a small **optimisation** decision layered on top of the model.

## 10. Lunar gravity and the jump

The astronaut moves under constant gravity `g = 1.62 m/s²`, about one sixth of Earth's `9.81 m/s²`. The code keeps all physics in metres and seconds and converts to pixels at 32 px per metre, so on screen gravity is `1.62 × 32 ≈ 51.8 px/s²`.

A jump starts with an upward speed `v₀ = 3.13 m/s`. This is **projectile motion** with constant acceleration:

```
y(t) = v₀·t − ½·g·t²
v(t) = v₀ − g·t
```

The top of the jump is where `v = 0`, at `t = v₀/g`, which gives

```
apex height   h = v₀² / (2g)
air time      t_air = 2·v₀ / g
```

| | Earth (g = 9.81) | Moon (g = 1.62) |
|---|---|---|
| Apex height | 3.13² / 19.62 ≈ **0.50 m** | 3.13² / 3.24 ≈ **3.0 m** |
| Air time | 6.26 / 9.81 ≈ **0.64 s** | 6.26 / 1.62 ≈ **3.9 s** |

Both scale with `1/g`, so the same push gives a jump about `9.81/1.62 ≈ 6` times higher and longer. `Player.jump_apex_m()` and `Player.jump_air_time_s()` compute these predictions.

Each frame the code integrates the motion the same way as the base model, with Euler steps on the velocity: `velocity.y += g · Δt`. Releasing jump early multiplies the upward speed by 0.5, and since height goes as `v²`, that cuts the remaining rise to a quarter, which gives fine control over jump height.

**Why it matters for play.** Supply pods hang 2.6 to 4.4 m up. Standing, the astronaut reaches about 2 m; a full jump adds about 3 m. So every pod needs a jump and the highest need a full one, a direct consequence of `h = v₀²/2g`.

## 11. Other bits of math in the game

**Time scaling.** `hours_per_second = 0.08`, so 72 in-game hours take `72 / 0.08 = 900 s = 15 min`. Holding F multiplies the rate by 6. Converting between real and in-game time is a simple linear scale factor.

**The rescue ship's landing.** For the last `T = 1.5` hours the ship's height above the pad is

```
y = H · (t_left / T)²
```

Differentiating, its speed is proportional to `t_left`, so it slows at a **constant deceleration** and touches down with zero speed exactly at hour 72, like a real powered landing. On take-off it climbs with constant thrust, `y = ½·a·t²`.

**Uniform random timing.** Supply pods arrive every 5 to 9 hours and calamities every 16 to 22 hours (the first between hour 14 and 20), each drawn from a **uniform distribution**. The mean gap between pods is therefore 7 hours.

**Weighted random choice.** A pod's contents are a **categorical distribution**: oxygen, water, food and toolkit have weights 1, 1, 0.8 and 0.6, which are adjusted to the base's needs (more water when water is low, less oxygen when the tanks are nearly full, always a toolkit if two things are broken). A uniform number in `[0, total weight)` picks the kind.

**Calamity freeze and the shelter.** From one hour before a calamity until it passes, the base's rates are set to zero (`Base.frozen`), so `dR/dt = 0` and the forecasts show infinity. The astronaut instead lives off supplies carried down to the tunnel shelter. One survival pack holds exactly one hour of each consumable at the normal rates (0.035 kg of oxygen, 0.5 L of water, 0.075 kg of food), and the shelter lasts

```
t_shelter = min(O_s / c_O,  W_s / c_W,  F_s / c_F)
```

hours, the same "the scarcest resource decides" minimum as the survival clock in [section 5](#5-forecasting-time-until-a-limit-and-the-survival-clock). A calamity lasts 2 hours, so the player needs at least two packs' worth of every consumable stocked before it arrives. During the calamity the shelter's stores fall linearly (constant rates, so here the straight-line formula is exact), and the run ends if one reaches zero first.

**Score.** A linear function: `score = 10·hours + 40·repairs + 60·pods + 1000·rescued`.

**Sound from math.** There are no audio files: `Sfx` (`scripts/sfx.gd`) computes every sound sample by sample at 22,050 samples per second.

- A **tone** is a periodic wave (sine, square, triangle or sawtooth) whose frequency slides linearly between two pitches, `f(t) = f₀ + (f₁ − f₀)·t/T`, a *chirp*. The code accumulates the phase (`phase += f/RATE`) rather than computing `sin(2π·f(t)·t)` directly, because the phase is the integral of the frequency and this keeps the sweep smooth.
- Its loudness follows an **envelope**: a linear rise over the attack time, then exponential decay `e^(−t/τ)`, the same shape as the cabin cooling in [section 3.4](#34-temperature-newtons-law-of-cooling).
- Thumps and rumbles are random noise passed through a one-pole **low-pass filter**, `yₙ = s·yₙ₋₁ + (1 − s)·xₙ`, an exponential moving average: the closer `s` is to 1, the darker the sound.
- The background machine hum mixes 60 Hz and 90 Hz sine waves. Both fit a whole number of cycles in exactly one second, so the one-second sample loops forever without a click.

## 12. The math debrief: looking back at the run

When a run ends, M opens a debrief built from `Base.history`, which records every resource once per in-game hour. For each resource it shows:

- a **graph of the run**: the solution `R(t)` that Euler's method produced, plotted over the shaded safe range, so you can see exactly where the nights pulled the battery down or where the temperature started its exponential slide;
- the **rate equation** that produced it;
- the start, end, lowest and highest values;
- the **average rate of change** over the run, `ΔR/Δt = (R_end − R_start) / (t_end − t_start)`, the slope of the secant line from the first point to the last, in contrast with the instantaneous rate `dR/dt` the HUD showed during play.

A summary card applies the Poisson model to a whole game: with `λ = 0.076` per hour, the expected number of breakdowns in 72 h is `λ·t ≈ 5.5`, and the chance of at least one in any 24-hour stretch is `1 − e^(−0.076 × 24) ≈ 84%`.

This is the **interpret** stage of the modelling cycle after the fact: the player sees the curves their decisions produced and can connect each bend in a graph to a term in its equation.

## 13. Validating the model: the balance simulation

A model is only useful if it behaves sensibly, so the project checks it with `tests/balance_sim.gd`, which plays the full 72 hours without graphics using `Δt = 0.01 h` and fixed strategies:

| Strategy | What it does | Result (current constants) |
|---|---|---|
| do nothing | leave the starting switches alone | loses: the cabin freezes at hour 12.7, in the first night |
| all on | turn the heater on as well | loses: the cabin overheats past 35 °C at hour 6.1 (heating by day) |
| all off | every machine off | loses: freezes at hour 12.7 |
| careful | thermostat rules: heater between 18 and 24 °C, generator between 1 and 3 kg of oxygen and mostly by day, panels disconnected above 55 kWh, recycler unless the battery is low, greenhouse by day | wins |
| careful + failures | as above with random breakdowns (2 to 8 per run), each repaired after 1 h, seeds 1 to 5 | wins all 5 |
| careful + slow repair | repairs only after 6 h, seeds 1 to 5 | wins 3, loses 2 (battery runs flat at hours 38.7 and 65.4) |

For each run it prints the outcome and the lowest and highest value each resource reached. This is the **validation** step of the modelling cycle: the constants in `BaseConfig` (panel area, heater power, leak rates, failure rates and so on) were tuned until careless strategies lose, careful ones win, and slow responses to failures are punished. The "careful" strategy is itself a small **feedback controller** built from hysteresis bands (switch on below one threshold, off above another), which is the same idea a real thermostat uses.

## 14. Assumptions and limitations

Every model simplifies. The main simplifications here, and why they are acceptable for the game:

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
| `u_gen, u_rec, u_heat, u_gh, u_sol` | generator, recycler, heater, greenhouse, solar switches (0 or 1) | control |
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
| `y` | crop yield | 0.18 kg/h |
| `T_opt, T_span` | best growing temperature, growth width | 23 °C, 14 °C |
| `p` | oxygen per kg of crop | 0.08 |
| `c_F` | food eaten | 0.075 kg/h |
| `a, r` (ice) | first drill load, ratio | 3 L, 0.5 |
| `λ` | failure rates | 0.01 to 0.02 per hour |
| `P0, q` | starting food price, price ratio per kg sold | 20 coins/kg, 0.9 |
| `s` | food sold so far | kg |
| `g_moon` | lunar gravity | 1.62 m/s² |
| `v₀` | jump take-off speed | 3.13 m/s |

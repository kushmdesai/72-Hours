# Moonbase: 72 Hours

*A 2D survival game about mathematical modelling, built in Godot (GDScript).*

## Pitch

A meteor strike has crippled your lunar base and the rescue ship is 72 hours away. You are the only astronaut awake. Oxygen, energy, water and temperature are all draining, and equipment keeps breaking. Every repair, reroute and shutdown you choose changes the equations that decide whether you are still alive when help arrives.

## Gameplay

- **Explore the base** as a 2D side scroller with real lunar gravity (1.62 m/s², about 1/6 of Earth), so jumps are long and floaty.
- **Watch four resources** on the HUD: oxygen, energy, water and base temperature, each with its current rate of change and a live "time until empty".
- **Handle failures.** Solar panels get covered in dust, the oxygen generator jams, pipes leak and heaters fail. Walk to the broken module to repair it.
- **Make trade-offs.** Power is limited, so you decide which systems stay on. Running the heater keeps you warm but drains the battery; making oxygen costs both water and energy.
- **Survive 72 in-game hours.** You win if every resource stays above zero until rescue. The game ends the moment any one hits zero.

## The Math Model

The base is modelled as a system of coupled rate equations (differential equations) stepped forward in time each frame with Euler's method: `R(t + Δt) = R(t) + (dR/dt)·Δt`.

| Resource | Rate equation | Meaning |
|---|---|---|
| Oxygen `O` (kg) | `dO/dt = g·u_gen − c_O − L_O` | Generator output `g` (when switched on, `u_gen = 1`) minus astronaut use `c_O` (≈ 0.84 kg/day) minus leaks `L_O` |
| Energy `E` (kWh) | `dE/dt = η·A·S(t) − Σ uᵢ·Pᵢ` | Solar input (efficiency `η`, panel area `A`, sunlight `S(t)`, reduced by dust) minus the power `Pᵢ` of every system that is switched on |
| Water `W` (L) | `dW/dt = −(1 − r)·c_W − k_e·g·u_gen − L_W` | Use `c_W` with recycling efficiency `r`, minus water split for oxygen (electrolysis), minus leaks |
| Temperature `T` (°C) | `dT/dt = [H·u_heat − k·(T − T_out)] / C` | Newton's law of cooling: heater power `H` versus heat lost to the lunar surface (`T_out` ≈ −173 °C at night), with heat capacity `C` |

**Coupling.** The resources depend on each other. Oxygen generation uses water and energy, and the heater uses energy. Fixing one problem can create another, which is where the strategy comes from.

**Equipment failures** happen at random as a Poisson process with rate `λ`. The chance of at least one failure in the next `t` hours is `P = 1 − e^(−λt)`, so failures get more likely the longer you go without maintenance.

**Survival time.** For any resource with a constant net drain, the time left is

```
t_empty = R(t) / |dR/dt|
t_survive = min(t_O, t_E, t_W, t_T)
```

where `t_T` is the time until the temperature reaches the lowest safe limit. The HUD shows `t_survive` live, so the player sees right away how each decision moves their survival clock. The goal is to keep `t_survive ≥` the hours left until rescue.

**Moon physics.** The astronaut moves under `y'' = g_moon = 1.62 m/s²` (scaled at 32 px per metre), so the same push-off gives a jump about 6 times higher and longer than on Earth (9.81 / 1.62 ≈ 6).

## What Players Learn

- How rates of change accumulate into totals over time (integration in practice).
- How coupled systems produce trade-offs, and how to find the limiting resource.
- How probability models failure risk and why prevention beats repair.

## Built With

Godot Engine, GDScript.

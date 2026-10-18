# Moonbase: 72 Hours

*A 2D survival side-scroller about mathematical modelling, built in Godot with GDScript for MathHacks 2.0.*

A meteor strike has crippled your lunar base and the rescue ship is 72 hours away. You are the only astronaut awake. Oxygen, energy, water, temperature and food are all changing every second, and equipment keeps breaking. Every machine you switch on or off, every repair and every supply you collect changes the equations that decide whether you are still alive when help arrives.

## The math modelling idea

The base is a system of five coupled rate equations (ordinary differential equations), solved every frame with Euler's method:

```
R(t + Δt) = R(t) + (dR/dt) · Δt
```

| Resource | Rate equation | What it means |
|---|---|---|
| Oxygen `O` | `dO/dt = g·u_gen − c_O − L_O` | Generator output minus breathing minus leaks |
| Energy `E` | `dE/dt = η·A·S(t) − Σ uᵢ·Pᵢ` | Solar input minus the power of every machine that is on |
| Water `W` | `dW/dt = −(1 − r)·c_W − k_e·g·u_gen − L_W` | Use after recycling, minus water split for oxygen, minus leaks |
| Temperature `T` | `dT/dt = [H·u_heat − k·(T − T_out)] / C` | Newton's law of cooling against the heater |
| Food `F` | temperature-dependent growth curve | Greenhouse output that depends on how warm the base is |

The resources are coupled: making oxygen costs water and energy, and heating costs energy, so fixing one problem can create another. On top of that:

- **Breakdowns** follow a Poisson process, so the chance of a failure in the next `t` hours is `1 − e^(−λt)`.
- **Forecasts** run the same solver ahead in time to show "time until each limit" on the HUD, and each machine screen draws a what-if graph of the machine on versus off.
- **Ice mining** pays out as a geometric series, the **food market** price decays exponentially and a sale pays the area under it, and the astronaut jumps under real lunar gravity (1.62 m/s²).
- **A math debrief** at the end of a run graphs every resource against its equation.

You win if all resources stay inside their safe ranges for the full 72 in-game hours.

## Running the game

1. Install [Godot 4](https://godotengine.org/download) (the project targets 4.7, standard build).
2. Clone the repository:
   ```bash
   git clone https://github.com/kushmdesai/72-Hours.git
   ```
3. Open Godot, choose **Import**, and select `project.godot` in the cloned folder.
4. Press **F5** (or the Play button) to run the main scene.

From a terminal you can also run `godot --path .` in the repository folder. The headless balance test plays the model with fixed strategies:

```bash
godot --headless --script res://tests/balance_sim.gd
```

## Controls

| Key | Action |
|---|---|
| A / D or ← / → | Move |
| W, ↑ or Space | Jump |
| E | Interact (machines, repairs, supply pods, trade terminal) |
| R | Restart |
| F | Fast-forward time |
| T | Start the tutorial (title screen) |
| S | Settings (title screen) |
| M | Math debrief (end screen) |
| N | Mute or unmute sound |
| F11 | Toggle full screen |

## Documentation

- [explanation.md](explanation.md) explains how the code fits together: the model, the scenes, the HUD and every system.
- [math.md](math.md) explains every equation in the game, why it was chosen, and the model's assumptions and limits.

## License

Released under the [MIT License](LICENSE).

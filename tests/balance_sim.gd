extends SceneTree
## Headless balance check: plays the 72 h model with a few fixed strategies.
## Run: godot --headless --script res://tests/balance_sim.gd

const DT := 0.01


func _init() -> void:
	var base: Node = load("res://scripts/base.gd").new()
	base.config = BaseConfig.new()
	base.config.seed = 7
	var no_fail: Dictionary = {}
	print_rich("strategy                 | result")
	for strategy in ["all_on", "all_off", "careful", "careful_failures", "careful_slow_repair"]:
		for seed in ([1, 2, 3, 4, 5] if strategy.ends_with("failures") or strategy.ends_with("repair") else [1]):
			base.config.seed = seed
			var saved: Dictionary = base.config.failure_rates.duplicate()
			if not strategy.contains("fail") and not strategy.contains("repair"):
				base.config.failure_rates = no_fail
			base.reset()
			var result := _play(base, strategy)
			base.config.failure_rates = saved
			print("%-24s seed %d | %s" % [strategy, seed, result])
	base.free()
	quit()


func _play(base: Node, strategy: String) -> String:
	var out := {"text": "", "failures": 0}
	var low := {"oxygen": INF, "energy": INF, "water": INF, "temperature": INF}
	var on_lost := func(r, h): out.text = "LOST %s at %.1fh" % [r, h]
	var on_won := func(): out.text = "WON"
	var on_fail := func(_f): out.failures += 1
	base.game_over.connect(on_lost)
	base.game_won.connect(on_won)
	base.failure_started.connect(on_fail)
	var repair_delay := 1.0 if strategy != "careful_slow_repair" else 6.0
	while not base.ended:
		match strategy:
			"all_off":
				base.set_system("oxygen", false)
				base.set_system("water", false)
				base.set_system("heater", false)
			"all_on":
				pass
			_:
				# Make oxygen only in daylight, heat to hold ~18-24 °C,
				# recycle unless the battery is low.
				base.set_system("oxygen", base.is_day() and base.energy > 10.0 or base.oxygen < 0.6)
				if base.temperature < 18.0:
					base.set_system("heater", true)
				elif base.temperature > 24.0:
					base.set_system("heater", false)
				base.set_system("water", base.energy > 8.0 or base.water < 8.0)
				for f in base.failures.keys():
					if base.hour - base.failures[f] > repair_delay:
						base.repair(f)
		base.step(DT)
		for k in low:
			low[k] = minf(low[k], base.value(k))
	base.game_over.disconnect(on_lost)
	base.game_won.disconnect(on_won)
	base.failure_started.disconnect(on_fail)
	return "%-22s failures %d | lows O %.2f E %.1f W %.1f T %.1f" % [out.text, out.failures, low.oxygen, low.energy, low.water, low.temperature]

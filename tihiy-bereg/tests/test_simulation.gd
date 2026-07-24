extends SceneTree

func _init() -> void:
	var sim := BeachSimulation.new(65, 49)
	var p := Vector3(0.0, sim.sample_height(0.0, 6.0), 6.0)
	var h0 := sim.sample_height(0.0, 6.0)
	for i in range(20):
		sim.apply_brush(0, p, 2.4, 0.8, 1.0 / 30.0)
	var h1 := sim.sample_height(0.0, 6.0)
	if h1 <= h0 + 0.05:
		printerr("add brush failed")
		quit(10)
		return
	for i in range(20):
		sim.apply_brush(1, p, 2.0, 0.8, 1.0 / 30.0)
	var h2 := sim.sample_height(0.0, 6.0)
	if h2 >= h1 - 0.04:
		printerr("dig brush failed")
		quit(11)
		return
	var water_before := sim.total_water()
	sim.apply_brush(4, p, 2.0, 1.0, 0.5)
	for i in range(180):
		sim.step(1.0 / 30.0)
	var water_after := sim.total_water()
	if not is_finite(water_after) or water_after <= 0.0:
		printerr("water solver failed")
		quit(12)
		return
	for v in sim.water:
		if not is_finite(v) or v < -0.000001:
			printerr("invalid water value")
			quit(13)
			return
	var state := sim.serialize_state()
	var sim2 := BeachSimulation.new(65, 49)
	if not sim2.load_state(state):
		printerr("save/load failed")
		quit(14)
		return
	if absf(sim2.sample_height(0.0, 6.0) - sim.sample_height(0.0, 6.0)) > 0.001:
		printerr("state mismatch")
		quit(15)
		return
	print("SIMULATION_TEST_OK water_before=", water_before, " water_after=", water_after)
	quit(0)

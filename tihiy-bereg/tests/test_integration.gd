extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("main scene missing")
		quit(20)
		return
	var game := packed.instantiate()
	get_root().add_child(game)
	await process_frame
	await process_frame
	game._place_tower(Vector3(-3.0, 0.0, 5.0))
	game._place_tower(Vector3(3.0, 0.0, 5.5))
	game._place_wall(Vector3(-3.0, 0.0, 5.0), Vector3(3.0, 0.0, 5.5))
	game._place_driftwood(Vector3(0.0, 0.0, -2.0))
	game._throw_rock(Vector3(1.0, 0.0, 1.0))
	if game.build_records.size() < 3:
		printerr("building system failed")
		quit(21)
		return
	if game.dynamic_objects.size() < 2:
		printerr("object system failed")
		quit(22)
		return
	game.sim.add_wave(0.65)
	for i in range(240):
		game.sim.step(1.0 / 30.0)
		game._update_dynamic_objects(1.0 / 30.0)
		game._update_build_support(1.0 / 30.0)
	for v in game.sim.water:
		if not is_finite(v) or v < -0.000001:
			printerr("integration water invalid")
			quit(23)
			return
	game._save_game(false)
	if not ResourceLoader.exists(game.SAVE_PATH):
		printerr("save file missing")
		quit(24)
		return
	print("INTEGRATION_TEST_OK builds=", game.build_records.size(), " objects=", game.dynamic_objects.size())
	quit(0)

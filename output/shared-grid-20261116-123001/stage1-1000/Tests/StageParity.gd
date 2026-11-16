extends "res://Tests/PerformanceVerification.gd"

func _verify() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	var settings: SimulationConfig = scene.simulation_config.copy_config()
	settings.initial_total = 30
	scene.simulation_config = settings
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.paused = true
	var frames: Array = []
	for index in range(180):
		engine.simulate_step(1.0 / 60.0)
		frames.append(_state())
	var file := FileAccess.open("res://output/stage-parity.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(frames))
	file.close()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	quit()

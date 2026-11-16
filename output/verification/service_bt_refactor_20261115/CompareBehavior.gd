extends SceneTree

var engine: Node

func _initialize() -> void:
	call_deferred("_capture")

func _state() -> Array:
	var values: Array = [engine.rng.state, engine.entity_service.capture_count]
	for animal in engine.entity_service.entities:
		var target_id: int = animal.target.entity_id if animal.is_live(animal.target) else 0
		values.append([animal.entity_id, animal.position, animal.velocity, animal.current_behavior, target_id, animal.alive, animal.facing, animal.last_seen_position, animal.last_seen_velocity, animal.unseen_elapsed])
		if animal is SheepController:
			values.append([animal.has_alert, animal.alert_elapsed, animal.has_panic, animal.panic_elapsed])
		elif animal is WolfController:
			values.append([animal.hunting, animal.hunt_elapsed, animal.charging, animal.strategy, animal.strategy_failures.duplicate(), animal.rest_elapsed, animal.howl_elapsed, animal.howled, animal.retreating])
		elif animal is SheepdogController:
			var anchor_id: int = animal.protected_sheep.entity_id if animal.is_live(animal.protected_sheep) else 0
			var stray_id: int = animal.collected_sheep.entity_id if animal.is_live(animal.collected_sheep) else 0
			values.append([anchor_id, stray_id, animal.protection_center, animal.guard_point, animal.patrol_angle, animal._returning])
	return values

func _capture() -> void:
	var scene := load("res://Levels/Map/SCN_Root.tscn").instantiate() as Node
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.set_physics_process(false)
	engine.reset_simulation()
	engine.paused = true
	var states: Array = []
	for index in range(600):
		engine.simulate_step(1.0 / 60.0)
		states.append(_state())
	var path := "res://output/verification/service_bt_refactor_20261115/baseline.bin"
	if "--compare" in OS.get_cmdline_user_args():
		var file := FileAccess.open(path, FileAccess.READ)
		var expected: Array = file.get_var()
		for index in range(states.size()):
			if states[index] != expected[index]:
				push_error("BASELINE_MISMATCH step=%d" % (index + 1))
				quit(1)
				return
		print("BASELINE_COMPARISON steps=600 identical=true")
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_var(states)
		print("BASELINE_CAPTURE steps=600")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	quit()

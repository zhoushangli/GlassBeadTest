extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	var engine := root.get_node("g_gameplayEngine")
	engine.set_physics_process(false)
	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.set_draft(engine.config)
	var checks: int = 0
	var failures: int = 0
	for field in panel.editors:
		checks += 1
		if not panel.editors[field].tooltip_text.contains("例如："):
			failures += 1
			push_error("Missing Chinese tip: " + field)
	for field in ["Sheep.perception_radius", "Sheep.emergency_distance", "Wolves.dog_threat_distance"]:
		checks += 1
		if not panel.editors[field].tooltip_text.contains("距离"):
			failures += 1
			push_error("Missing distance explanation: " + field)
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	print("CFG_TIPS_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

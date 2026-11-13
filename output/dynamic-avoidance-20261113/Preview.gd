extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	var engine: Node = root.get_node("g_gameplayEngine")
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/dynamic-avoidance-20261113/preview-start.png")
	await create_timer(17.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/dynamic-avoidance-20261113/preview-end.png")
	print("DYNAMIC_AVOIDANCE_PREVIEW seed=%d time=%.1f counts=%s captures=%d" % [engine.config.random_seed, engine.simulation_time, engine.entity_service.get_counts(), engine.entity_service.capture_count])
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	scene = null
	engine = null
	quit()

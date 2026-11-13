extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var engine = root.get_node("g_gameplayEngine")
	print("PROCESSING=", engine.debug_service.is_processing_unhandled_input(), " paused=", engine.paused)
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	print("AFTER_INPUT paused=", engine.paused)
	event.pressed = false
	Input.parse_input_event(event)
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	quit()

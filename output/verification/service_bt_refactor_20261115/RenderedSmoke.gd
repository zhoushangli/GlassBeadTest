extends SceneTree

var engine: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	var scene := load("res://Levels/Map/SCN_Root.tscn").instantiate() as Node
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	await create_timer(0.3).timeout
	_check(engine.step_count > 0 and engine.simulation_time > 0.0, "rendered process advances simulation")
	await _key(KEY_SPACE)
	var before: int = engine.step_count
	await create_timer(0.1).timeout
	_check(engine.paused and engine.step_count == before, "space pauses actual rendered loop")
	await _key(KEY_N)
	_check(engine.step_count == before + 1 and engine.paused, "N advances exactly one step")
	var sheep_count: int = engine.entity_service.sheep.size()
	await _key(KEY_1)
	_check(engine.entity_service.sheep.size() == sheep_count + 1, "spawn input applies while paused")
	engine.debug_service.select_at(engine.entity_service.dogs[0].global_position)
	await _key(KEY_F1)
	_check(engine.debug_service.show_details and is_instance_valid(engine.debug_service.selected), "selection and overlay remain active")
	_check(engine.debug_service.hud.status.text.begins_with("PAUSED"), "HUD refreshes while paused")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/verification/service_bt_refactor_20261115/paused.png")
	await _key(KEY_F2)
	_check(engine.debug_service.hud.parameters.visible, "F2 opens configuration panel")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/verification/service_bt_refactor_20261115/config.png")
	await _key(KEY_ESCAPE)
	_check(not engine.debug_service.hud.parameters.visible, "escape closes configuration panel")
	await _key(KEY_R)
	_check(not engine.paused and engine.entity_service.get_counts() == Vector3i(240, 24, 12), "reset restores default population and resumes")
	print("RENDERED_SMOKE checks=%d failures=%d" % [checks, failures])
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

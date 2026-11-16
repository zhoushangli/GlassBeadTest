extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var capture_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(capture_directory + "/" + name + ".png")
	_check(error == OK, "rendered capture " + name)

func _click(control: Control) -> void:
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await process_frame

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _run() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	capture_directory = "res://output/ecs-visuals/" + Time.get_datetime_string_from_system().replace(":", "-") + "_" + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(capture_directory)
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.paused = true
	await _capture("default")
	engine.config.initial_sheep = 0
	engine.config.initial_wolves = 0
	engine.config.initial_sheepdogs = 0
	engine.reset_simulation()
	engine.paused = true
	var service: EntityService = engine.entity_service
	var sheep := service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 300))[0]
	var wolf := service.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(410, 300))[0]
	var dog := service.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(650, 500))[0]
	data.motion_facing[wolf.row] = Vector2.RIGHT
	data.memory_target[wolf.row] = sheep
	data.memory_target_visible[wolf.row] = false
	data.memory_last_seen_position[wolf.row] = Vector2(570, 350)
	data.memory_unseen_elapsed[wolf.row] = 0.8
	data.motion_movement_goal[wolf.row] = data.memory_last_seen_position[wolf.row]
	data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.SEARCH
	data.motion_facing[dog.row] = Vector2.UP
	data.dog_protected_sheep[dog.row] = sheep
	data.dog_collected_sheep[dog.row] = sheep
	data.dog_protection_center[dog.row] = Vector2(600, 420)
	data.dog_guard_point[dog.row] = Vector2(680, 480)
	data.motion_movement_goal[dog.row] = Vector2(675, 330)
	for animal in service.entities:
		data.brain_view[animal.row].sync()
	var debug: DebugService = engine.debug_service
	debug.selected = wolf
	var panel: DebugPanel = scene.hud.debug_panel
	await _key(KEY_F3)
	_check(panel.visible, "F3 routes through actual input to open DebugPanel")
	await _click(panel.enabled_toggle)
	_check(debug.show_details and debug.selected == wolf, "panel click enables visuals without changing selection")
	_check(scene.hud.get_node("Screen").get_global_rect().encloses(panel.get_global_rect()), "DebugPanel fits the viewport")
	debug.record_howl(wolf)
	debug.advance_visuals(0.3)
	await _capture("selected-wolf")
	await _click(panel.controls["tracking"])
	_check(not debug.visual_options["tracking"] and debug.selected == wolf, "checkbox input updates tracking without click-through")
	await _click(panel.controls["tracking"])
	panel.scope.select(1)
	panel.scope.item_selected.emit(1)
	debug.record_howl(wolf)
	debug.advance_visuals(0.3)
	await _capture("all-animals")
	await _key(KEY_F2)
	_check(scene.hud.parameters.visible and not panel.visible, "F2 input switches to parameters")
	await _key(KEY_ESCAPE)
	_check(not scene.hud.parameters.visible, "Escape input closes parameters")
	await _key(KEY_F3)
	await _key(KEY_ESCAPE)
	_check(not panel.visible and debug.show_details, "closing DebugPanel keeps overlays enabled")
	await _key(KEY_F1)
	_check(not debug.show_details and debug.howl_events.is_empty(), "F1 input disables visuals and clears pulses")
	var retained: int = service.all_entities.size()
	service.capture(sheep)
	engine.request_single_step()
	engine._process(0.0)
	_check(not sheep.enabled and data.brain_view[sheep.row].visible, "single-step disables simulation while showing the corpse")
	for index in range(20):
		engine.simulate_step(1.0 / 60.0)
	_check(not data.brain_view[sheep.row].visible and service.all_entities.size() == retained, "corpse returns to pool without growing retained objects")
	await _capture("recycled")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("DEBUG_VISUAL_VERIFICATION checks=%d failures=%d captures=%s" % [checks, failures, capture_directory])
	quit(0 if failures == 0 else 1)

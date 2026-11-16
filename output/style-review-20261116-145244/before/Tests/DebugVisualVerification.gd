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

func _check_camera_fit(label: String) -> void:
	scene.camera.force_update_scroll()
	var viewport_bounds := root.get_visible_rect().grow(0.1)
	var world_transform: Transform2D = scene.world.get_global_transform_with_canvas()
	var arena: Vector2 = engine.config.arena_size
	_check(viewport_bounds.has_point(world_transform * Vector2.ZERO) and viewport_bounds.has_point(world_transform * arena), label)

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
	_check_camera_fit("startup camera fits the full authored arena")
	var original_window_size := root.size
	root.size = Vector2i(1000, 800)
	await _capture("resized")
	_check_camera_fit("viewport resize retains the complete arena")
	root.size = original_window_size
	await process_frame
	await process_frame
	var settings: SimulationConfig = engine.config.copy_config()
	settings.initial_total = 0
	settings.arena_size = Vector2(1800, 900)
	engine.request_config_apply(settings)
	engine._process(0.0)
	await _capture("applied-arena")
	_check_camera_fit("applying an arena size refits the camera")
	engine.config.initial_total = 0
	engine.config.arena_size = Vector2(1280, 720)
	scene._refresh_world(false)
	engine.reset_simulation()
	engine.paused = true
	var service: EntityService = engine.entity_service
	var sheep := service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 300))[0]
	var wolf := service.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(410, 300))[0]
	var dog := service.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(650, 500))[0]
	var sheep_view := data.brain_view[sheep.row]
	data.sheep_dog_pressure[sheep.row] = Vector2.RIGHT
	data.sheep_panic_strength[sheep.row] = 0.5
	var rng_state: int = engine.rng.state
	sheep_view.sync()
	var expected_color: Color = sheep_view.behavior_colors["Herded"].lerp(sheep_view.behavior_colors["Flee"], 0.5)
	_check(sheep_view.bt_player == null and sheep_view.sprite.self_modulate.is_equal_approx(expected_color), "sheep blends continuous pressure colors without a behavior tree")
	_check(engine.rng.state == rng_state, "continuous sheep presentation does not consume simulation RNG")
	data.sheep_dog_pressure[sheep.row] = Vector2.ZERO
	data.sheep_panic_strength[sheep.row] = 0.0
	data.motion_facing[wolf.row] = Vector2.RIGHT
	data.memory_target[wolf.row] = sheep
	data.memory_target_visible[wolf.row] = int(false)
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
	_check(scene.hud.parameters.editors.has("World.grid_cell_size") and not scene.hud.parameters.editors.has("Sheep.vision_angle"), "parameters expose grid sizing without sheep FOV")
	await _capture("parameters")
	_check(scene.hud.parameters.editors.has("World.sheep_ratio") and scene.hud.parameters.editors.has("World.wolf_ratio") and scene.hud.parameters.editors.has("World.sheepdog_ratio") and not scene.hud.parameters.editors.has("World.initial_sheep"), "parameters expose total and species ratios instead of species counts")
	scene.hud.parameters.editors["World.initial_total"].value = 1000
	_check(scene.hud.parameters.apply_button.text == "Apply & restart" and scene.hud.parameters.message.text.contains("870 sheep, 87 wolves, 43 dogs"), "total input previews the exact allocation without spawning")
	await _capture("population-preview")
	scene.hud.parameters.set_draft(engine.config)
	scene.hud.parameters.tabs.current_tab = 1
	await _capture("sheep-parameters")
	await _key(KEY_ESCAPE)
	_check(not scene.hud.parameters.visible, "Escape input closes parameters")
	await _key(KEY_F3)
	await _key(KEY_ESCAPE)
	_check(not panel.visible and debug.show_details, "closing DebugPanel keeps overlays enabled")
	await _key(KEY_F1)
	_check(not debug.show_details and debug.howl_events.is_empty(), "F1 input disables visuals and clears pulses")
	var retained: int = data.row_to_slot.size()
	service.capture(sheep)
	engine.request_single_step()
	engine._process(0.0)
	_check(not sheep.enabled and data.brain_view[sheep.row].visible, "single-step disables simulation while showing the corpse")
	for index in range(20):
		engine.simulate_step(1.0 / 60.0)
	_check(not data.brain_view[sheep.row].visible and data.row_to_slot.size() == retained, "corpse returns to pool without growing retained objects")
	await _capture("recycled")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("DEBUG_VISUAL_VERIFICATION checks=%d failures=%d captures=%s" % [checks, failures, capture_directory])
	quit(0 if failures == 0 else 1)

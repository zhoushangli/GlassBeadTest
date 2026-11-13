extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _empty() -> void:
	engine.debug_service.clear_selection()
	engine.entity_service.clear()
	engine.simulation_time = 0.0
	engine.step_count = 0
	engine.rng.seed = 1337
	engine.paused = true


func _animal(kind: AnimalController.Kind, point: Vector2) -> AnimalController:
	var animal: AnimalController = engine.entity_service.spawn(kind, 1, point)[0]
	animal.move_speed = 0.0
	animal.urgent_speed = 0.0
	animal.retreat_speed = 0.0
	animal.return_speed = 0.0
	return animal


func _step(count: int) -> void:
	for index in range(count):
		engine.simulate_step(1.0 / 60.0)


func _key(code: Key, shift: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.shift_pressed = shift
	event.echo = echo
	engine.debug_service._unhandled_input(event)


func _run() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_physics_process(false)
	await process_frame
	_check(engine.entity_service.get_counts() == Vector3i(80, 8, 4), "initial populations")
	_check(root.get_node_or_null("g_gameplayEngine2") == null, "single engine")
	var positions: Array[Vector2] = []
	engine.reset_simulation()
	for animal in engine.entity_service.entities:
		positions.append(animal.position)
	engine.reset_simulation()
	for index in range(positions.size()):
		_check(positions[index] == engine.entity_service.entities[index].position, "seed reproduces spawn " + str(index))

	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240))
	var other := _animal(AnimalController.Kind.SHEEP, Vector2(400, 240))
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(1100, 600))
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(640, 360))
	for animal in [sheep, wolf, dog]:
		_check(animal.sprite.texture != null, "prefab has a white texture")
		_check(animal.bt_player.get_bt_instance() != null, "prefab has a behavior tree instance")
		_check(animal.bt_player.update_mode == BTPlayer.MANUAL, "manual BT update")
	_check(sheep.bt_player.blackboard != other.bt_player.blackboard, "independent blackboards")
	var other_color := other.sprite.self_modulate
	sheep.set_behavior(AnimalController.Behavior.FLEE)
	_check(sheep.sprite.self_modulate.is_equal_approx(Color("#facc15")), "sheep flee color")
	_check(other.sprite.self_modulate == other_color, "color modulation is per instance")
	wolf.set_behavior(AnimalController.Behavior.CAPTURE)
	_check(wolf.sprite.self_modulate.is_equal_approx(Color("#f43f5e")), "wolf capture color")
	dog.set_behavior(AnimalController.Behavior.INTERCEPT)
	_check(dog.sprite.self_modulate.is_equal_approx(Color("#22b8f0")), "dog intercept color")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240))
	sheep.satiated_remaining = 0.0
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "sheep graze at grass")
	_step(190)
	_check(sheep.satiated_remaining > 0.0, "grazing satisfies sheep")
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK, "satisfied sheep flock")
	sheep.position = Vector2(640, 360)
	sheep.satiated_remaining = 0.0
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.SEEK_FOOD, "hungry sheep seek grass")
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(720, 360))
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "wolf interrupts foraging")
	wolf.position = Vector2(1150, 600)
	_step(30)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "safety delay keeps fleeing")
	_step(40)
	_check(sheep.current_behavior == AnimalController.Behavior.SEEK_FOOD, "safe sheep resume foraging")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(450, 350))
	other = _animal(AnimalController.Kind.SHEEP, Vector2(500, 350))
	sheep.satiated_remaining = 20.0
	_step(1)
	_check(sheep.neighbor_count == 1 and sheep.local_flock_center == other.position, "full scan finds local flock")
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK, "flocking branch")
	sheep.position = other.position
	sheep.perceive(1.0 / 60.0)
	_check(not sheep.separation.is_zero_approx(), "coincident animals can separate")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240))
	_step(29)
	_check(sheep.alive, "capture cannot finish before half a second")
	_step(1)
	_check(not sheep.alive and engine.entity_service.capture_count == 1, "continuous capture succeeds")
	_check(sheep.sprite.self_modulate.is_equal_approx(Color("#7b8794")), "death feedback")
	_check(engine.entity_service.get_counts().x == 0, "dead sheep excluded immediately")
	_step(19)
	_check(not engine.entity_service.entities.has(sheep), "corpse removed after feedback")
	_check(wolf.current_behavior == AnimalController.Behavior.SEARCH, "wolf searches after prey dies")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240))
	_step(15)
	dog = _animal(AnimalController.Kind.SHEEPDOG, Vector2(410, 240))
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.FLEE, "dog interrupts capture")
	_check(wolf.capture_progress == 0.0, "dog resets capture progress")
	_step(40)
	_check(sheep.alive, "dog saves sheep")
	dog.position = Vector2(1100, 600)
	_step(29)
	_check(sheep.alive, "interrupted capture must restart")
	_step(1)
	_check(not sheep.alive, "capture succeeds after a fresh full interval")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240))
	_step(15)
	sheep.position = Vector2(500, 240)
	_step(1)
	_check(wolf.capture_progress == 0.0 and sheep.alive, "escaping capture radius interrupts")
	sheep.position = Vector2(340, 240)
	_step(29)
	_check(sheep.alive, "escape resets the entire interval")
	_step(1)
	_check(not sheep.alive, "new uninterrupted interval captures")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(345, 240))
	var second_wolf := _animal(AnimalController.Kind.WOLF, Vector2(350, 240))
	_step(30)
	_check(engine.entity_service.capture_count == 1, "two wolves capture a sheep only once")
	_step(25)
	_check(not wolf.is_live(wolf.target) and not second_wolf.is_live(second_wolf.target), "dead references rejected")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(500, 240))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(380, 240))
	second_wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 240))
	_step(2)
	_check(wolf.target == sheep and second_wolf.target == sheep, "wolves share a visible target")
	_check(second_wolf.supporting_hunt, "nearby wolf joins hunt")
	_check(second_wolf.movement_goal != sheep.position, "supporting wolf approaches a flank")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(640, 360))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(860, 360))
	dog = _animal(AnimalController.Kind.SHEEPDOG, Vector2(640, 360))
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.INTERCEPT, "dog intercepts flock threat")
	dog.position = dog.intercept_point
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.DRIVE, "dog drives after intercepting")
	wolf.position = Vector2(1200, 600)
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.RETURN, "dog returns after threat leaves")
	dog.position = dog.guard_point
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.PATROL, "dog resumes patrol")
	dog.position = Vector2(40, 120)
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.RETURN, "dog leash prevents endless pursuit")

	_empty()
	dog = _animal(AnimalController.Kind.SHEEPDOG, Vector2(640, 360))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(1050, 400))
	_step(2)
	_check(dog.flock_center == engine.config.arena_size * 0.5, "empty flock uses arena center")
	_check(dog.current_behavior == AnimalController.Behavior.PATROL, "dog remains active without sheep")
	_check(wolf.current_behavior == AnimalController.Behavior.SEARCH, "wolf remains active without sheep")

	_empty()
	_key(KEY_1)
	_key(KEY_2, true)
	_key(KEY_3)
	engine._physics_process(1.0 / 60.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "debug spawn keys and batch count")
	var before: int = engine.step_count
	engine._physics_process(1.0 / 60.0)
	_check(engine.step_count == before, "pause prevents simulation")
	_key(KEY_N)
	engine._physics_process(1.0 / 60.0)
	_check(engine.step_count == before + 1 and engine.paused, "single step advances exactly once")
	engine._physics_process(1.0 / 60.0)
	_check(engine.step_count == before + 1, "single step is consumed")
	_key(KEY_1, false, true)
	engine._physics_process(1.0 / 60.0)
	_check(engine.entity_service.get_counts().x == 1, "key repeat ignored")
	_key(KEY_F1)
	_check(engine.debug_service.show_details, "debug overlay toggle")
	sheep = engine.entity_service.entities[0]
	engine.debug_service.select_at(sheep.position)
	_check(engine.debug_service.selected == sheep, "selection uses world coordinates")
	engine.entity_service.capture(sheep)
	_check(engine.debug_service.selected == null, "death clears selection")
	_key(KEY_R)
	engine._physics_process(1.0 / 60.0)
	_check(engine.entity_service.get_counts() == Vector3i(80, 8, 4), "reset restores population")
	_check(not engine.paused and engine.entity_service.capture_count == 0, "reset resumes and clears counters")
	_check(engine.entity_service.container.get_child_count() == 92, "reset leaves no old entities")

	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	print("SIMULATION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var authored: Resource

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _empty(frozen: bool = true) -> void:
	engine.config = authored.copy_config()
	engine.config.initial_sheep = 0
	engine.config.initial_wolves = 0
	engine.config.initial_sheepdogs = 0
	engine.config.perception_interval = 0.0
	if frozen:
		engine.config.sheep.move_speed = 0.0
		engine.config.sheep.flee_speed = 0.0
		engine.config.wolf.move_speed = 0.0
		engine.config.wolf.chase_speed = 0.0
		engine.config.wolf.retreat_speed = 0.0
		engine.config.sheepdog.move_speed = 0.0
		engine.config.sheepdog.drive_speed = 0.0
		engine.config.sheepdog.return_speed = 0.0
	engine.reset_simulation()
	engine.paused = true

func _animal(kind: AnimalController.Kind, point: Vector2) -> AnimalController:
	return engine.entity_service.spawn(kind, 1, point)[0]

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

func _verify_resources_and_vision() -> void:
	_empty()
	_check(authored.validate().is_empty(), "authored CFG validates")
	var copy: SimulationConfig = authored.copy_config()
	copy.sheep.move_speed = 19.0
	_check(authored.sheep.move_speed == 70.0, "runtime resources are independent")
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(400, 300))
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(400, 300))
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(400, 300))
	for animal in [sheep, wolf, dog]:
		_check(animal.bt_player.get_bt_instance() != null and animal.bt_player.update_mode == BTPlayer.MANUAL, "manual behavior tree is instantiated")
		animal.facing = Vector2.RIGHT
		var radius: float = animal.perception_radius
		var half: float = deg_to_rad(animal.movement_config.vision_angle * 0.5)
		_check(animal.can_see(animal.position), "coincident target visible")
		_check(animal.can_see(animal.position + Vector2.RIGHT * radius), "range boundary visible")
		_check(not animal.can_see(animal.position + Vector2.RIGHT * (radius + 1.0)), "outside visual range rejected")
		_check(animal.can_see(animal.position + Vector2.from_angle(half) * 50.0), "angle boundary visible")
		_check(not animal.can_see(animal.position + Vector2.from_angle(half + 0.01) * 50.0), "outside visual angle rejected")
		animal.velocity = Vector2.ZERO
		animal.desired_velocity = Vector2.ZERO
		animal.separation = Vector2.ZERO
		animal._speed_limit = 0.0
		animal.move(1.0 / 60.0)
		_check(animal.facing == Vector2.RIGHT, "stationary facing retained")
	wolf.desired_velocity = Vector2.DOWN * 50.0
	wolf._speed_limit = 50.0
	wolf.move(1.0 / 60.0)
	_check(wolf.facing.is_equal_approx(Vector2.DOWN) and is_equal_approx(wolf.sprite.rotation, PI), "sprite and facing follow actual movement")
	engine.debug_service.select_at(sheep.position)
	engine.entity_service.capture(sheep)
	_check(not sheep.alive and not engine.entity_service.capture(sheep), "death is idempotent")
	_step(20)
	_check(not engine.entity_service.entities.has(sheep), "corpse removed from registry")

func _verify_sheep() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(400, 300)) as SheepController
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(300, 300)) as WolfController
	sheep.facing = Vector2.RIGHT
	wolf.resting = true
	wolf.rest_elapsed = -100.0
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK, "hidden distant wolf does not affect sheep")
	wolf.position = Vector2(380, 300)
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "emergency radius bypasses vision")
	wolf.position = Vector2(100, 500)
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.ALERT, "lost threat becomes alert")
	engine.config.sheep.alert_duration = 0.02
	_step(2)
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK, "alert expires")
	sheep.receive_howl(Vector2(350, 300))
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE and sheep.threat_direction.x > 0.0, "howl causes outward panic")
	sheep.panic_elapsed = 1.0
	sheep.receive_howl(Vector2(350, 300))
	_check(sheep.panic_elapsed == 0.0, "repeated howl refreshes panic")
	engine.config.sheep.panic_duration = 0.01
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.ALERT, "panic becomes alert")
	_empty(false)
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(400, 300)) as SheepController
	var neighbor := _animal(AnimalController.Kind.SHEEP, Vector2(440, 300))
	neighbor.velocity = Vector2.DOWN * 20.0
	engine.entity_service.rebuild_spatial_index()
	neighbor.velocity = Vector2.UP * 20.0
	sheep.perceive(1.0 / 60.0)
	_check(sheep.neighbor_count == 1 and sheep.alignment.y > 0.0, "BOID reads snapshot velocity")
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(350, 300))
	engine.entity_service.rebuild_spatial_index()
	sheep.perceive(1.0 / 60.0)
	sheep.decide(1.0 / 60.0)
	_check(sheep.current_behavior == AnimalController.Behavior.HERDED and sheep.desired_velocity.x > 0.0, "dog pushes sheep away")
	dog.position = Vector2(100, 500)

func _verify_wolves() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(550, 300))
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	_step(1)
	_check(wolf.hunting and wolf.target == sheep and wolf.current_behavior == AnimalController.Behavior.STALK, "visible nearest sheep starts stalk")
	wolf.strategy = WolfController.Strategy.FRONTAL
	var seen := wolf.last_seen_position
	sheep.position = Vector2(300, 350)
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.SEARCH and wolf.last_seen_position == seen and wolf.movement_goal == seen, "hidden prey only updates unseen timer")
	sheep.position = Vector2(550, 310)
	_step(1)
	_check(wolf.target_visible and wolf.unseen_elapsed == 0.0 and wolf.last_seen_position == sheep.position, "reacquired prey refreshes memory")
	sheep.position = Vector2(300, 350)
	engine.config.wolf.memory_duration = 0.02
	_step(2)
	_check(not wolf.hunting and wolf.current_behavior == AnimalController.Behavior.REST and wolf.strategy_failures[0] > 0.9, "lost memory fails hunt once and rests")
	var failures_before: float = wolf.strategy_failures[0]
	wolf.end_hunt(false)
	_check(wolf.strategy_failures[0] == failures_before, "failure feedback is idempotent")
	engine.config.wolf.rest_duration = 0.01
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.PATROL, "rest ends into patrol without visible prey")
	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	_step(1)
	_check(not sheep.alive and engine.entity_service.capture_count == 1 and wolf.resting, "charge immediately captures in range and rests")
	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	var second := _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	second.facing = Vector2.RIGHT
	_step(1)
	_check(engine.entity_service.capture_count == 1, "multiple wolves cannot double capture")
	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	wolf.begin_hunt(sheep)
	wolf.set_behavior(AnimalController.Behavior.CHASE)
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(380, 300))
	wolf.resolve_interactions(0.0)
	_check(sheep.alive and not wolf.hunting and wolf.retreating, "post-movement dog interrupts capture from behind")
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.RETREAT, "tree prioritizes retreat")
	dog.position = Vector2(100, 500)
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.REST and not wolf.retreating, "cleared retreat starts rest")
	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(550, 300))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	wolf.begin_hunt(sheep)
	wolf.strategy = WolfController.Strategy.HOWL
	_step(1)
	_check(wolf.howled and (sheep as SheepController).has_panic and sheep.current_behavior != AnimalController.Behavior.FLEE, "howl is delivered after decisions")
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "howl affects next decision")
	var elapsed: float = (sheep as SheepController).panic_elapsed
	_step(1)
	_check((sheep as SheepController).panic_elapsed > elapsed, "one hunt does not howl repeatedly")
	wolf.end_hunt(true)
	_check(wolf.strategy_failures[WolfController.Strategy.HOWL] == 0.0, "success feedback stays nonnegative")

func _verify_dogs() -> void:
	_empty()
	var anchor := _animal(AnimalController.Kind.SHEEP, Vector2(500, 300)) as SheepController
	var stray := _animal(AnimalController.Kind.SHEEP, Vector2(680, 300)) as SheepController
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(600, 300)) as SheepdogController
	dog.protected_sheep = anchor
	dog._assignment_remaining = 100.0
	dog.facing = Vector2.RIGHT
	_step(1)
	_check(dog.collected_sheep == stray and dog.current_behavior == AnimalController.Behavior.COLLECT, "local stray is collected")
	_check(dog.movement_goal.x > stray.position.x, "collect point is outside stray relative to flock")
	stray.position = Vector2(570, 300)
	_step(1)
	_check(dog.collected_sheep == null and dog.current_behavior == AnimalController.Behavior.PATROL, "collected sheep releases task")
	var guard := dog.guard_point
	_step(1)
	_check(dog.guard_point != guard, "patrol target rotates over simulation time")
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(700, 300)) as WolfController
	wolf.resting = true
	wolf.rest_elapsed = -100.0
	_step(1)
	_check(dog.target == wolf and dog.current_behavior == AnimalController.Behavior.DRIVE, "visible nearby wolf interrupts patrol")
	var seen := dog.last_seen_position
	wolf.position = Vector2(300, 500)
	_step(1)
	_check(dog.target == wolf and dog.last_seen_position == seen and dog.movement_goal == seen, "dog pursues last visible position")
	engine.config.sheepdog.memory_duration = 0.02
	_step(2)
	_check(dog.target == null and dog.current_behavior == AnimalController.Behavior.RETURN, "dog returns when memory expires")
	dog.position = Vector2(1000, 300)
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.RETURN, "leash takes priority")
	_empty()
	anchor = _animal(AnimalController.Kind.SHEEP, Vector2(500, 300)) as SheepController
	dog = _animal(AnimalController.Kind.SHEEPDOG, Vector2(580, 300)) as SheepdogController
	var other := _animal(AnimalController.Kind.SHEEPDOG, Vector2(580, 300)) as SheepdogController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(670, 300)) as WolfController
	wolf.resting = true
	wolf.rest_elapsed = -100.0
	for item in [dog, other]:
		item.protected_sheep = anchor
		item._assignment_remaining = 100.0
		item.facing = Vector2.RIGHT
	_step(1)
	_check(dog.target == wolf and other.target == null, "equal distance wolf claim uses lower dog ID")
	engine.entity_service.dogs.reverse()
	_step(1)
	_check(dog.target == wolf and other.target == null, "wolf claim independent of dog registry order")
	wolf.position = Vector2(100, 500)
	dog.target = null
	other.target = null
	stray = _animal(AnimalController.Kind.SHEEP, Vector2(700, 300)) as SheepController
	_step(1)
	_check(dog.collected_sheep == stray and other.collected_sheep == null, "stray gets one responsible dog")
	_empty()
	dog = _animal(AnimalController.Kind.SHEEPDOG, Vector2(400, 300)) as SheepdogController
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.PATROL and dog.target == null, "no sheep falls back to wandering")

func _verify_behavior_edges() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(470, 300))
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.CHASE, "close prey enters charge")
	sheep.position = Vector2(550, 300)
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.CHASE, "charge persists when prey moves farther away")
	wolf.hunt_elapsed = engine.config.wolf.hunt_duration
	_step(1)
	_check(not wolf.hunting and wolf.current_behavior == AnimalController.Behavior.REST, "hunt timeout interrupts charge")
	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(550, 300))
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 300)) as WolfController
	wolf.facing = Vector2.RIGHT
	var nearer := _animal(AnimalController.Kind.SHEEP, Vector2(530, 300))
	_step(1)
	_check(wolf.target == nearer, "nearest visible sheep selected")
	engine.entity_service.capture(nearer)
	_step(1)
	_check(not wolf.hunting and wolf.resting, "target death ends hunt immediately")
	wolf.strategy_failures = [1000.0, 0.0, 1000.0, 1000.0]
	var sides: int = 0
	for index in range(200):
		wolf.begin_hunt(sheep)
		if wolf.strategy == WolfController.Strategy.SIDE:
			sides += 1
	_check(sides > 190, "feedback strongly favors the strategy with fewer failures")
	wolf.end_hunt(false)
	wolf.strategy_failures[0] = 2.0
	var before: float = wolf.strategy_failures[0]
	_step(1)
	_check(wolf.strategy_failures[0] < before, "strategy failures decay with simulation time")
	_empty(false)
	engine.config.sheep.idle_speed_scale = 0.0
	engine.config.sheep.alignment_weight = 0.0
	engine.config.sheep.cohesion_weight = 0.0
	var anchor := _animal(AnimalController.Kind.SHEEP, Vector2(500, 300)) as SheepController
	var stray := _animal(AnimalController.Kind.SHEEP, Vector2(680, 300)) as SheepController
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(755, 300)) as SheepdogController
	dog.protected_sheep = anchor
	dog._assignment_remaining = 1000.0
	var collected := false
	for index in range(600):
		_step(1)
		if anchor.position.distance_to(stray.position) < engine.config.sheepdog.local_flock_radius:
			collected = true
			break
	_check(collected, "dog pressure actually brings a stray back to local companions")
	_empty()
	anchor = _animal(AnimalController.Kind.SHEEP, Vector2(500, 300)) as SheepController
	dog = _animal(AnimalController.Kind.SHEEPDOG, Vector2(600, 300)) as SheepdogController
	var other := _animal(AnimalController.Kind.SHEEPDOG, Vector2(600, 300)) as SheepdogController
	var first := _animal(AnimalController.Kind.WOLF, Vector2(650, 280)) as WolfController
	var second := _animal(AnimalController.Kind.WOLF, Vector2(650, 320)) as WolfController
	for predator in [first, second]:
		predator.resting = true
		predator.rest_elapsed = -100.0
	for guard in [dog, other]:
		guard.facing = Vector2.RIGHT
		guard.protected_sheep = anchor
		guard._assignment_remaining = 100.0
	_step(1)
	_check(dog.target == first and other.target == second, "loser of shared wolf claim takes remaining threat")

func _verify_runtime_config() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(400, 300)) as SheepController
	sheep.receive_howl(Vector2(300, 300))
	_step(1)
	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.set_draft(engine.config)
	_check(panel.editors.has("Sheep.alignment_weight") and panel.editors.has("Wolves.howl_radius") and panel.editors.has("Dogs.vision_angle"), "new CFG fields exposed")
	var draft: SimulationConfig = engine.config.copy_config()
	draft.sheep.emergency_distance = draft.sheep.perception_radius + 1.0
	_check(not draft.validate().is_empty(), "invalid emergency range rejected")
	draft = engine.config.copy_config()
	draft.sheepdog.guard_distance = draft.sheepdog.leash_distance
	_check(not draft.validate().is_empty(), "invalid leash rejected")
	draft = engine.config.copy_config()
	draft.sheepdog.collect_distance = draft.sheep.herding_distance
	_check(not draft.validate().is_empty(), "collect point must exert sheep pressure")
	draft = engine.config.copy_config()
	draft.sheep.vision_angle = 250.0
	var elapsed := sheep.panic_elapsed
	_check(engine.request_config_apply(draft).is_empty(), "ordinary config accepted")
	engine._physics_process(0.0)
	_check(sheep.settings.vision_angle == 250.0 and sheep.panic_elapsed == elapsed and engine.paused, "paused hot apply preserves timers")
	var path := "res://output/verification/preset_v3.tres"
	_check(engine.save_preset(path) == OK and engine.load_preset(path) != null, "new preset round trip")
	var old: SimulationConfig = engine.config.copy_config()
	old.preset_version = 2
	var old_path := "res://output/verification/preset_old.tres"
	ResourceSaver.save(old, old_path)
	var before := FileAccess.get_file_as_string(old_path)
	_check(engine.load_preset(old_path) == null and FileAccess.get_file_as_string(old_path) == before, "old preset rejected unchanged")
	draft = engine.config.copy_config()
	draft.initial_sheep = 1
	draft.arena_size = Vector2(1400, 800)
	engine.request_config_apply(draft)
	engine._physics_process(0.0)
	_check(engine.paused and engine.entity_service.get_counts() == Vector3i(1, 0, 0), "restart preserves pause and uses new counts")
	_check(scene.get_node("Camera2D").position == Vector2(700, 400), "arena refresh independent of removed food system")

func _verify_controls() -> void:
	_empty()
	_key(KEY_1)
	_key(KEY_2, true)
	_key(KEY_3)
	engine._physics_process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "debug spawn and batch keys")
	var before: int = engine.step_count
	engine._physics_process(1.0)
	_check(engine.step_count == before, "pause freezes simulation")
	_key(KEY_N)
	engine._physics_process(0.0)
	_check(engine.step_count == before + 1 and engine.paused, "single step advances once")
	engine._physics_process(0.0)
	_check(engine.step_count == before + 1, "single step is consumed")
	_key(KEY_1, false, true)
	engine._physics_process(0.0)
	_check(engine.entity_service.get_counts().x == 1, "key repeats are ignored")

	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.show()
	panel.set_draft(engine.config)
	panel.editors["World.initial_sheep"].get_line_edit().grab_focus()
	_key(KEY_1)
	_key(KEY_R)
	engine._physics_process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "numeric field focus blocks gameplay shortcuts")
	panel.close()
	_key(KEY_F1)
	_check(engine.debug_service.show_details, "debug overlay toggle")

	engine.config = authored.copy_config()
	engine.reset_simulation()
	var positions: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		positions.append(animal.position)
	_step(3)
	engine.reset_simulation()
	var repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		repeated.append(animal.position)
	_check(positions == repeated, "reset reproduces seeded populations")
	_check(engine.step_count == 0 and engine.entity_service.capture_count == 0, "reset clears simulation counters")
	_check(engine.entity_service.get_counts() == Vector3i(240, 24, 12), "default population remains unchanged")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/verification")
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	authored = scene.simulation_config
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_physics_process(false)
	await process_frame
	_verify_resources_and_vision()
	_verify_sheep()
	_verify_wolves()
	_verify_dogs()
	_verify_behavior_edges()
	_verify_runtime_config()
	_verify_controls()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	authored = null
	scene = null
	engine = null
	print("SIMULATION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

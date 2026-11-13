extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node
var authored


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
	engine.config.sheep.hunger_per_second = 0.0
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


func _two_grass_points() -> void:
	engine.config.grass.per_patch = 1
	engine.config.grass.positions = PackedVector2Array([Vector2(340, 240), Vector2(940, 240)])
	engine.reset_grass()


func _verify_resources_and_lifecycle() -> void:
	_check(authored.validate().is_empty(), "authored CFG is valid")
	var copy = authored.copy_config()
	copy.sheep.move_speed = 19.0
	copy.grass.positions[0] = Vector2(100, 200)
	_check(authored.sheep.move_speed == 55.0 and authored.grass.positions[0] == Vector2(340, 240), "deep runtime copies preserve authored resources")

	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	var other := _animal(AnimalController.Kind.SHEEP, Vector2(400, 240)) as SheepController
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(1100, 600)) as WolfController
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(640, 360)) as SheepdogController
	_check(sheep != null and wolf != null and dog != null, "prefabs instantiate their dedicated controllers")
	for animal in [sheep, wolf, dog]:
		_check(animal.sprite.texture != null and animal.bt_player.get_bt_instance() != null, "prefab has appearance and behavior tree")
		_check(animal.bt_player.update_mode == BTPlayer.MANUAL, "behavior trees use unified manual updates")
	_check(sheep.bt_player.blackboard != other.bt_player.blackboard, "independent blackboards")
	var original_color := other.sprite.self_modulate
	sheep.set_behavior(AnimalController.Behavior.FLEE)
	_check(sheep.sprite.self_modulate.is_equal_approx(Color("#facc15")) and other.sprite.self_modulate == original_color, "state colors are per instance")
	wolf._speed_limit = 100.0
	for direction in [Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
		wolf.desired_velocity = direction * 100.0
		wolf.move(1.0 / 60.0)
		_check(is_zero_approx(wolf.sprite.rotation), "wolf triangle keeps its upward orientation")

	engine.debug_service.select_at(sheep.position)
	_check(engine.debug_service.selected == sheep, "world selection")
	engine.entity_service.capture(sheep)
	_check(engine.debug_service.selected == null and not sheep.alive, "death clears selection immediately")
	_step(19)
	_check(not engine.entity_service.entities.has(sheep) and not engine.entity_service.sheep.has(sheep), "corpse cleanup removes both registries")
	_check(root.get_node_or_null("g_gameplayEngine2") == null, "single gameplay engine")


func _verify_sheep_and_grass() -> void:
	_empty()
	_two_grass_points()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 0.8
	_step(179)
	_check(engine.grass_bites[0] == 3 and sheep.grazing_progress > 0.0, "unfinished grazing keeps food")
	_step(1)
	_check(engine.grass_bites[0] == 2 and is_equal_approx(sheep.hunger, 0.55), "one completed bite lowers hunger")
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "feeding continues below hungry threshold")
	_step(359)
	_check(sheep.hunger <= engine.config.sheep.full_threshold, "feeding ends at full threshold")
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK and sheep.grass_target_index == -1, "full sheep release food and wander")
	_check(not engine.consume_grass(0) and not scene.grass_visuals[0].visible, "depleted grass cannot feed another sheep")

	engine.config.grass.regrow_duration = 0.5
	engine.grass_regrow_remaining[0] = 0.5
	var remaining: float = engine.grass_regrow_remaining[0]
	engine._physics_process(1.0)
	_check(engine.grass_regrow_remaining[0] == remaining, "pause freezes regrowth")
	_step(29)
	_check(engine.grass_bites[0] == 0, "regrowth waits for its interval")
	_step(1)
	_check(engine.grass_bites[0] == 3 and scene.grass_visuals[0].visible, "regrowth restores food and appearance")

	_empty()
	_two_grass_points()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 0.59
	engine.config.sheep.hunger_per_second = 0.01
	_step(61)
	_check(sheep.hunger >= 0.6 and sheep.current_behavior == AnimalController.Behavior.GRAZE, "hunger increases and starts feeding")
	sheep.hunger = 0.999
	engine.config.sheep.hunger_per_second = 0.1
	_step(1)
	_check(sheep.hunger <= 1.0, "hunger stays normalized")

	_empty()
	_two_grass_points()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 1.0
	_step(1)
	var other := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	other.hunger = 1.0
	other._set_grass_target(0)
	other._retarget_remaining = 100.0
	sheep._retarget_remaining = 100.0
	engine.grass_bites[0] = 1
	_step(180)
	_check(sheep.meals_eaten + other.meals_eaten == 1, "two sheep cannot both eat the last bite")
	_step(1)
	_check(sheep.grass_target_index == 1 and other.grass_target_index == 1, "depletion redirects foragers to another patch")

	_empty()
	engine.config.grass.per_patch = 1
	engine.config.grass.positions = PackedVector2Array([Vector2(350, 240), Vector2(450, 240)])
	engine.reset_grass()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(400, 240)) as SheepController
	other = _animal(AnimalController.Kind.SHEEP, Vector2(400, 240)) as SheepController
	sheep.hunger = 1.0
	other.hunger = 1.0
	_step(1)
	_check(sheep.grass_target_index != other.grass_target_index, "target claims spread equal-distance foragers")
	_check(not sheep.separation.is_zero_approx(), "existing soft separation handles coincident animals")
	for index in range(engine.grass_bites.size()):
		while engine.consume_grass(index):
			pass
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK, "empty grass falls back to safe wandering")


func _verify_threats() -> void:
	_empty()
	_two_grass_points()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 1.0
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(420, 240)) as WolfController
	_step(90)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "distant resting wolf permits grazing")
	_check(engine.try_begin_hunt(), "a visible prey can start an explicit hunt")
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE and sheep.grazing_progress == 0.0, "hunting wolf interrupts a meal")
	_check(engine.grass_bites[0] == 3, "interrupted grazing does not consume grass")
	engine.finish_hunt()
	_step(30)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "safety memory delays feeding")
	_step(32)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "sheep resume feeding after danger")
	wolf.position = Vector2(360, 240)
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "nearby resting wolves still trigger emergency escape")


func _verify_wolves() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
	_step(30)
	_check(sheep.alive and not wolf.hunting, "rest period forbids opportunistic captures")
	engine.try_begin_hunt()
	_step(29)
	_check(sheep.alive, "capture requires a continuous full interval")
	_step(1)
	_check(not sheep.alive and engine.entity_service.capture_count == 1, "continuous capture succeeds")
	_check(not engine.hunt_active and engine.hunt_rest_remaining >= 15.0 and not wolf.hunting, "successful capture ends the round and starts rest")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
	engine.try_begin_hunt()
	_step(15)
	sheep.position = Vector2(500, 240)
	_step(1)
	_check(wolf.capture_progress == 0.0 and sheep.alive, "escaping reach resets capture")
	sheep.position = Vector2(340, 240)
	_step(29)
	_check(sheep.alive, "returning prey needs a fresh interval")
	_step(1)
	_check(not sheep.alive, "fresh capture interval completes")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
	_animal(AnimalController.Kind.WOLF, Vector2(345, 240))
	engine.try_begin_hunt()
	_step(30)
	_check(engine.entity_service.capture_count == 1, "cooperating wolves capture only once")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(500, 240)) as SheepController
	for index in range(5):
		_animal(AnimalController.Kind.WOLF, Vector2(380 + index * 5, 240))
	engine.config.wolf.hunt_duration = 0.1
	engine.try_begin_hunt()
	_check(engine.hunters.size() == 3, "hunt roster respects the cap")
	var supported: WolfController = engine.hunters[1]
	_step(1)
	_check(supported.target == sheep and supported.supporting_hunt and supported.movement_goal != sheep.position, "supporters share prey and approach the flank")
	_step(7)
	_check(not engine.hunt_active and engine.hunt_rest_remaining > 0.0, "timeout finishes a round")
	var rounds: int = engine.hunt_rounds
	_step(60)
	_check(engine.hunt_rounds == rounds, "no replacement hunters enter during rest")

	_empty()
	engine.config.perception_interval = 0.125
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
	engine.try_begin_hunt()
	_step(29)
	_animal(AnimalController.Kind.SHEEPDOG, Vector2(410, 240))
	_step(1)
	_check(sheep.alive and wolf.capture_progress == 0.0 and not wolf.hunting, "new dog interrupts capture between perception scans")
	_step(1)
	_check(not engine.hunt_active, "all hunters leaving ends the round")


func _verify_dogs() -> void:
	_empty()
	var left := _animal(AnimalController.Kind.SHEEP, Vector2(220, 300)) as SheepController
	var right := _animal(AnimalController.Kind.SHEEP, Vector2(1050, 300)) as SheepController
	var first := _animal(AnimalController.Kind.SHEEPDOG, Vector2(230, 300)) as SheepdogController
	var second := _animal(AnimalController.Kind.SHEEPDOG, Vector2(1040, 300)) as SheepdogController
	_step(1)
	_check(first.protected_sheep == left and second.protected_sheep == right, "dogs distribute between local flocks")
	_check(first.protection_center == left.position and second.protection_center == right.position, "protection uses local centers")
	engine.entity_service.capture(left)
	_step(1)
	_check(first.protected_sheep == right, "dead protection anchors are replaced")

	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(640, 360)) as SheepController
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(860, 360)) as WolfController
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(640, 360)) as SheepdogController
	engine.try_begin_hunt()
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.INTERCEPT, "dog intercepts a hunting threat")
	dog.position = dog.intercept_point
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.DRIVE, "dog drives after interception")
	wolf.position = Vector2(1200, 600)
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.RETURN, "dog returns when local threat leaves")
	dog.position = dog.guard_point
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.PATROL, "dog resumes local patrol")
	dog.position = Vector2(40, 120)
	_step(1)
	_check(dog.current_behavior == AnimalController.Behavior.RETURN, "local leash limits pursuit")
	engine.entity_service.capture(sheep)
	_step(1)
	_check(dog.protected_sheep == null, "empty flock clears anchor safely")


func _verify_runtime_config() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(200, 200)) as SheepController
	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.show()
	panel.set_draft(engine.config)
	_check(panel.editors.has("Sheep.hungry_threshold") and panel.editors.has("Wolves.max_hunters"), "CFG metadata generates species controls")
	panel.editors["Sheep.move_speed"].value = 31.0
	panel.editors["Sheep.move_speed"].get_line_edit().text = "31"
	_check(engine.config.sheep.move_speed == 0.0, "editing the form leaves live parameters unchanged")
	panel.apply_button.pressed.emit()
	engine._physics_process(0.0)
	_check(sheep.move_speed == 31.0 and engine.paused and engine.step_count == 0, "apply updates existing animals while paused without stepping")
	var second := _animal(AnimalController.Kind.SHEEP, Vector2(500, 200)) as SheepController
	_check(second.move_speed == 31.0, "new animals use applied parameters")
	_check(authored.sheep.move_speed == 55.0, "runtime changes do not overwrite authored CFG")
	sheep.hunger = 1.0
	_step(1)
	_check(sheep.velocity.length() > 0.0 and sheep.velocity.length() <= 31.001, "live speed change affects actual movement")

	panel.set_draft(engine.config)
	panel.editors["Sheep.full_threshold"].value = 0.8
	_check(panel.apply_button.disabled, "invalid hunger thresholds disable Apply")
	var invalid = engine.config.copy_config()
	invalid.sheep.full_threshold = 0.8
	_check(not engine.request_config_apply(invalid).is_empty() and engine.config.sheep.full_threshold == 0.2, "invalid config is rejected atomically")

	var changed = engine.config.copy_config()
	changed.initial_sheep = 3
	panel.set_draft(changed)
	_check(panel.apply_button.text == "Apply & restart", "structural changes explain the restart")
	panel.apply_button.pressed.emit()
	engine._physics_process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(3, 0, 0) and not engine.entity_service.entities.has(sheep), "population change recreates the simulation")
	_check(engine.paused and engine.step_count == 0, "restart preserves pause state")

	var path := "res://output/runtime-config-verification.tres"
	_check(engine.save_preset(path) == OK, "runtime preset saves")
	var loaded = engine.load_preset(path)
	_check(loaded != null and loaded.sheep.move_speed == 31.0 and loaded.initial_sheep == 3, "saved nested CFG round-trips")
	loaded.sheep.move_speed = 47.0
	_check(engine.config.sheep.move_speed == 31.0, "loaded preset is detached from live settings")
	panel._restore_defaults()
	_check(panel.draft.sheep.move_speed == 55.0 and engine.config.sheep.move_speed == 31.0, "defaults stage changes without applying")
	panel.close()

	_empty()
	_animal(AnimalController.Kind.SHEEP, Vector2(500, 240))
	for index in range(4):
		_animal(AnimalController.Kind.WOLF, Vector2(380 + 4 * index, 240))
	engine.try_begin_hunt()
	var limited = engine.config.copy_config()
	limited.wolf.max_hunters = 1
	engine.request_config_apply(limited)
	engine._physics_process(0.0)
	var active: int = 0
	for wolf in engine.entity_service.wolves:
		active += 1 if wolf.hunting else 0
	_check(active == 1, "lowering the live hunt cap releases excess hunters")


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
	_check(engine.hunt_rounds == 0 and not engine.hunt_active and engine.step_count == 0, "reset clears round state and counters")
	_check(engine.entity_service.get_counts() == Vector3i(240, 24, 12), "default population remains unchanged")


func _run() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	authored = scene.simulation_config
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_physics_process(false)
	await process_frame
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	authored = null
	scene = null
	engine = null
	print("SIMULATION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

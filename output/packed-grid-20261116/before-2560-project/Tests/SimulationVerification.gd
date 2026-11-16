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

func _animal(kind: AnimalEntity.Kind, point: Vector2) -> AnimalEntity:
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
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	_check(authored.validate().is_empty(), "authored CFG validates")
	var copy: SimulationConfig = authored.copy_config()
	copy.sheep.move_speed = 19.0
	_check(authored.sheep.move_speed == 70.0, "runtime resources are independent")
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(400, 300))
	for animal in [sheep, wolf, dog]:
		_check(data.brain_player[animal.row].get_bt_instance() != null and data.brain_player[animal.row].update_mode == BTPlayer.MANUAL, "manual behavior tree is instantiated")
		data.motion_facing[animal.row] = Vector2.RIGHT
		var radius: float = data.settings[animal.row].perception_radius
		var half: float = deg_to_rad(data.settings[animal.row].vision_angle * 0.5)
		_check(g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row]), "coincident target visible")
		_check(g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.RIGHT * radius), "range boundary visible")
		_check(not g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.RIGHT * (radius + 1.0)), "outside visual range rejected")
		_check(g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.from_angle(half) * 50.0), "angle boundary visible")
		_check(not g_gameplayEngine.animal_system.can_see(animal, data.motion_position[animal.row] + Vector2.from_angle(half + 0.01) * 50.0), "outside visual angle rejected")
		data.motion_velocity[animal.row] = Vector2.ZERO
		data.motion_desired_velocity[animal.row] = Vector2.ZERO
		data.motion_separation[animal.row] = Vector2.ZERO
		data.motion_speed_limit[animal.row] = 0.0
		g_gameplayEngine.animal_system.update_movement(1.0 / 60.0)
		_check(data.motion_facing[animal.row] == Vector2.RIGHT, "stationary facing retained")
	data.motion_desired_velocity[wolf.row] = Vector2.DOWN * 50.0
	data.motion_speed_limit[wolf.row] = 50.0
	g_gameplayEngine.animal_system.update_movement(1.0 / 60.0)
	data.brain_view[wolf.row].sync()
	_check(data.motion_facing[wolf.row].is_equal_approx(Vector2.DOWN) and is_equal_approx(data.brain_view[wolf.row].sprite.rotation, PI), "sprite and facing follow actual movement")
	engine.debug_service.select_at(data.motion_position[sheep.row])
	engine.entity_service.capture(sheep)
	_check(not data.identity_alive[sheep.row] and not engine.entity_service.capture(sheep), "death is idempotent")
	_step(20)
	_check(not engine.entity_service.entities.has(sheep), "corpse removed from registry")

func _verify_sheep() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300)) as AnimalEntity
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(300, 300)) as AnimalEntity
	data.motion_facing[sheep.row] = Vector2.RIGHT
	data.wolf_resting[wolf.row] = int(true)
	data.wolf_rest_elapsed[wolf.row] = -100.0
	_step(1)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.FLOCK, "hidden distant wolf does not affect sheep")
	data.motion_position[wolf.row] = Vector2(380, 300)
	_step(1)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.FLEE, "emergency radius bypasses vision")
	data.motion_position[wolf.row] = Vector2(100, 500)
	_step(1)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.ALERT, "lost threat becomes alert")
	engine.config.sheep.alert_duration = 0.02
	_step(2)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.FLOCK, "alert expires")
	g_gameplayEngine.sheep_system.receive_howl(sheep, Vector2(350, 300))
	_step(1)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.FLEE and data.sheep_threat_direction[sheep.row].x > 0.0, "howl causes outward panic")
	data.sheep_panic_elapsed[sheep.row] = 1.0
	g_gameplayEngine.sheep_system.receive_howl(sheep, Vector2(350, 300))
	_check(data.sheep_panic_elapsed[sheep.row] == 0.0, "repeated howl refreshes panic")
	engine.config.sheep.panic_duration = 0.01
	_step(1)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.ALERT, "panic becomes alert")
	_empty(false)
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300)) as AnimalEntity
	var neighbor := _animal(AnimalEntity.Kind.SHEEP, Vector2(440, 300))
	data.motion_velocity[neighbor.row] = Vector2.DOWN * 20.0
	engine.entity_service.rebuild_spatial_index()
	data.motion_velocity[neighbor.row] = Vector2.UP * 20.0
	g_gameplayEngine.sheep_system.perceive(sheep, 1.0 / 60.0)
	_check(data.sheep_neighbor_count[sheep.row] == 1 and data.sheep_alignment[sheep.row].y > 0.0, "BOID reads snapshot velocity")
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(350, 300))
	engine.entity_service.rebuild_spatial_index()
	g_gameplayEngine.sheep_system.perceive(sheep, 1.0 / 60.0)
	g_gameplayEngine.animal_system.decide(sheep, 1.0 / 60.0)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.HERDED and data.motion_desired_velocity[sheep.row].x > 0.0, "dog pushes sheep away")
	data.motion_position[dog.row] = Vector2(100, 500)

func _verify_wolves() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	_step(1)
	_check(data.wolf_hunting[wolf.row] and data.live(data.memory_target[wolf.row]) == sheep and data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.STALK, "visible nearest sheep starts stalk")
	data.wolf_strategy[wolf.row] = AnimalEntity.Strategy.FRONTAL
	var seen := data.memory_last_seen_position[wolf.row]
	data.motion_position[sheep.row] = Vector2(300, 350)
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.SEARCH and data.memory_last_seen_position[wolf.row] == seen and data.motion_movement_goal[wolf.row] == seen, "hidden prey only updates unseen timer")
	data.motion_position[sheep.row] = Vector2(550, 310)
	_step(1)
	_check(data.memory_target_visible[wolf.row] and data.memory_unseen_elapsed[wolf.row] == 0.0 and data.memory_last_seen_position[wolf.row] == data.motion_position[sheep.row], "reacquired prey refreshes memory")
	data.motion_position[sheep.row] = Vector2(300, 350)
	engine.config.wolf.memory_duration = 0.02
	_step(2)
	_check(not data.wolf_hunting[wolf.row] and data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.REST and data.wolf_strategy_failures[wolf.row][0] > 0.9, "lost memory fails hunt once and rests")
	var failures_before: float = data.wolf_strategy_failures[wolf.row][0]
	g_gameplayEngine.wolf_system.end_hunt(wolf, false)
	_check(data.wolf_strategy_failures[wolf.row][0] == failures_before, "failure feedback is idempotent")
	engine.config.wolf.rest_duration = 0.01
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.PATROL, "rest ends into patrol without visible prey")
	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	_step(1)
	_check(not data.identity_alive[sheep.row] and engine.entity_service.capture_count == 1 and data.wolf_resting[wolf.row], "charge immediately captures in range and rests")
	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	var second := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[second.row] = Vector2.RIGHT
	_step(1)
	_check(engine.entity_service.capture_count == 1, "multiple wolves cannot double capture")
	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(420, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	g_gameplayEngine.wolf_system.begin_hunt(wolf, sheep)
	data.brain_current_behavior[wolf.row] = AnimalEntity.Behavior.CHASE
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(380, 300))
	g_gameplayEngine.wolf_system.resolve_interactions(wolf, 0.0)
	_check(data.identity_alive[sheep.row] and not data.wolf_hunting[wolf.row] and data.wolf_retreating[wolf.row], "post-movement dog interrupts capture from behind")
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.RETREAT, "tree prioritizes retreat")
	data.motion_position[dog.row] = Vector2(100, 500)
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.REST and not data.wolf_retreating[wolf.row], "cleared retreat starts rest")
	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	g_gameplayEngine.wolf_system.begin_hunt(wolf, sheep)
	data.wolf_strategy[wolf.row] = AnimalEntity.Strategy.HOWL
	_step(1)
	_check(data.wolf_howled[wolf.row] and data.sheep_has_panic[(sheep as AnimalEntity).row] and data.brain_current_behavior[sheep.row] != AnimalEntity.Behavior.FLEE, "howl is delivered after decisions")
	_step(1)
	_check(data.brain_current_behavior[sheep.row] == AnimalEntity.Behavior.FLEE, "howl affects next decision")
	var elapsed: float = data.sheep_panic_elapsed[(sheep as AnimalEntity).row]
	_step(1)
	_check(data.sheep_panic_elapsed[(sheep as AnimalEntity).row] > elapsed, "one hunt does not howl repeatedly")
	g_gameplayEngine.wolf_system.end_hunt(wolf, true)
	_check(data.wolf_strategy_failures[wolf.row][AnimalEntity.Strategy.HOWL] == 0.0, "success feedback stays nonnegative")

func _verify_dogs() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var anchor := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	var stray := _animal(AnimalEntity.Kind.SHEEP, Vector2(680, 300)) as AnimalEntity
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300)) as AnimalEntity
	data.dog_protected_sheep[dog.row] = anchor
	data.dog_assignment_remaining[dog.row] = 100.0
	data.motion_facing[dog.row] = Vector2.RIGHT
	_step(1)
	_check(data.live(data.dog_collected_sheep[dog.row]) == stray and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.COLLECT, "local stray is collected")
	_check(data.motion_movement_goal[dog.row].x > data.motion_position[stray.row].x, "collect point is outside stray relative to flock")
	data.motion_position[stray.row] = Vector2(570, 300)
	_step(1)
	_check(data.live(data.dog_collected_sheep[dog.row]) == null and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.PATROL, "collected sheep releases task")
	var guard := data.dog_guard_point[dog.row]
	_step(1)
	_check(data.dog_guard_point[dog.row] != guard, "patrol target rotates over simulation time")
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(700, 300)) as AnimalEntity
	data.wolf_resting[wolf.row] = int(true)
	data.wolf_rest_elapsed[wolf.row] = -100.0
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.DRIVE, "visible nearby wolf interrupts patrol")
	var seen := data.memory_last_seen_position[dog.row]
	data.motion_position[wolf.row] = Vector2(300, 500)
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.memory_last_seen_position[dog.row] == seen and data.motion_movement_goal[dog.row] == seen, "dog pursues last visible position")
	engine.config.sheepdog.memory_duration = 0.02
	_step(2)
	_check(data.live(data.memory_target[dog.row]) == null and data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.RETURN, "dog returns when memory expires")
	data.motion_position[dog.row] = Vector2(1000, 300)
	_step(1)
	_check(data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.RETURN, "leash takes priority")
	_empty()
	anchor = _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	dog = _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(580, 300)) as AnimalEntity
	var other := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(580, 300)) as AnimalEntity
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(670, 300)) as AnimalEntity
	data.wolf_resting[wolf.row] = int(true)
	data.wolf_rest_elapsed[wolf.row] = -100.0
	for item in [dog, other]:
		data.dog_protected_sheep[item.row] = anchor
		data.dog_assignment_remaining[item.row] = 100.0
		data.motion_facing[item.row] = Vector2.RIGHT
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.live(data.memory_target[other.row]) == null, "equal distance wolf claim uses lower dog ID")
	engine.entity_service.dog_rows.reverse()
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == wolf and data.live(data.memory_target[other.row]) == null, "wolf claim independent of dog registry order")
	data.motion_position[wolf.row] = Vector2(100, 500)
	data.memory_target[dog.row] = null
	data.memory_target[other.row] = null
	stray = _animal(AnimalEntity.Kind.SHEEP, Vector2(700, 300)) as AnimalEntity
	_step(1)
	_check(data.live(data.dog_collected_sheep[dog.row]) == stray and data.live(data.dog_collected_sheep[other.row]) == null, "stray gets one responsible dog")
	_empty()
	dog = _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(400, 300)) as AnimalEntity
	_step(1)
	_check(data.brain_current_behavior[dog.row] == AnimalEntity.Behavior.PATROL and data.live(data.memory_target[dog.row]) == null, "no sheep falls back to wandering")

func _verify_behavior_edges() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(470, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.CHASE, "close prey enters charge")
	data.motion_position[sheep.row] = Vector2(550, 300)
	_step(1)
	_check(data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.CHASE, "charge persists when prey moves farther away")
	data.wolf_hunt_elapsed[wolf.row] = engine.config.wolf.hunt_duration
	_step(1)
	_check(not data.wolf_hunting[wolf.row] and data.brain_current_behavior[wolf.row] == AnimalEntity.Behavior.REST, "hunt timeout interrupts charge")
	_empty()
	sheep = _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	wolf = _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300)) as AnimalEntity
	data.motion_facing[wolf.row] = Vector2.RIGHT
	var nearer := _animal(AnimalEntity.Kind.SHEEP, Vector2(530, 300))
	_step(1)
	_check(data.live(data.memory_target[wolf.row]) == nearer, "nearest visible sheep selected")
	engine.entity_service.capture(nearer)
	_step(1)
	_check(not data.wolf_hunting[wolf.row] and data.wolf_resting[wolf.row], "target death ends hunt immediately")
	data.wolf_strategy_failures[wolf.row] = Vector4(1000.0, 0.0, 1000.0, 1000.0)
	var sides: int = 0
	for index in range(200):
		g_gameplayEngine.wolf_system.begin_hunt(wolf, sheep)
		if data.wolf_strategy[wolf.row] == AnimalEntity.Strategy.SIDE:
			sides += 1
	_check(sides > 190, "feedback strongly favors the strategy with fewer failures")
	g_gameplayEngine.wolf_system.end_hunt(wolf, false)
	data.wolf_strategy_failures[wolf.row][0] = 2.0
	var before: float = data.wolf_strategy_failures[wolf.row][0]
	_step(1)
	_check(data.wolf_strategy_failures[wolf.row][0] < before, "strategy failures decay with simulation time")
	_empty(false)
	engine.config.sheep.idle_speed_scale = 0.0
	engine.config.sheep.alignment_weight = 0.0
	engine.config.sheep.cohesion_weight = 0.0
	var anchor := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	var stray := _animal(AnimalEntity.Kind.SHEEP, Vector2(680, 300)) as AnimalEntity
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(755, 300)) as AnimalEntity
	data.dog_protected_sheep[dog.row] = anchor
	data.dog_assignment_remaining[dog.row] = 1000.0
	var collected := false
	for index in range(600):
		_step(1)
		if data.motion_position[anchor.row].distance_to(data.motion_position[stray.row]) < engine.config.sheepdog.local_flock_radius:
			collected = true
			break
	_check(collected, "dog pressure actually brings a stray back to local companions")
	_empty()
	anchor = _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300)) as AnimalEntity
	dog = _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300)) as AnimalEntity
	var other := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(600, 300)) as AnimalEntity
	var first := _animal(AnimalEntity.Kind.WOLF, Vector2(650, 280)) as AnimalEntity
	var second := _animal(AnimalEntity.Kind.WOLF, Vector2(650, 320)) as AnimalEntity
	for predator in [first, second]:
		data.wolf_resting[predator.row] = int(true)
		data.wolf_rest_elapsed[predator.row] = -100.0
	for guard in [dog, other]:
		data.motion_facing[guard.row] = Vector2.RIGHT
		data.dog_protected_sheep[guard.row] = anchor
		data.dog_assignment_remaining[guard.row] = 100.0
	_step(1)
	_check(data.live(data.memory_target[dog.row]) == first and data.live(data.memory_target[other.row]) == second, "loser of shared wolf claim takes remaining threat")

func _verify_runtime_config() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(400, 300)) as AnimalEntity
	g_gameplayEngine.sheep_system.receive_howl(sheep, Vector2(300, 300))
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
	var elapsed := data.sheep_panic_elapsed[sheep.row]
	_check(engine.request_config_apply(draft).is_empty(), "ordinary config accepted")
	engine._process(0.0)
	_check(data.settings[sheep.row].vision_angle == 250.0 and data.sheep_panic_elapsed[sheep.row] == elapsed and engine.paused, "paused hot apply preserves timers")
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
	engine._process(0.0)
	_check(engine.paused and engine.entity_service.get_counts() == Vector3i(1, 0, 0), "restart preserves pause and uses new counts")
	_check(scene.get_node("Camera2D").position == Vector2(700, 400), "arena refresh independent of removed food system")

func _verify_controls() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	_key(KEY_1)
	_key(KEY_2, true)
	_key(KEY_3)
	engine._process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "debug spawn and batch keys")
	var before: int = engine.step_count
	engine._process(1.0)
	_check(engine.step_count == before, "pause freezes simulation")
	_key(KEY_N)
	engine._process(0.0)
	_check(engine.step_count == before + 1 and engine.paused, "single step advances once")
	engine._process(0.0)
	_check(engine.step_count == before + 1, "single step is consumed")
	_key(KEY_1, false, true)
	engine._process(0.0)
	_check(engine.entity_service.get_counts().x == 1, "key repeats are ignored")

	var panel: RuntimeConfigPanel = scene.hud.parameters
	panel.show()
	panel.set_draft(engine.config)
	panel.editors["World.initial_sheep"].get_line_edit().grab_focus()
	_key(KEY_1)
	_key(KEY_R)
	engine._process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(1, 10, 1), "numeric field focus blocks gameplay shortcuts")
	panel.close()
	_key(KEY_F1)
	_check(engine.debug_service.show_details, "debug overlay toggle")

	engine.config = authored.copy_config()
	engine.reset_simulation()
	var positions: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		positions.append(data.motion_position[animal.row])
	_step(3)
	engine.reset_simulation()
	var repeated: Array[Vector2] = []
	for animal in engine.entity_service.entities:
		repeated.append(data.motion_position[animal.row])
	_check(positions == repeated, "reset reproduces seeded populations")
	_check(engine.step_count == 0 and engine.entity_service.capture_count == 0, "reset clears simulation counters")
	_check(engine.entity_service.get_counts() == Vector3i(240, 24, 12), "default population remains unchanged")

func _verify_clock() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty(false)
	engine.simulation_hz = 60.0
	engine.max_steps_per_frame = 4
	engine.paused = false
	var interval: float = 1.0 / engine.simulation_hz
	engine._process(interval * 0.4)
	_check(engine.step_count == 0 and is_equal_approx(engine._accumulator, interval * 0.4), "fractional frame waits for a full step")
	engine._process(interval * 0.6)
	_check(engine.step_count == 1 and is_zero_approx(engine._accumulator), "accumulated full step advances once")
	engine.reset_simulation()
	engine._process(interval * 6.4)
	_check(engine.step_count == 4 and is_equal_approx(engine._accumulator, interval * 0.4), "catch-up is bounded and retains only fractional remainder")
	engine._process(0.0)
	_check(engine.step_count == 4, "discarded backlog is not replayed")
	engine._process(interval * 0.6)
	_check(engine.step_count == 5, "fractional remainder carries into next frame")
	engine.reset_simulation()
	engine._process(interval * 0.4)
	engine.paused = true
	engine._process(100.0)
	_check(engine.step_count == 0 and engine._accumulator == 0.0, "pause discards fractional time and accrues no debt")
	engine.paused = false
	engine._process(interval * 0.6)
	_check(engine.step_count == 0, "resume starts with a fresh accumulator")
	engine._process(interval * 0.4)
	_check(engine.step_count == 1, "resume advances after a new full interval")
	engine.reset_simulation()
	engine.simulation_hz = 30.0
	engine.paused = true
	engine.request_single_step()
	engine._process(0.0)
	_check(engine.step_count == 1 and is_equal_approx(engine.simulation_time, 1.0 / 30.0), "single step uses configured interval")
	engine._process(10.0)
	_check(engine.step_count == 1, "single-step request is consumed once")
	engine.paused = false
	engine._process(0.01)
	engine.reset_simulation()
	_check(engine._accumulator == 0.0 and engine.step_count == 0, "reset clears accumulated time")
	var errors_enabled := Engine.print_error_messages
	Engine.print_error_messages = false
	var invalid_results: Array[bool] = []
	for frequency in [0.0, -1.0, NAN, INF, 1.0e-320]:
		engine.simulation_hz = frequency
		engine._process(1.0)
		invalid_results.append(engine.step_count == 0 and engine._clock_error_reported)
	engine.simulation_hz = 60.0
	engine.max_steps_per_frame = 0
	engine._process(1.0)
	invalid_results.append(engine.step_count == 0 and engine._clock_error_reported)
	engine.max_steps_per_frame = 4
	for frame_delta in [NAN, INF, -1.0]:
		engine._process(frame_delta)
		invalid_results.append(engine.step_count == 0 and engine._clock_error_reported)
	Engine.print_error_messages = errors_enabled
	for result in invalid_results:
		_check(result, "invalid clock input prevents automatic stepping")
	engine._process(1.0 / 60.0)
	_check(engine.step_count == 1 and not engine._clock_error_reported, "valid configuration resumes automatic stepping")
	_empty(false)
	engine.config.initial_sheep = 24
	engine.config.initial_wolves = 4
	engine.config.initial_sheepdogs = 2
	engine.reset_simulation()
	for index in range(120):
		engine._process(1.0 / 60.0)
	var expected: Array = [engine.rng.state, engine.entity_service.capture_count]
	for animal in engine.entity_service.entities:
		expected.append([data.identity_entity_id[animal.row], data.motion_position[animal.row], data.motion_velocity[animal.row], data.brain_current_behavior[animal.row]])
	engine.reset_simulation()
	for index in range(60):
		engine._process(1.0 / 120.0)
		engine._process(3.0 / 120.0)
	var actual: Array = [engine.rng.state, engine.entity_service.capture_count]
	for animal in engine.entity_service.entities:
		actual.append([data.identity_entity_id[animal.row], data.motion_position[animal.row], data.motion_velocity[animal.row], data.brain_current_behavior[animal.row]])
	_check(engine.step_count == 120 and expected == actual and is_zero_approx(engine._accumulator), "frame grouping preserves seeded simulation at equal step count")
	engine.reset_simulation()
	engine._process(interval * 0.4)
	var replacement: SimulationConfig = engine.config.copy_config()
	replacement.initial_sheep = 1
	engine.request_config_apply(replacement)
	engine._process(0.0)
	_check(engine._accumulator == 0.0 and engine.step_count == 0 and engine.entity_service.get_counts().x == 1, "configuration restart clears partial step")

func _verify_ecs_storage() -> void:
	_empty()
	var service: EntityService = engine.entity_service
	service.clear()
	var data := service.data
	var prey := _animal(AnimalEntity.Kind.SHEEP, Vector2(500, 300))
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(100, 300))
	var dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(900, 300))
	data.memory_target[wolf.row] = prey
	data.dog_protected_sheep[dog.row] = prey
	data.dog_collected_sheep[dog.row] = prey
	var old_uid := prey.uid
	var old_slot := prey.slot
	var view := data.brain_view[prey.row]
	var player := data.brain_player[prey.row]
	player.get_blackboard().set_var(&"reuse_test", 42)
	data.sheep_has_panic[prey.row] = 1
	data.motion_velocity[prey.row] = Vector2(20, 10)
	data.motion_velocity[dog.row] = Vector2(7, 9)
	data.dog_protection_center[dog.row] = Vector2(800, 250)
	var dog_uid := dog.uid
	engine.debug_service.selected = prey
	_check(service.capture(prey) and not service.capture(prey), "death captures exactly once")
	_check(data.live(data.memory_target[wolf.row]) == null and engine.debug_service.selected == null, "death invalidates target and selection immediately")
	service.remove_expired()
	_check(not prey.enabled and view.visible and not player.active, "disabled life keeps a short corpse presentation")
	_check(data.active_count == 2 and data.retained_count == 3 and not service.entities.has(prey), "corpse is outside the contiguous active prefix")
	_check(dog.row == 0 and dog.uid == dog_uid and data.motion_position[dog.row] == Vector2(900, 300) and data.motion_velocity[dog.row] == Vector2(7, 9) and data.dog_protection_center[dog.row] == Vector2(800, 250), "row swap preserves identity and independent component fields")
	_check(data.brain_view[dog.row].entity == dog and data.live(data.dog_collected_sheep[dog.row]) == null, "row swap preserves scene association and invalidates dog references")
	for row in range(data.row_to_slot.size()):
		_check(data.slot_to_row[data.row_to_slot[row]] == row, "slot mapping follows row swap")
	var remaining := data.identity_death_remaining[prey.row]
	engine._process(1.0)
	_check(data.identity_death_remaining[prey.row] == remaining, "pause freezes corpse lifetime")
	var extra := _animal(AnimalEntity.Kind.SHEEP, Vector2(700, 400))
	_check(extra.slot != old_slot and view.visible, "spawning cannot reuse a visible corpse")
	_step(20)
	_check(not view.visible and data.retained_count == data.active_count, "expired corpse enters the reusable suffix")
	var allocated := data.row_to_slot.size()
	var replacement := _animal(AnimalEntity.Kind.SHEEP, Vector2(600, 400))
	_check(replacement.slot == old_slot and replacement.uid != old_uid and data.row_to_slot.size() == allocated, "reuse keeps the slot and allocates a new uid without growing storage")
	_check(data.row_of(prey) == -1 and data.live(prey) == null and data.live(data.memory_target[wolf.row]) == null, "old life handle cannot follow a reused slot")
	_check(data.brain_view[replacement.row] == view and data.brain_player[replacement.row] == player, "reuse preserves scene and behavior tree objects")
	_check(not data.sheep_has_panic[replacement.row] and data.motion_velocity[replacement.row] == Vector2.ZERO and data.memory_target[replacement.row] == null, "reuse clears previous life state")
	_check(not player.get_blackboard().has_var(&"reuse_test"), "reuse clears behavior tree blackboard")
	_check(view.global_position == Vector2(600, 400) and replacement.enabled, "reuse synchronizes spawn presentation")
	_check(service.capture(extra) and service.capture(replacement), "multiple deaths can be queued in one interaction phase")
	service.remove_expired()
	_check(data.active_count == 2 and service.get_counts() == Vector3i(0, 1, 1), "compaction does not skip consecutive deaths")
	var last_uid := dog.uid
	for index in range(3):
		engine.reset_simulation()
	_check(data.row_to_slot.size() == allocated and service.get_counts() == Vector3i.ZERO, "empty resets retain allocated storage without growth")
	var new_dog := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(900, 300))
	_check(new_dog.uid > last_uid and data.live(dog) == null, "reset does not recycle uid values")
	service.clear()
	var after_clear := _animal(AnimalEntity.Kind.SHEEPDOG, Vector2(900, 300))
	_check(after_clear.uid > new_dog.uid and data.live(new_dog) == null, "clear cannot revive an old handle")

func _verify_debug_panel() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	_empty()
	engine.entity_service.clear()
	var debug: DebugService = engine.debug_service
	var panel: DebugPanel = scene.hud.debug_panel
	var wolf := _animal(AnimalEntity.Kind.WOLF, Vector2(400, 300))
	var sheep := _animal(AnimalEntity.Kind.SHEEP, Vector2(550, 300))
	data.memory_target[wolf.row] = sheep
	data.memory_target_visible[wolf.row] = int(false)
	data.memory_last_seen_position[wolf.row] = Vector2(500, 320)
	debug.selected = wolf
	debug.show_details = false
	debug.selected_only = true
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F3
	scene.hud._unhandled_key_input(event)
	_check(panel.visible and not scene.hud.parameters.visible, "F3 opens DebugPanel separately from parameters")
	panel.enabled_toggle.button_pressed = true
	_check(debug.show_details, "panel enables auxiliary visuals immediately")
	panel.scope.select(1)
	panel.scope.item_selected.emit(1)
	_check(not debug.selected_only, "panel supports all-animal scope")
	var rng_state: int = engine.rng.state
	var target_position := data.motion_position[sheep.row]
	var remembered := data.memory_last_seen_position[wolf.row]
	data.wolf_howl_pending[wolf.row] = int(true)
	engine.wolf_system.resolve_interactions(wolf, 0.0)
	_check(debug.howl_events.size() == 1, "settled howl records a visual event")
	var origin: Vector2 = debug.howl_events[0]["position"]
	var radius: float = debug.howl_events[0]["radius"]
	data.motion_position[wolf.row] += Vector2(40, 0)
	var draft: SimulationConfig = engine.config.copy_config()
	draft.wolf.howl_radius += 10.0
	engine.request_config_apply(draft)
	engine._process(0.0)
	_check(debug.howl_events[0]["position"] == origin and debug.howl_events[0]["radius"] == radius, "howl snapshots origin and range at settlement")
	engine._process(1.0)
	_check(debug.howl_events[0]["elapsed"] == 0.0, "pause freezes howl pulse")
	debug.advance_visuals(0.1)
	_check(is_equal_approx(debug.howl_events[0]["elapsed"], 0.1), "visual event advances with simulation delta")
	panel.controls["howl"].button_pressed = false
	_check(debug.howl_events.is_empty(), "disabling howl clears pending presentation")
	panel.controls["howl"].button_pressed = true
	_check(debug.howl_events.is_empty(), "reenabling does not replay old howls")
	_check(engine.rng.state == rng_state and data.motion_position[sheep.row] == target_position and data.memory_last_seen_position[wolf.row] == remembered, "visual controls preserve RNG and hidden target memory")
	panel.close()
	_check(debug.show_details and not panel.visible, "closing panel preserves visual choices")
	event.keycode = KEY_F2
	scene.hud._unhandled_key_input(event)
	_check(scene.hud.parameters.visible and not panel.visible, "F2 keeps panels mutually exclusive")
	event.keycode = KEY_F3
	scene.hud._unhandled_key_input(event)
	_check(panel.visible and not scene.hud.parameters.visible, "opening DebugPanel closes parameters")
	event.keycode = KEY_ESCAPE
	scene.hud._unhandled_key_input(event)
	_check(not panel.visible, "Escape closes DebugPanel")
	engine.reset_simulation()
	_check(debug.show_details and not debug.selected_only and debug.howl_events.is_empty(), "reset keeps visual preferences and clears effects")
	debug.show_details = false
	debug.selected_only = true

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/verification")
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	authored = scene.simulation_config
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	await process_frame
	_check(not engine.debug_service.show_details and not scene.hud.debug_panel.visible and engine.debug_service.selected_only, "default presentation keeps overlays off with selected-only scope")
	_verify_resources_and_vision()
	_verify_sheep()
	_verify_wolves()
	_verify_dogs()
	_verify_behavior_edges()
	_verify_runtime_config()
	_verify_controls()
	_verify_clock()
	_verify_ecs_storage()
	_verify_debug_panel()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	authored = null
	scene = null
	engine = null
	print("SIMULATION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

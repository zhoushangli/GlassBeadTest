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
	engine.config.sheep.hunger_per_second = 0
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
	engine.config.grass.bites = 3
	engine.config.sheep.grazing_duration = 3.0
	engine.config.grass.positions = PackedVector2Array([Vector2(340, 240), Vector2(940, 240)])
	engine.reset_grass()

func _verify_resources_and_lifecycle() -> void:
	_check(authored.validate().is_empty(), "authored CFG is valid")
	var copy: Resource = authored.copy_config()
	copy.sheep.move_speed = 19.0
	copy.grass.positions[0] = Vector2(100, 200)
	_check(authored.sheep.move_speed == 70.0 and authored.grass.positions[0] == Vector2(340, 240), "deep runtime copies preserve authored resources")

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
	sheep.hunger = 80
	_step(179)
	_check(engine.grass_bites[0] == 3 and sheep.grazing_progress > 0.0, "unfinished grazing keeps food")
	_step(1)
	_check(engine.grass_bites[0] == 2 and sheep.hunger == 55, "one completed bite lowers hunger")
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
	sheep.hunger = 59
	engine.config.sheep.hunger_per_second = 01
	_step(61)
	_check(sheep.hunger >= 60 and sheep.current_behavior == AnimalController.Behavior.GRAZE, "hunger increases and starts feeding")
	sheep.hunger = 99
	engine.config.sheep.hunger_per_second = 100
	_step(1)
	_check(sheep.hunger <= 100, "hunger stays within 0-100")

	_empty()
	_two_grass_points()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 100
	_step(1)
	var other := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	other.hunger = 100
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
	sheep.hunger = 100
	other.hunger = 100
	_step(1)
	_check(sheep.grass_target_index != other.grass_target_index, "target claims spread equal-distance foragers")
	_check(not sheep.separation.is_zero_approx(), "existing soft separation handles coincident animals")
	for index in range(engine.grass_bites.size()):
		while engine.consume_grass(index):
			pass
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLOCK, "empty grass falls back to safe wandering")

	_empty()
	engine.config.grass.per_patch = 1
	engine.config.grass.positions = PackedVector2Array([Vector2(350, 240)])
	engine.reset_grass()
	engine.grass_bites[0] = 1
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(300, 240)) as SheepController
	other = _animal(AnimalController.Kind.SHEEP, Vector2(300, 250)) as SheepController
	sheep.hunger = 100
	other.hunger = 100
	_step(1)
	_check(sheep.grass_target_index == 0 and other.grass_target_index == -1, "new foragers cannot overbook the remaining food")
	_check(other.current_behavior == AnimalController.Behavior.FLOCK, "unserved hungry sheep wander until the next search")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(100, 100)) as SheepController
	sheep.hunger = 30
	engine.config.sheep.hunger_per_second = 1
	_step(59)
	_check(sheep.hunger == 30, "sub-point hunger is retained until a whole point accrues")
	engine._physics_process(10.0)
	_check(sheep.hunger == 30, "pause freezes hunger accumulation")
	_step(1)
	_check(sheep.hunger == 31, "sixty small steps add one hunger point")
	sheep.hunger = 100
	_step(30)
	sheep.hunger = 99
	_step(30)
	_check(sheep.hunger == 99, "maximum hunger discards excess fractional progress")
	sheep.hunger = 1
	sheep._set_grass_target(0)
	sheep.set_behavior(AnimalController.Behavior.GRAZE)
	sheep.position = engine.grass_positions[0]
	sheep.grass_target = engine.grass_positions[0]
	engine.grass_bites[0] = 1
	sheep.resolve_interactions(engine.config.sheep.grazing_duration)
	_check(sheep.hunger == 0, "eating clamps integer hunger at zero")

func _verify_threats() -> void:
	_empty()
	_two_grass_points()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	var expected := {0: 130.0, 25: 106.5, 50: 83.0, 75: 59.5, 100: 36.0}
	for value in expected:
		sheep.hunger = value
		_check(is_equal_approx(sheep.avoidance_radius, expected[value]), "hunger %d interpolates avoidance radius" % value)
	sheep.hunger = 100
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(420, 240)) as WolfController
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE and not sheep._grass_unsafe(0), "hungry sheep can graze near a wolf outside their reduced avoidance radius")
	var state: int = engine.rng.state
	for index in range(10):
		sheep.perceive(0.0)
	_check(engine.rng.state == state, "dynamic avoidance does not draw random risk decisions")
	sheep.hunger = 50
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE and sheep._grass_unsafe(0), "lower hunger expands both threat and grass exclusion distance")
	_check(engine.grass_bites[0] == 3, "escaping interrupts grazing before food is consumed")
	wolf.position = Vector2(1100, 600)
	_step(15)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "safety memory delays feeding for half a second")
	_step(17)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "sheep resume feeding after reduced safety memory expires")
	sheep.hunger = 100
	wolf.position = Vector2(420, 240)
	wolf.begin_hunt(sheep)
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "high hunger narrows avoidance again without an encounter lottery")
	wolf.position = Vector2(375, 240)
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE and sheep.grass_target_index == -1, "emergency distance forces escape even at hunger 100")
	wolf.position = Vector2(420, 240)
	_step(32)
	sheep.position = Vector2(300, 240)
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.SEEK_FOOD and sheep.grass_target_index == 0, "hungry sheep can seek food inside the base but outside actual avoidance distance")

	_empty()
	_two_grass_points()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 80
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 240)) as WolfController
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.GRAZE, "hunger 80 permits grazing with a wolf 60 pixels away")
	_step(180)
	_check(sheep.hunger == 55 and sheep.current_behavior == AnimalController.Behavior.FLEE, "eating expands avoidance and interrupts the next bite")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 0
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(375, 240)) as WolfController
	engine.entity_service.rebuild_spatial_index()
	sheep.perceive(0.0)
	sheep.decide(1.0 / 60.0)
	_check(not wolf.hunting and sheep.current_behavior == AnimalController.Behavior.FLEE, "non-hunting wolf still triggers emergency escape")

func _verify_wolves() -> void:
	_empty()
	var sheep := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
	_step(29)
	_check(sheep.alive and wolf.hunting, "wolves hunt immediately but capture requires a full interval")
	_step(1)
	_check(not sheep.alive and engine.entity_service.capture_count == 1 and not wolf.hunting, "capture succeeds without a rest round")
	var replacement := _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	_step(1)
	_check(wolf.hunting and wolf.target == replacement, "capture is followed by immediate independent hunting")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
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
	for index in range(5):
		_animal(AnimalController.Kind.WOLF, Vector2(350, 240))
	_step(1)
	var active: int = 0
	for hunter in engine.entity_service.wolves:
		active += 1 if hunter.hunting else 0
	_check(active == 5, "independent wolves have no participation cap")
	_step(29)
	_check(engine.entity_service.capture_count == 1, "multiple wolves cannot capture the same sheep twice")

	_empty()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(500, 240)) as SheepController
	var other := _animal(AnimalController.Kind.SHEEP, Vector2(300, 240)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(400, 240)) as WolfController
	var competitor := _animal(AnimalController.Kind.WOLF, Vector2(400, 250)) as WolfController
	var unclaimed := wolf._prey_weight(sheep)
	competitor.begin_hunt(sheep)
	_check(is_equal_approx(wolf._prey_weight(sheep), unclaimed / 4.0) and is_equal_approx(wolf._prey_weight(other), unclaimed), "claimed prey weight drops while equal-distance alternatives retain weight")
	engine.entity_service.rebuild_spatial_index()
	engine.rng.seed = 1337
	var first_choices: Array[int] = []
	var claimed_count: int = 0
	for index in range(1000):
		wolf._choose_prey()
		first_choices.append(wolf.target.entity_id)
		if wolf.target == sheep:
			claimed_count += 1
	_check(claimed_count > 100 and claimed_count < 300, "weighted selection favors unclaimed prey without forbidding overlap")
	engine.rng.seed = 1337
	var repeated: Array[int] = []
	for index in range(1000):
		wolf._choose_prey()
		repeated.append(wolf.target.entity_id)
	_check(first_choices == repeated, "weighted choices reproduce with a fixed seed")
	wolf.begin_hunt(sheep)
	engine.config.wolf.hunt_duration = 0.1
	_step(8)
	_check(wolf.hunting and wolf.target == other, "timeout skips previous prey once when an alternative exists")
	other.position = Vector2(1100, 600)
	_step(1)
	_check(wolf.target == sheep, "out-of-range target is replaced")

	_empty()
	engine.config.perception_interval = 0.125
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(350, 240)) as WolfController
	_step(29)
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(800, 240)) as SheepdogController
	# 1) Move a dog after decisions to exercise post-movement capture protection.
	engine.entity_service.rebuild_spatial_index()
	wolf.update_hunt(1.0 / 60.0)
	wolf.perceive(1.0 / 60.0)
	wolf.decide(1.0 / 60.0)
	dog.position = Vector2(410, 240)
	wolf.resolve_interactions(1.0 / 60.0)
	_check(sheep.alive and wolf.capture_progress == 0.0 and not wolf.hunting, "dog arriving after perception interrupts capture")
	_step(1)
	_check(wolf.current_behavior == AnimalController.Behavior.FLEE, "near dog takes priority over searching")
	dog.position = Vector2(1100, 600)
	_step(1)
	_check(wolf.hunting, "wolf resumes hunting as soon as dog leaves")

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
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(820, 360)) as WolfController
	var dog := _animal(AnimalController.Kind.SHEEPDOG, Vector2(640, 360)) as SheepdogController
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
	_check(panel.editors.has("Sheep.hungry_threshold") and panel.editors.has("Wolves.competition_weight"), "CFG metadata generates species controls")
	_check(is_equal_approx(panel.editors["Wolves.hunt_duration"].value, engine.config.wolf.hunt_duration) and is_equal_approx(panel.editors["Grass.regrow_duration"].value, engine.config.grass.regrow_duration), "form steps preserve applied duration values exactly")
	panel.editors["Sheep.move_speed"].value = 31.0
	panel.editors["Sheep.move_speed"].get_line_edit().text = "31"
	_check(engine.config.sheep.move_speed == 0.0, "editing the form leaves live parameters unchanged")
	panel.apply_button.pressed.emit()
	engine._physics_process(0.0)
	_check(sheep.move_speed == 31.0 and engine.paused and engine.step_count == 0, "apply updates existing animals while paused without stepping")
	var second := _animal(AnimalController.Kind.SHEEP, Vector2(500, 200)) as SheepController
	_check(second.move_speed == 31.0, "new animals use applied parameters")
	_check(authored.sheep.move_speed == 70.0, "runtime changes do not overwrite authored CFG")
	sheep.hunger = 100
	_step(1)
	_check(sheep.velocity.length() > 0.0 and sheep.velocity.length() <= 31.001, "live speed change affects actual movement")

	panel.set_draft(engine.config)
	panel.editors["Sheep.full_threshold"].value = 80
	_check(panel.apply_button.disabled, "invalid hunger thresholds disable Apply")
	var invalid: Resource = engine.config.copy_config()
	invalid.sheep.full_threshold = 80
	_check(not engine.request_config_apply(invalid).is_empty() and engine.config.sheep.full_threshold == 20, "invalid config is rejected atomically")

	var changed: Resource = engine.config.copy_config()
	changed.initial_sheep = 3
	panel.set_draft(changed)
	_check(panel.apply_button.text == "Apply & restart", "structural changes explain the restart")
	panel.apply_button.pressed.emit()
	engine._physics_process(0.0)
	_check(engine.entity_service.get_counts() == Vector3i(3, 0, 0) and not engine.entity_service.entities.has(sheep), "population change recreates the simulation")
	_check(engine.paused and engine.step_count == 0, "restart preserves pause state")

	var path := "res://output/verification/runtime-config.tres"
	_check(engine.save_preset(path) == OK, "runtime preset saves")
	var loaded: Resource = engine.load_preset(path)
	_check(loaded != null and loaded.sheep.move_speed == 31.0 and loaded.initial_sheep == 3, "saved nested CFG round-trips")
	var legacy_path := "res://output/verification/legacy-preset.tres"
	var legacy: SimulationConfig = engine.config.copy_config()
	legacy.preset_version = 0
	ResourceSaver.save(legacy, legacy_path)
	_check(engine.load_preset(legacy_path) == null, "unversioned legacy presets are rejected even if omitted fields acquire new defaults")
	loaded.sheep.move_speed = 47.0
	_check(engine.config.sheep.move_speed == 31.0, "loaded preset is detached from live settings")
	panel._restore_defaults()
	_check(panel.draft.sheep.move_speed == 70.0 and engine.config.sheep.move_speed == 31.0, "defaults stage changes without applying")
	panel.close()

	_empty()
	_two_grass_points()
	sheep = _animal(AnimalController.Kind.SHEEP, Vector2(340, 240)) as SheepController
	sheep.hunger = 100
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(420, 240)) as WolfController
	_step(3)
	var chase_before: float = wolf.hunt_elapsed
	var changed_distance: Resource = engine.config.copy_config()
	changed_distance.sheep.emergency_distance = 90.0
	engine.request_config_apply(changed_distance)
	engine._physics_process(0.0)
	_check(sheep.hunger == 100 and wolf.hunt_elapsed == chase_before, "paused apply preserves hunger and elapsed chase")
	_check(is_equal_approx(sheep.avoidance_radius, 90.0), "applied distances recompute with existing hunger")
	_step(1)
	_check(sheep.current_behavior == AnimalController.Behavior.FLEE, "updated avoidance affects the next decision")
	var invalid_distance: Resource = engine.config.copy_config()
	invalid_distance.sheep.emergency_distance = 140.0
	_check(not engine.request_config_apply(invalid_distance).is_empty(), "emergency distance cannot exceed base avoidance radius")
	engine.grass_regrow_remaining[0] = 8.0
	engine.grass_bites[0] = 0
	var regrowth: Resource = engine.config.copy_config()
	regrowth.grass.regrow_duration = 1.0
	engine.request_config_apply(regrowth)
	engine._physics_process(0.0)
	_check(engine.grass_regrow_remaining[0] == 8.0, "apply preserves already sampled grass recovery")
	var bite_change: Resource = engine.config.copy_config()
	bite_change.grass.bites += 1
	panel.set_draft(bite_change)
	_check(panel.apply_button.text == "Apply & restart", "grass food capacity changes require restart")
	panel.close()

func _reference_prey_choice(wolf: WolfController) -> SheepController:
	var candidates: Array[SheepController] = []
	for sheep in engine.entity_service.sheep:
		if sheep.alive and wolf.global_position.distance_to(sheep.global_position) < wolf.perception_radius:
			candidates.append(sheep)
	if candidates.size() > 1:
		candidates.erase(wolf._timed_out_target)
	var weights: Array[float] = []
	var total: float = 0.0
	for sheep in candidates:
		var weight := wolf._prey_weight(sheep)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return null

	var choice: float = engine.rng.randf() * total
	for index in range(candidates.size()):
		choice -= weights[index]
		if choice < 0.0 or index == candidates.size() - 1:
			return candidates[index]
	return null

func _verify_spatial_prey_selection() -> void:
	_empty()
	var wolf := _animal(AnimalController.Kind.WOLF, Vector2(360, 360)) as WolfController
	_animal(AnimalController.Kind.SHEEPDOG, Vector2(360, 360))
	_animal(AnimalController.Kind.SHEEP, Vector2(620, 360))
	_animal(AnimalController.Kind.SHEEP, Vector2(610, 610))
	var dead := _animal(AnimalController.Kind.SHEEP, Vector2(370, 360)) as SheepController
	engine.entity_service.rebuild_spatial_index()
	dead.die()
	var empty_state: int = engine.rng.state
	wolf._choose_prey()
	_check(wolf.target == null and engine.rng.state == empty_state, "prey selection excludes other species, newly dead sheep, circle exterior and exact radius without consuming RNG")
	var inside := _animal(AnimalController.Kind.SHEEP, Vector2(619.99, 360)) as SheepController
	engine.entity_service.rebuild_spatial_index()
	wolf._timed_out_target = inside
	wolf._choose_prey()
	_check(wolf.target == inside and wolf._timed_out_target == null, "prey just inside radius remains eligible when it is the only timed-out target")
	inside.position = Vector2(119, 360)
	engine.entity_service.rebuild_spatial_index()
	wolf.leave_hunt()
	wolf._choose_prey()
	_check(wolf.target == inside, "prey selection crosses cell boundaries after index rebuild")
	inside.position = Vector2(30, 360)
	engine.entity_service.rebuild_spatial_index()
	wolf.leave_hunt()
	wolf._choose_prey()
	_check(wolf.target == null, "moved prey outside query cells is excluded after index rebuild")
	_empty()
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(360, 360)) as WolfController
	engine.entity_service.rebuild_spatial_index()
	empty_state = engine.rng.state
	wolf._choose_prey()
	_check(wolf.target == null and engine.rng.state == empty_state, "empty prey query leaves target and RNG unchanged")

	_empty()
	var right := _animal(AnimalController.Kind.SHEEP, Vector2(550, 360)) as SheepController
	wolf = _animal(AnimalController.Kind.WOLF, Vector2(360, 360)) as WolfController
	var left := _animal(AnimalController.Kind.SHEEP, Vector2(119, 360)) as SheepController
	var competitor := _animal(AnimalController.Kind.WOLF, Vector2(400, 360)) as WolfController
	_animal(AnimalController.Kind.SHEEP, Vector2(360, 200))
	var second_competitor := _animal(AnimalController.Kind.WOLF, Vector2(390, 350)) as WolfController
	competitor.begin_hunt(right)
	second_competitor.begin_hunt(right)
	engine.entity_service.rebuild_spatial_index()
	for seed_value in [1, 1337, 987654]:
		engine.rng.seed = seed_value
		var matching := true
		for index in range(128):
			wolf.leave_hunt()
			wolf._timed_out_target = right if index % 3 == 0 else left if index % 3 == 1 else null
			var before_state: int = engine.rng.state
			var expected := _reference_prey_choice(wolf)
			var expected_state: int = engine.rng.state
			engine.rng.state = before_state
			wolf._choose_prey()
			matching = matching and wolf.target == expected and engine.rng.state == expected_state and wolf._timed_out_target == null
		_check(matching, "spatial prey sequence and RNG match full scan with competition and timeout, seed %d" % seed_value)

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
	_verify_resources_and_lifecycle()
	_verify_sheep_and_grass()
	_verify_threats()
	_verify_wolves()
	_verify_spatial_prey_selection()
	_verify_dogs()
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


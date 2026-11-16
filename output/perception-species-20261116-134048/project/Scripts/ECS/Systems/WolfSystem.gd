class_name WolfSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func accumulate_sheep_pressure() -> void:
	g_gameplayEngine.grid_service.accumulate_pressure(AnimalEntity.Kind.WOLF)

func find_dog(animal: AnimalEntity, radius: float) -> AnimalEntity:
	var row := animal.row
	var result: AnimalEntity
	var best := radius
	for dog_row in g_gameplayEngine.entity_service.dog_rows:
		var dog := data.handles[dog_row]
		if not data.identity_alive[dog.row]:
			continue
		var distance := data.motion_position[row].distance_to(data.motion_position[dog.row])
		if distance < best or (is_equal_approx(distance, best) and result != null and data.identity_entity_id[dog.row] < data.identity_entity_id[result.row]):
			result = dog
			best = distance
	return result

func perceive(animal: AnimalEntity, delta: float) -> void:
	var wolf_resting := data.wolf_resting
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	for index in range(4):
		data.wolf_strategy_failures[row][index] = maxf(0.0, data.wolf_strategy_failures[row][index] - settings.strategy_decay * delta)
	data.wolf_howl_elapsed[row] += delta
	if wolf_resting[row]:
		data.wolf_rest_elapsed[row] += delta
		wolf_resting[row] = int(data.wolf_rest_elapsed[row] < settings.rest_duration)
	data.wolf_nearest_threat[row] = find_dog(animal, settings.dog_threat_distance * (2.0 if data.wolf_retreating[row] else 1.0))
	if data.wolf_hunting[row]:
		data.wolf_hunt_elapsed[row] += delta
		common.observe_target(animal, delta)
		if not common.is_live(animal, data.live(data.memory_target[row])) or data.wolf_hunt_elapsed[row] >= settings.hunt_duration or (not data.memory_target_visible[row] and data.memory_unseen_elapsed[row] >= settings.memory_duration):
			end_hunt(animal, false)
	if not data.wolf_hunting[row] and not wolf_resting[row] and not common.is_live(animal, data.live(data.wolf_nearest_threat[row])) and not data.wolf_retreating[row]:
		_choose_prey(animal)

func _choose_prey(animal: AnimalEntity) -> void:
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var best: AnimalEntity
	var distance: float = INF
	var service: GridService = g_gameplayEngine.grid_service
	for index in service.get_nearby_indices(data.motion_position[row], settings.perception_radius, AnimalEntity.Kind.SHEEP):
		if service.perception_kinds[index] != AnimalEntity.Kind.SHEEP:
			continue
		var point := service.perception_positions[index]
		if not common.can_see(animal, point):
			continue
		var candidate := data.handles[index] as AnimalEntity
		var next_distance := data.motion_position[row].distance_squared_to(point)
		if next_distance < distance or (is_equal_approx(next_distance, distance) and best != null and data.identity_entity_id[candidate.row] < data.identity_entity_id[best.row]):
			best = candidate
			distance = next_distance
	if best != null:
		begin_hunt(animal, best)
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("WolfTarget", started)

func begin_hunt(animal: AnimalEntity, prey: AnimalEntity) -> void:
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	data.memory_target[row] = prey
	data.wolf_hunting[row] = 1
	data.wolf_hunt_elapsed[row] = 0.0
	data.wolf_charging[row] = 0
	data.wolf_howled[row] = 0
	var total: float = 0.0
	for index in range(4):
		total += 1.0 / (1.0 + data.wolf_strategy_failures[row][index])
	var choice: float = g_gameplayEngine.rng.randf() * total
	for index in range(4):
		choice -= 1.0 / (1.0 + data.wolf_strategy_failures[row][index])
		if choice <= 0.0 or index == 4 - 1:
			data.wolf_strategy[row] = index
			break
	common.observe_target(animal, 0.0)

func end_hunt(animal: AnimalEntity, success: bool) -> void:
	var row := animal.row
	if not data.wolf_hunting[row]:
		return
	data.wolf_strategy_failures[row][data.wolf_strategy[row]] = maxf(0.0, data.wolf_strategy_failures[row][data.wolf_strategy[row]] + (-1.5 if success else 1.0))
	data.wolf_hunting[row] = 0
	data.wolf_charging[row] = 0
	data.memory_target[row] = null
	data.memory_target_visible[row] = 0
	data.wolf_resting[row] = 1
	data.wolf_rest_elapsed[row] = 0.0

func can_charge(animal: AnimalEntity) -> bool:
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	return data.wolf_hunting[row] and data.memory_target_visible[row] and (data.wolf_charging[row] or data.motion_position[row].distance_to(data.memory_last_seen_position[row]) <= settings.capture_distance * settings.charge_distance_scale)

func resolve_interactions(animal: AnimalEntity, _delta: float) -> void:
	var memory_target := data.memory_target
	var motion_position := data.motion_position
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if data.wolf_howl_pending[row]:
		data.wolf_howl_pending[row] = 0
		g_gameplayEngine.debug_service.record_howl(animal)
		for sheep_row in g_gameplayEngine.entity_service.sheep_rows:
			var sheep := data.handles[sheep_row]
			if data.identity_alive[sheep.row] and motion_position[row].distance_to(motion_position[sheep.row]) <= settings.howl_radius:
				g_gameplayEngine.sheep_system.receive_howl(sheep, motion_position[row])
	if not data.wolf_hunting[row] or data.brain_current_behavior[row] != AnimalEntity.Behavior.CHASE:
		return
	if not common.is_live(animal, data.live(memory_target[row])):
		end_hunt(animal, false)
		return
	data.wolf_nearest_threat[row] = find_dog(animal, settings.dog_threat_distance)
	if common.is_live(animal, data.live(data.wolf_nearest_threat[row])):
		end_hunt(animal, false)
		data.wolf_retreating[row] = 1
		return
	if common.can_see(animal, motion_position[data.live(memory_target[row]).row]) and motion_position[row].distance_to(motion_position[data.live(memory_target[row]).row]) <= settings.capture_distance:
		if g_gameplayEngine.entity_service.capture(data.live(memory_target[row])):
			end_hunt(animal, true)

func prepare_motion_goals() -> void:
	var settings: WolfConfig = g_gameplayEngine.config.wolf
	var common: AnimalSystem = g_gameplayEngine.animal_system
	for row in g_gameplayEngine.entity_service.wolf_rows:
		if data.motion_intent[row] != AnimalData.MotionIntent.POINT:
			continue
		match data.brain_current_behavior[row]:
			AnimalEntity.Behavior.STALK:
				var point := data.motion_movement_goal[row]
				var direction := data.memory_last_seen_velocity[row].normalized()
				if direction.is_zero_approx():
					direction = Vector2.RIGHT
				match data.wolf_strategy[row]:
					AnimalEntity.Strategy.SIDE:
						point += direction.orthogonal() * settings.strategy_offset
					AnimalEntity.Strategy.REAR:
						point -= direction * settings.strategy_offset
				data.motion_movement_goal[row] = common.clamp_to_arena(data.handles[row], point)
			AnimalEntity.Behavior.RETREAT:
				var threat := data.live(data.wolf_nearest_threat[row])
				if threat != null:
					var away := (data.motion_position[row] - data.motion_position[threat.row]).normalized()
					if away.is_zero_approx():
						away = data.motion_facing[row]
					data.motion_movement_goal[row] = data.motion_position[row] + away * 100.0

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	return "%s | Hunt %.1f s | Unseen %.1f s | Failures %s" % [AnimalEntity.STRATEGY_NAMES[data.wolf_strategy[row]], data.wolf_hunt_elapsed[row], data.memory_unseen_elapsed[row], data.wolf_strategy_failures[row]]

class_name WolfSystem
extends RefCounted

func find_dog(animal: AnimalEntity, radius: float) -> AnimalEntity:
	var data: AnimalData = g_gameplayEngine.entity_service.data
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
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	for index in range(data.wolf_strategy_failures[row].size()):
		data.wolf_strategy_failures[row][index] = maxf(0.0, data.wolf_strategy_failures[row][index] - settings.strategy_decay * delta)
	data.wolf_howl_elapsed[row] += delta
	if data.wolf_resting[row]:
		data.wolf_rest_elapsed[row] += delta
		data.wolf_resting[row] = data.wolf_rest_elapsed[row] < settings.rest_duration
	data.wolf_nearest_threat[row] = find_dog(animal, settings.dog_threat_distance * (2.0 if data.wolf_retreating[row] else 1.0))
	if data.wolf_hunting[row]:
		data.wolf_hunt_elapsed[row] += delta
		common.observe_target(animal, delta)
		if not common.is_live(animal, data.live(data.memory_target[row])) or data.wolf_hunt_elapsed[row] >= settings.hunt_duration or (not data.memory_target_visible[row] and data.memory_unseen_elapsed[row] >= settings.memory_duration):
			end_hunt(animal, false)
	if not data.wolf_hunting[row] and not data.wolf_resting[row] and not common.is_live(animal, data.live(data.wolf_nearest_threat[row])) and not data.wolf_retreating[row]:
		_choose_prey(animal)

func _choose_prey(animal: AnimalEntity) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var best: AnimalEntity
	var distance: float = INF
	var service: EntityService = g_gameplayEngine.entity_service
	for index in service.get_nearby_indices(data.motion_position[row], settings.perception_radius):
		if service.perception_kinds[index] != AnimalEntity.Kind.SHEEP:
			continue
		var point := service.perception_positions[index]
		if not common.can_see(animal, point):
			continue
		var candidate := service.entities[index] as AnimalEntity
		var next_distance := data.motion_position[row].distance_squared_to(point)
		if next_distance < distance or (is_equal_approx(next_distance, distance) and best != null and data.identity_entity_id[candidate.row] < data.identity_entity_id[best.row]):
			best = candidate
			distance = next_distance
	if best != null:
		begin_hunt(animal, best)
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("WolfTarget", started)

func begin_hunt(animal: AnimalEntity, prey: AnimalEntity) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	data.memory_target[row] = prey
	data.wolf_hunting[row] = true
	data.wolf_hunt_elapsed[row] = 0.0
	data.wolf_charging[row] = false
	data.wolf_howled[row] = false
	var total: float = 0.0
	for failures in data.wolf_strategy_failures[row]:
		total += 1.0 / (1.0 + failures)
	var choice: float = g_gameplayEngine.rng.randf() * total
	for index in range(data.wolf_strategy_failures[row].size()):
		choice -= 1.0 / (1.0 + data.wolf_strategy_failures[row][index])
		if choice <= 0.0 or index == data.wolf_strategy_failures[row].size() - 1:
			data.wolf_strategy[row] = index
			break
	common.observe_target(animal, 0.0)

func end_hunt(animal: AnimalEntity, success: bool) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	if not data.wolf_hunting[row]:
		return
	data.wolf_strategy_failures[row][data.wolf_strategy[row]] = maxf(0.0, data.wolf_strategy_failures[row][data.wolf_strategy[row]] + (-1.5 if success else 1.0))
	data.wolf_hunting[row] = false
	data.wolf_charging[row] = false
	data.memory_target[row] = null
	data.memory_target_visible[row] = false
	data.wolf_resting[row] = true
	data.wolf_rest_elapsed[row] = 0.0

func can_charge(animal: AnimalEntity) -> bool:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	return data.wolf_hunting[row] and data.memory_target_visible[row] and (data.wolf_charging[row] or data.motion_position[row].distance_to(data.memory_last_seen_position[row]) <= settings.capture_distance * settings.charge_distance_scale)

func resolve_interactions(animal: AnimalEntity, _delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if data.wolf_howl_pending[row]:
		data.wolf_howl_pending[row] = false
		g_gameplayEngine.debug_service.record_howl(animal)
		for sheep_row in g_gameplayEngine.entity_service.sheep_rows:
			var sheep := data.handles[sheep_row]
			if data.identity_alive[sheep.row] and data.motion_position[row].distance_to(data.motion_position[sheep.row]) <= settings.howl_radius:
				g_gameplayEngine.sheep_system.receive_howl(sheep, data.motion_position[row])
	if not data.wolf_hunting[row] or data.brain_current_behavior[row] != AnimalEntity.Behavior.CHASE:
		return
	if not common.is_live(animal, data.live(data.memory_target[row])):
		end_hunt(animal, false)
		return
	data.wolf_nearest_threat[row] = find_dog(animal, settings.dog_threat_distance)
	if common.is_live(animal, data.live(data.wolf_nearest_threat[row])):
		end_hunt(animal, false)
		data.wolf_retreating[row] = true
		return
	if common.can_see(animal, data.motion_position[data.live(data.memory_target[row]).row]) and data.motion_position[row].distance_to(data.motion_position[data.live(data.memory_target[row]).row]) <= settings.capture_distance:
		if g_gameplayEngine.entity_service.capture(data.live(data.memory_target[row])):
			end_hunt(animal, true)

func get_debug_details(animal: AnimalEntity) -> String:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	return "%s | Hunt %.1f s | Unseen %.1f s | Failures %s" % [AnimalEntity.STRATEGY_NAMES[data.wolf_strategy[row]], data.wolf_hunt_elapsed[row], data.memory_unseen_elapsed[row], data.wolf_strategy_failures[row]]

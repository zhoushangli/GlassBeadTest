class_name AnimalSystem
extends RefCounted

func is_live(animal: AnimalEntity, other: AnimalEntity) -> bool:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	return is_instance_valid(other) and data.identity_alive[other.row]

func can_see(animal: AnimalEntity, point: Vector2) -> bool:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var offset := point - data.motion_position[row]
	if offset.length_squared() > data.memory_vision_radius_squared[row]:
		return false
	return offset.is_zero_approx() or data.motion_facing[row].dot(offset.normalized()) + 0.000001 >= data.memory_vision_cos[row]

func observe_target(animal: AnimalEntity, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var target := data.live(data.memory_target[row])
	if target == null:
		data.memory_target_visible[row] = false
		data.memory_unseen_elapsed[row] = 0.0
		return
	data.memory_target_visible[row] = can_see(animal, data.motion_position[target.row])
	if data.memory_target_visible[row]:
		data.memory_last_seen_position[row] = data.motion_position[target.row]
		data.memory_last_seen_velocity[row] = data.motion_velocity[target.row]
		data.memory_unseen_elapsed[row] = 0.0
	else:
		data.memory_unseen_elapsed[row] += delta

func perceive(animal: AnimalEntity, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.motion_wander_remaining[row] -= delta
	data.memory_perception_remaining[row] -= delta
	if not data.memory_perception_ready[row] or data.memory_perception_remaining[row] <= 0.0:
		var service: EntityService = g_gameplayEngine.entity_service
		data.memory_nearby[row] = service.get_nearby_indices(data.motion_position[row], _get_query_radius(animal))
		var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
		_scan_separation(animal, service)
		if g_gameplayEngine.profile_service.detailed_stats_enabled:
			g_gameplayEngine.profile_service.record_hotspot("Separation", started)
			started = Time.get_ticks_usec()
		if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
			g_gameplayEngine.sheep_system._scan_neighbors(animal, service)
		if g_gameplayEngine.profile_service.detailed_stats_enabled:
			g_gameplayEngine.profile_service.record_hotspot("NeighborScan", started)
		data.memory_perception_remaining[row] = g_gameplayEngine.config.perception_interval
		if not data.memory_perception_ready[row]:
			data.memory_perception_remaining[row] *= fmod(data.identity_entity_id[row] * 0.618034, 1.0)
		data.memory_perception_ready[row] = true

func _get_query_radius(animal: AnimalEntity) -> float:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: Resource = data.settings[row]
	var radius := maxf(settings.perception_radius, g_gameplayEngine.config.separation_distance)
	if data.identity_kind[row] == AnimalEntity.Kind.SHEEP:
		radius = maxf(radius, maxf(settings.flock_radius, settings.alignment_radius))
	return radius

func _scan_separation(animal: AnimalEntity, service: EntityService) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.motion_separation[row] = Vector2.ZERO
	var distance_limit: float = g_gameplayEngine.config.separation_distance
	if distance_limit <= 0.0:
		return

	for index in data.memory_nearby[row]:
		if index == data.memory_perception_index[row] or service.perception_kinds[index] != data.identity_kind[row]:
			continue

		var offset := data.motion_position[row] - service.perception_positions[index]
		var distance_squared := offset.length_squared()
		if distance_squared >= distance_limit * distance_limit:
			continue

		var distance := sqrt(distance_squared)
		var direction := offset.normalized()
		if distance < 0.001:
			direction = Vector2.RIGHT if data.identity_entity_id[row] < data.identity_entity_id[service.entities[index].row] else Vector2.LEFT
		data.motion_separation[row] += direction * (1.0 - distance / distance_limit)

func decide(animal: AnimalEntity, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: Resource = data.settings[row]
	data.motion_desired_velocity[row] = Vector2.ZERO
	data.motion_speed_limit[row] = settings.move_speed
	data.brain_player[row].update(delta)

func get_wander_point(animal: AnimalEntity, distance: float) -> Vector2:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	if data.motion_wander_remaining[row] <= 0.0 or data.motion_position[row].distance_to(data.motion_wander_point[row]) < 15.0:
		var direction := Vector2.from_angle(g_gameplayEngine.rng.randf_range(-PI, PI))
		data.motion_wander_point[row] = clamp_to_arena(animal, data.motion_position[row] + direction * distance)
		data.motion_wander_remaining[row] = g_gameplayEngine.rng.randf_range(1.5, 3.5)
	return data.motion_wander_point[row]

func clamp_to_arena(animal: AnimalEntity, point: Vector2) -> Vector2:
	return point.clamp(Vector2(12.0, 94.0), g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0))

func move_towards(animal: AnimalEntity, point: Vector2, speed: float, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.motion_movement_goal[row] = point
	data.motion_speed_limit[row] = speed
	var difference := point - data.motion_position[row]
	data.motion_desired_velocity[row] = difference.normalized() * minf(speed, difference.length() / maxf(delta, 0.00001))

func submit_velocity(animal: AnimalEntity, desired: Vector2, speed: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.motion_desired_velocity[row] = desired
	data.motion_speed_limit[row] = speed
	data.motion_movement_goal[row] = data.motion_position[row] + data.motion_desired_velocity[row]

func separation_velocity(animal: AnimalEntity) -> Vector2:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: Resource = data.settings[row]
	return Vector2.ZERO if data.identity_kind[row] == AnimalEntity.Kind.SHEEP else data.motion_separation[row] * settings.move_speed

func move(animal: AnimalEntity, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	if not data.identity_alive[row]:
		return

	var previous := data.motion_position[row]
	data.motion_velocity[row] = (data.motion_desired_velocity[row] + separation_velocity(animal)).limit_length(data.motion_speed_limit[row])
	data.motion_position[row] = clamp_to_arena(animal, data.motion_position[row] + data.motion_velocity[row] * delta)
	data.motion_velocity[row] = (data.motion_position[row] - previous) / maxf(delta, 0.00001)
	if not data.motion_velocity[row].is_zero_approx():
		data.motion_facing[row] = data.motion_velocity[row].normalized()

func set_behavior(animal: AnimalEntity, behavior: AnimalEntity.Behavior) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.brain_current_behavior[row] = behavior

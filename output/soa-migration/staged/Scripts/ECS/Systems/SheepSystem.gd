class_name SheepSystem
extends RefCounted

func _scan_neighbors(animal: AnimalEntity, service: EntityService) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	data.sheep_local_flock_center[row] = Vector2.ZERO
	data.sheep_alignment[row] = Vector2.ZERO
	data.sheep_neighbor_count[row] = 0
	var aligned: int = 0
	for index in data.memory_nearby[row]:
		if index == data.memory_perception_index[row] or service.perception_kinds[index] != AnimalEntity.Kind.SHEEP:
			continue
		var distance := data.motion_position[row].distance_to(service.perception_positions[index])
		if distance < settings.flock_radius:
			data.sheep_local_flock_center[row] += service.perception_positions[index]
			data.sheep_neighbor_count[row] += 1
		if distance < settings.alignment_radius:
			data.sheep_alignment[row] += service.perception_velocities[index]
			aligned += 1
	data.sheep_local_flock_center[row] = data.sheep_local_flock_center[row] / data.sheep_neighbor_count[row] if data.sheep_neighbor_count[row] > 0 else data.motion_position[row]
	if aligned > 0:
		data.sheep_alignment[row] /= aligned

func receive_howl(animal: AnimalEntity, source: Vector2) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	data.sheep_panic_source[row] = source
	data.sheep_panic_elapsed[row] = 0.0
	data.sheep_has_panic[row] = true
	data.sheep_has_alert[row] = true
	data.sheep_alert_elapsed[row] = 0.0

func perceive(animal: AnimalEntity, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	data.sheep_threatened[row] = false
	data.sheep_threat_direction[row] = Vector2.ZERO
	data.sheep_dog_pressure[row] = Vector2.ZERO
	var service: EntityService = g_gameplayEngine.entity_service
	for index in service.get_nearby_indices(data.motion_position[row], maxf(settings.perception_radius, settings.herding_distance)):
		var kind: int = service.perception_kinds[index]
		if kind != AnimalEntity.Kind.WOLF and kind != AnimalEntity.Kind.SHEEPDOG:
			continue
		var point := service.perception_positions[index]
		var offset := data.motion_position[row] - point
		var distance := offset.length()
		match kind:
			AnimalEntity.Kind.WOLF:
				if distance <= settings.emergency_distance or common.can_see(animal, point):
					data.sheep_threatened[row] = true
					data.sheep_threat_direction[row] += offset.normalized() / maxf(distance, 1.0)
			AnimalEntity.Kind.SHEEPDOG:
				if distance < settings.herding_distance:
					data.sheep_dog_pressure[row] += offset.normalized() * (1.0 - distance / settings.herding_distance)
	if data.sheep_has_panic[row]:
		data.sheep_panic_elapsed[row] += delta
		data.sheep_has_panic[row] = data.sheep_panic_elapsed[row] < settings.panic_duration
		if data.sheep_has_panic[row]:
			data.sheep_threat_direction[row] += (data.motion_position[row] - data.sheep_panic_source[row]).normalized()
	if data.sheep_threatened[row] or data.sheep_has_panic[row]:
		data.sheep_has_alert[row] = true
		data.sheep_alert_elapsed[row] = 0.0
	else:
		data.sheep_alert_elapsed[row] += delta
		data.sheep_has_alert[row] = data.sheep_has_alert[row] and data.sheep_alert_elapsed[row] < settings.alert_duration
	if (data.sheep_threatened[row] or data.sheep_has_panic[row]) and data.sheep_threat_direction[row].is_zero_approx():
		data.sheep_threat_direction[row] = Vector2.from_angle(data.identity_entity_id[row] * 2.399963)

func get_flock_velocity(animal: AnimalEntity) -> Vector2:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	var cohesion := (data.sheep_local_flock_center[row] - data.motion_position[row]).normalized() if data.sheep_neighbor_count[row] > 0 else Vector2.ZERO
	return data.sheep_alignment[row] * settings.alignment_weight + cohesion * settings.move_speed * settings.cohesion_weight

func apply_steering(animal: AnimalEntity, steering: Vector2, flock: Vector2, speed: float, delta: float) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	steering += flock + data.motion_separation[row] * settings.move_speed * settings.separation_weight
	var margin: float = 40.0
	var lower := Vector2(12.0, 94.0) + Vector2.ONE * margin
	var upper: Vector2 = g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0) - Vector2.ONE * margin
	var boundary := (lower - data.motion_position[row]).max(Vector2.ZERO) - (data.motion_position[row] - upper).max(Vector2.ZERO)
	steering += boundary / margin * speed * 2.0
	var desired := data.motion_velocity[row].lerp(steering.limit_length(speed), minf(1.0, settings.steering_rate * delta))
	common.submit_velocity(animal, desired, speed)

func get_debug_details(animal: AnimalEntity) -> String:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	return "Neighbors %d | Alert %.1f s | Panic %.1f s" % [data.sheep_neighbor_count[row], maxf(0.0, settings.alert_duration - data.sheep_alert_elapsed[row]) if data.sheep_has_alert[row] else 0.0, maxf(0.0, settings.panic_duration - data.sheep_panic_elapsed[row]) if data.sheep_has_panic[row] else 0.0]

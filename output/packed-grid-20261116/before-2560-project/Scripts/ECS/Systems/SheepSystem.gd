class_name SheepSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func _scan_neighbors(animal: AnimalEntity, service: EntityService) -> void:
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	var position := data.motion_position[row]
	var positions := service.perception_positions
	var velocities := service.perception_velocities
	var kinds := service.perception_kinds
	var center := Vector2.ZERO
	var alignment := Vector2.ZERO
	var count: int = 0
	var aligned: int = 0
	for index in data.memory_nearby[row]:
		if index == row or kinds[index] != AnimalEntity.Kind.SHEEP:
			continue
		var distance := position.distance_to(positions[index])
		if distance < settings.flock_radius:
			center += positions[index]
			count += 1
		if distance < settings.alignment_radius:
			alignment += velocities[index]
			aligned += 1
	data.sheep_local_flock_center[row] = center / count if count > 0 else position
	data.sheep_neighbor_count[row] = count
	data.sheep_alignment[row] = alignment / aligned if aligned > 0 else Vector2.ZERO

func receive_howl(animal: AnimalEntity, source: Vector2) -> void:
	var row := animal.row
	data.sheep_panic_source[row] = source
	data.sheep_panic_elapsed[row] = 0.0
	data.sheep_has_panic[row] = 1
	data.sheep_has_alert[row] = 1
	data.sheep_alert_elapsed[row] = 0.0

func perceive(animal: AnimalEntity, delta: float) -> void:
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	var position := data.motion_position[row]
	var threatened := false
	var threat_direction := Vector2.ZERO
	var dog_pressure := Vector2.ZERO
	var service: EntityService = g_gameplayEngine.entity_service
	var positions := service.perception_positions
	var kinds := service.perception_kinds
	for index in service.get_nearby_indices(position, maxf(settings.perception_radius, settings.herding_distance)):
		var kind: int = kinds[index]
		if kind != AnimalEntity.Kind.WOLF and kind != AnimalEntity.Kind.SHEEPDOG:
			continue
		var point := positions[index]
		var offset := position - point
		var distance := offset.length()
		match kind:
			AnimalEntity.Kind.WOLF:
				if distance <= settings.emergency_distance or common.can_see(animal, point):
					threatened = true
					threat_direction += offset.normalized() / maxf(distance, 1.0)
			AnimalEntity.Kind.SHEEPDOG:
				if distance < settings.herding_distance:
					dog_pressure += offset.normalized() * (1.0 - distance / settings.herding_distance)
	var panic_elapsed := data.sheep_panic_elapsed[row]
	var has_panic: bool = data.sheep_has_panic[row] != 0
	if has_panic:
		panic_elapsed += delta
		has_panic = panic_elapsed < settings.panic_duration
		if has_panic:
			threat_direction += (position - data.sheep_panic_source[row]).normalized()
	var alert_elapsed := data.sheep_alert_elapsed[row]
	var has_alert: bool = data.sheep_has_alert[row] != 0
	if threatened or has_panic:
		has_alert = true
		alert_elapsed = 0.0
	else:
		alert_elapsed += delta
		has_alert = has_alert and alert_elapsed < settings.alert_duration
	if (threatened or has_panic) and threat_direction.is_zero_approx():
		threat_direction = Vector2.from_angle(data.identity_entity_id[row] * 2.399963)
	data.sheep_threatened[row] = int(threatened)
	data.sheep_threat_direction[row] = threat_direction
	data.sheep_dog_pressure[row] = dog_pressure
	data.sheep_panic_elapsed[row] = panic_elapsed
	data.sheep_has_panic[row] = int(has_panic)
	data.sheep_alert_elapsed[row] = alert_elapsed
	data.sheep_has_alert[row] = int(has_alert)

func get_flock_velocity(animal: AnimalEntity) -> Vector2:
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	var cohesion := (data.sheep_local_flock_center[row] - data.motion_position[row]).normalized() if data.sheep_neighbor_count[row] > 0 else Vector2.ZERO
	return data.sheep_alignment[row] * settings.alignment_weight + cohesion * settings.move_speed * settings.cohesion_weight

func apply_steering(animal: AnimalEntity, steering: Vector2, flock: Vector2, speed: float, delta: float) -> void:
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
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	return "Neighbors %d | Alert %.1f s | Panic %.1f s" % [data.sheep_neighbor_count[row], maxf(0.0, settings.alert_duration - data.sheep_alert_elapsed[row]) if data.sheep_has_alert[row] else 0.0, maxf(0.0, settings.panic_duration - data.sheep_panic_elapsed[row]) if data.sheep_has_panic[row] else 0.0]

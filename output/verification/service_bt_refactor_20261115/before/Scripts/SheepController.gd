class_name SheepController
extends AnimalController

var settings: SheepConfig
var local_flock_center := Vector2.ZERO
var neighbor_count: int = 0
var alignment := Vector2.ZERO
var threat_direction := Vector2.ZERO
var dog_pressure := Vector2.ZERO
var alert_elapsed: float = 0.0
var panic_elapsed: float = 0.0
var has_alert: bool = false
var has_panic: bool = false
var panic_source := Vector2.ZERO
var threatened: bool = false

func refresh_config() -> void:
	settings = gameplay_engine.config.sheep
	movement_config = settings
	super.refresh_config()

func _get_query_radius() -> float:
	return maxf(super._get_query_radius(), maxf(settings.flock_radius, settings.alignment_radius))

func _scan_neighbors(service: EntityService) -> void:
	local_flock_center = Vector2.ZERO
	alignment = Vector2.ZERO
	neighbor_count = 0
	var aligned: int = 0
	for index in _nearby:
		if index == perception_index or service.perception_kinds[index] != Kind.SHEEP:
			continue
		var distance := global_position.distance_to(service.perception_positions[index])
		if distance < settings.flock_radius:
			local_flock_center += service.perception_positions[index]
			neighbor_count += 1
		if distance < settings.alignment_radius:
			alignment += service.perception_velocities[index]
			aligned += 1
	local_flock_center = local_flock_center / neighbor_count if neighbor_count > 0 else global_position
	if aligned > 0:
		alignment /= aligned

func receive_howl(source: Vector2) -> void:
	panic_source = source
	panic_elapsed = 0.0
	has_panic = true
	has_alert = true
	alert_elapsed = 0.0

func perceive(delta: float) -> void:
	super.perceive(delta)
	threatened = false
	threat_direction = Vector2.ZERO
	dog_pressure = Vector2.ZERO
	var service: EntityService = gameplay_engine.entity_service
	for index in service.get_nearby_indices(global_position, maxf(perception_radius, settings.herding_distance)):
		var kind: int = service.perception_kinds[index]
		if kind != Kind.WOLF and kind != Kind.SHEEPDOG:
			continue
		var point := service.perception_positions[index]
		var offset := global_position - point
		var distance := offset.length()
		match kind:
			Kind.WOLF:
				if distance <= settings.emergency_distance or can_see(point):
					threatened = true
					threat_direction += offset.normalized() / maxf(distance, 1.0)
			Kind.SHEEPDOG:
				if distance < settings.herding_distance:
					dog_pressure += offset.normalized() * (1.0 - distance / settings.herding_distance)
	if has_panic:
		panic_elapsed += delta
		has_panic = panic_elapsed < settings.panic_duration
		if has_panic:
			threat_direction += (global_position - panic_source).normalized()
	if threatened or has_panic:
		has_alert = true
		alert_elapsed = 0.0
	else:
		alert_elapsed += delta
		has_alert = has_alert and alert_elapsed < settings.alert_duration
	if (threatened or has_panic) and threat_direction.is_zero_approx():
		threat_direction = Vector2.from_angle(entity_id * 2.399963)
	bt_player.blackboard.set_var(&"threat", threatened or has_panic)
	bt_player.blackboard.set_var(&"alert", has_alert)
	bt_player.blackboard.set_var(&"herded", not dog_pressure.is_zero_approx())

func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	var cohesion := (local_flock_center - global_position).normalized() if neighbor_count > 0 else Vector2.ZERO
	var flock := alignment * settings.alignment_weight + cohesion * move_speed * settings.cohesion_weight
	var steering := Vector2.ZERO
	_speed_limit = move_speed
	match behavior:
		Behavior.FLOCK:
			_update_wander(85.0)
			steering = (_wander_point - global_position).normalized() * move_speed * settings.idle_speed_scale
			flock *= settings.idle_flock_scale
		Behavior.ALERT:
			flock *= settings.alert_flock_scale
		Behavior.HERDED:
			steering = dog_pressure * move_speed * settings.dog_pressure_weight
		Behavior.FLEE:
			_speed_limit = settings.flee_speed
			steering = threat_direction.normalized() * settings.flee_speed * settings.wolf_pressure_weight
			flock *= 0.25
	steering += flock + separation * move_speed * settings.separation_weight
	var margin: float = 40.0
	var lower := Vector2(12.0, 94.0) + Vector2.ONE * margin
	var upper: Vector2 = gameplay_engine.config.arena_size - Vector2(12.0, 58.0) - Vector2.ONE * margin
	var boundary := (lower - global_position).max(Vector2.ZERO) - (global_position - upper).max(Vector2.ZERO)
	steering += boundary / margin * _speed_limit * 2.0
	desired_velocity = velocity.lerp(steering.limit_length(_speed_limit), minf(1.0, settings.steering_rate * delta))
	movement_goal = global_position + desired_velocity

func separation_velocity() -> Vector2:
	return Vector2.ZERO

func get_debug_details() -> String:
	return "Neighbors %d | Alert %.1f s | Panic %.1f s" % [neighbor_count, maxf(0.0, settings.alert_duration - alert_elapsed) if has_alert else 0.0, maxf(0.0, settings.panic_duration - panic_elapsed) if has_panic else 0.0]

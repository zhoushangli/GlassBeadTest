class_name SheepdogController
extends AnimalController

var settings: SheepdogConfig
var protected_sheep: SheepController
var collected_sheep: SheepController
var protection_center := Vector2.ZERO
var guard_point := Vector2.ZERO
var wolf_candidates: Array[AnimalController] = []
var stray_candidates: Array[AnimalController] = []
var _assignment_remaining: float = 0.0
var _returning: bool = false
var patrol_angle: float = 0.0

func refresh_config() -> void:
	settings = gameplay_engine.config.sheepdog
	movement_config = settings
	_assignment_remaining = 0.0
	super.refresh_config()

func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	super.initialize(engine, id, at_position)
	current_behavior = Behavior.PATROL
	protection_center = at_position
	patrol_angle = entity_id * 2.399963

func perceive(delta: float) -> void:
	super.perceive(delta)
	_assignment_remaining -= delta
	if not is_live(protected_sheep) or _assignment_remaining <= 0.0:
		_choose_protection_anchor()
		_assignment_remaining = settings.reassignment_interval
	_update_protection_center()
	patrol_angle += settings.patrol_angular_speed * delta * (1.0 if entity_id % 2 == 0 else -1.0)
	guard_point = clamp_to_arena(protection_center + Vector2.from_angle(patrol_angle) * settings.guard_distance)
	observe_target(delta)
	if not is_live(protected_sheep):
		target = null
		_returning = false
	elif global_position.distance_to(protection_center) > settings.leash_distance:
		_returning = true
	if _returning and global_position.distance_to(guard_point) <= 24.0:
		_returning = false
	wolf_candidates.clear()
	stray_candidates.clear()
	if _returning or not is_live(protected_sheep):
		return
	var service: EntityService = gameplay_engine.entity_service
	var flock: Array[Vector2] = []
	for index in service.get_nearby_indices(protected_sheep.global_position, settings.local_flock_radius):
		if service.perception_kinds[index] == Kind.SHEEP and protected_sheep.global_position.distance_to(service.perception_positions[index]) <= settings.local_flock_radius:
			flock.append(service.perception_positions[index])
	for wolf in service.wolves:
		if not wolf.alive or not can_see(wolf.global_position):
			continue
		var threatening: bool = wolf.hunting
		for point in flock:
			if wolf.global_position.distance_to(point) < settings.threat_distance:
				threatening = true
				break
		if threatening:
			wolf_candidates.append(wolf)
	if is_live(target) and not target_visible and unseen_elapsed < settings.memory_duration:
		wolf_candidates.append(target)
	var radius := settings.local_flock_radius
	for index in service.get_nearby_indices(protected_sheep.global_position, radius * 2.0):
		if service.perception_kinds[index] != Kind.SHEEP:
			continue
		var sheep := service.entities[index] as SheepController
		var point := service.perception_positions[index]
		var distance := protection_center.distance_to(point)
		var threshold := radius * settings.collect_complete_ratio if sheep == collected_sheep else radius
		if protected_sheep.global_position.distance_to(point) <= radius * 2.0 and distance > threshold:
			stray_candidates.append(sheep)

func task_point(animal: AnimalController) -> Vector2:
	if animal == target and not target_visible:
		return last_seen_position
	return animal.global_position

func apply_assignment(wolf: AnimalController, stray: AnimalController) -> void:
	var lost_wolf := is_live(target) and wolf == null
	if wolf != target:
		target = wolf
		observe_target(0.0)
	collected_sheep = stray as SheepController
	if lost_wolf:
		_returning = true
	bt_player.blackboard.set_var(&"must_return", _returning)
	bt_player.blackboard.set_var(&"has_threat", is_live(target))
	bt_player.blackboard.set_var(&"has_stray", is_live(collected_sheep))

func _anchor_score(sheep: SheepController) -> float:
	var coverage: int = 0
	for dog in gameplay_engine.entity_service.dogs:
		if dog != self and dog.alive and is_live(dog.protected_sheep):
			if dog.protected_sheep.global_position.distance_to(sheep.global_position) < settings.local_flock_radius:
				coverage += 1
	return global_position.distance_to(sheep.global_position) / settings.local_flock_radius + coverage * settings.coverage_weight

func _choose_protection_anchor() -> void:
	var started := Time.get_ticks_usec() if gameplay_engine.profile_service.detailed_stats_enabled else 0
	var best: SheepController = protected_sheep if is_live(protected_sheep) else null
	var current_score: float = _anchor_score(best) if best != null else INF
	var best_score := current_score
	for sheep in gameplay_engine.entity_service.sheep:
		if not sheep.alive:
			continue
		var score := _anchor_score(sheep)
		if score < best_score:
			best = sheep
			best_score = score

	if not is_live(protected_sheep) or best_score <= current_score * (1.0 - settings.reassignment_improvement):
		protected_sheep = best
	if gameplay_engine.profile_service.detailed_stats_enabled:
		gameplay_engine.profile_service.record_hotspot("DogAnchor", started)

func _update_protection_center() -> void:
	if not is_live(protected_sheep):
		_update_wander(85.0)
		protection_center = _wander_point
		return

	var center := Vector2.ZERO
	var count: int = 0
	var service: EntityService = gameplay_engine.entity_service
	for index in service.get_nearby_indices(protected_sheep.global_position, settings.local_flock_radius):
		if service.perception_kinds[index] == Kind.SHEEP:
			var point := service.perception_positions[index]
			if point.distance_to(protected_sheep.global_position) <= settings.local_flock_radius:
				center += point
				count += 1
	protection_center = center / count if count > 0 else protected_sheep.global_position

func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	match behavior:
		Behavior.PATROL:
			if is_live(protected_sheep):
				_towards(guard_point, move_speed, delta)
			else:
				_update_wander(85.0)
				_towards(_wander_point, move_speed, delta)
		Behavior.DRIVE:
			_towards(last_seen_position, settings.drive_speed, delta)
		Behavior.COLLECT:
			if is_live(collected_sheep):
				var away := (collected_sheep.global_position - protection_center).normalized()
				var point := clamp_to_arena(collected_sheep.global_position + away * settings.collect_distance)
				_towards(point, move_speed, delta)
		Behavior.RETURN:
			_towards(guard_point, settings.return_speed, delta)

func get_debug_details() -> String:
	return "Anchor #%d | Stray #%d | Unseen %.1f s" % [protected_sheep.entity_id if is_live(protected_sheep) else 0, collected_sheep.entity_id if is_live(collected_sheep) else 0, unseen_elapsed]

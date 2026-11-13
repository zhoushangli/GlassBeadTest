class_name SheepdogController
extends AnimalController

var settings: SheepdogConfig
var protected_sheep: SheepController
var protection_center := Vector2.ZERO
var guard_point := Vector2.ZERO
var intercept_point := Vector2.ZERO
var candidate_wolf: WolfController
var _assignment_remaining: float = 0.0
var _returning: bool = false
var _interception_complete: bool = false


func refresh_config() -> void:
	settings = gameplay_engine.config.sheepdog
	movement_config = settings
	_assignment_remaining = 0.0
	super.refresh_config()


func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	super.initialize(engine, id, at_position)
	current_behavior = Behavior.PATROL
	protection_center = at_position


func perceive(delta: float) -> void:
	super.perceive(delta)
	_assignment_remaining -= delta
	if not is_live(protected_sheep) or _assignment_remaining <= 0.0:
		_choose_protection_anchor()
		_assignment_remaining = settings.reassignment_interval

	_update_protection_center()
	var angle := entity_id * 2.399963
	guard_point = clamp_to_arena(protection_center + Vector2.from_angle(angle) * settings.guard_distance)
	candidate_wolf = null
	var nearest_distance: float = INF
	var service: EntityService = gameplay_engine.entity_service
	var emergency_distance: float = gameplay_engine.config.sheep.emergency_distance
	for wolf in service.wolves:
		if not wolf.alive or global_position.distance_to(wolf.global_position) > perception_radius:
			continue

		var threatens_flock: bool = (wolf.hunting or wolf == target) and wolf.global_position.distance_to(protection_center) <= settings.protection_radius
		if not threatens_flock:
			for index in service.get_nearby_indices(wolf.global_position, emergency_distance):
				var point := service.perception_positions[index]
				if service.perception_kinds[index] == Kind.SHEEP and point.distance_to(protection_center) <= settings.local_flock_radius:
					if point.distance_to(wolf.global_position) < emergency_distance:
						threatens_flock = true
						break

		var distance := global_position.distance_to(wolf.global_position)
		if is_live(protected_sheep) and threatens_flock and distance < nearest_distance:
			candidate_wolf = wolf
			nearest_distance = distance

	if global_position.distance_to(protection_center) > settings.leash_distance:
		_returning = true
	if is_live(target) and not is_live(candidate_wolf):
		_returning = true
	if _returning and global_position.distance_to(guard_point) <= 24.0:
		_returning = false
		target = null

	if candidate_wolf != target:
		_interception_complete = false
	if is_live(candidate_wolf):
		var from_flock := candidate_wolf.global_position - protection_center
		intercept_point = clamp_to_arena(candidate_wolf.global_position - from_flock.normalized() * 42.0)
		if global_position.distance_to(intercept_point) <= 24.0:
			_interception_complete = true

	bt_player.blackboard.set_var(&"must_return", _returning)
	bt_player.blackboard.set_var(&"has_threat", is_live(candidate_wolf))
	bt_player.blackboard.set_var(&"needs_intercept", not _interception_complete)


func _anchor_score(sheep: SheepController) -> float:
	var coverage: int = 0
	for dog in gameplay_engine.entity_service.dogs:
		if dog != self and dog.alive and is_live(dog.protected_sheep):
			if dog.protected_sheep.global_position.distance_to(sheep.global_position) < settings.local_flock_radius:
				coverage += 1
	return global_position.distance_to(sheep.global_position) / settings.local_flock_radius + coverage * settings.coverage_weight


func _choose_protection_anchor() -> void:
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
			target = null
			_towards(guard_point, move_speed, delta)
		Behavior.INTERCEPT:
			target = candidate_wolf
			_towards(intercept_point, settings.drive_speed, delta)
		Behavior.DRIVE:
			target = candidate_wolf
			if is_live(target):
				_towards(target.global_position, settings.drive_speed, delta)
		Behavior.RETURN:
			target = null
			_towards(guard_point, settings.return_speed, delta)
	bt_player.blackboard.set_var(&"target", target)


func get_debug_details() -> String:
	return "Protecting sheep #%d" % protected_sheep.entity_id if is_live(protected_sheep) else "No sheep to protect"

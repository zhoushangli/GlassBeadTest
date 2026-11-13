class_name WolfController
extends AnimalController

var settings: WolfConfig
var hunting: bool = false
var supporting_hunt: bool = false
var capture_progress: float = 0.0
var retreating: bool = false
var nearest_threat: SheepdogController
var _rest_point := Vector2.ZERO
var _rest_remaining: float = 0.0


func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	super.initialize(engine, id, at_position)
	current_behavior = Behavior.REST
	_rest_point = at_position


func refresh_config() -> void:
	settings = gameplay_engine.config.wolf
	movement_config = settings
	_rest_remaining = 0.0
	super.refresh_config()


func _get_query_radius() -> float:
	return maxf(super._get_query_radius(), settings.dog_threat_distance)


func _scan_neighbors(service: EntityService) -> void:
	nearest_threat = null
	var dog_distance: float = settings.dog_threat_distance * settings.dog_threat_distance
	for index in _nearby:
		var distance_squared := global_position.distance_squared_to(service.perception_positions[index])
		if service.perception_kinds[index] == Kind.SHEEPDOG and distance_squared < dog_distance:
			nearest_threat = service.entities[index] as SheepdogController
			dog_distance = distance_squared


func perceive(delta: float) -> void:
	super.perceive(delta)
	_rest_remaining -= delta
	if is_live(nearest_threat) and global_position.distance_to(nearest_threat.global_position) >= settings.dog_threat_distance:
		nearest_threat = null

	if hunting and (is_live(nearest_threat) or not is_live(target) or global_position.distance_to(target.global_position) >= perception_radius):
		leave_hunt()

	if retreating and not is_live(nearest_threat) and global_position.distance_to(_rest_point) < 24.0:
		retreating = false
	if not hunting and not retreating and _rest_remaining <= 0.0:
		_choose_rest_point()

	bt_player.blackboard.set_var(&"threat", is_live(nearest_threat))
	bt_player.blackboard.set_var(&"must_retreat", retreating)
	bt_player.blackboard.set_var(&"has_prey", hunting and is_live(target))
	bt_player.blackboard.set_var(&"can_capture", hunting and is_live(target) and global_position.distance_to(target.global_position) <= settings.capture_distance)
	bt_player.blackboard.set_var(&"target", target)


func begin_hunt(prey: SheepController, support: bool) -> void:
	target = prey
	hunting = true
	supporting_hunt = support
	retreating = false
	capture_progress = 0.0
	_perception_ready = false


func leave_hunt() -> void:
	hunting = false
	target = null
	supporting_hunt = false
	capture_progress = 0.0
	retreating = true
	_choose_rest_point()


func _choose_rest_point() -> void:
	var arena: Vector2 = gameplay_engine.config.arena_size
	var first := Vector2(24.0, 106.0)
	var last := arena - Vector2(24.0, 70.0)
	var center := (first + last) * 0.5
	var candidates := [first, Vector2(center.x, first.y), Vector2(last.x, first.y),
		Vector2(first.x, center.y), Vector2(last.x, center.y),
		Vector2(first.x, last.y), Vector2(center.x, last.y), last]
	var best_score: float = -INF
	for point: Vector2 in candidates:
		var clearance: float = settings.retreat_distance
		for sheep in gameplay_engine.entity_service.sheep:
			if sheep.alive:
				clearance = minf(clearance, point.distance_to(sheep.global_position))
		var score := clearance - global_position.distance_to(point) * 0.1
		if score > best_score:
			best_score = score
			_rest_point = point

	_rest_point = clamp_to_arena(_rest_point + Vector2.from_angle(gameplay_engine.rng.randf_range(-PI, PI)) * 24.0)
	_rest_remaining = gameplay_engine.rng.randf_range(2.0, 4.0)


func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	match behavior:
		Behavior.REST:
			_towards(_rest_point, move_speed, delta)
		Behavior.RETREAT:
			_towards(_rest_point, settings.retreat_speed, delta)
		Behavior.FLEE:
			if is_live(nearest_threat):
				var away := (global_position - nearest_threat.global_position).normalized()
				if away.is_zero_approx():
					away = Vector2.from_angle(entity_id * 2.399963)
				_speed_limit = settings.retreat_speed
				desired_velocity = away * settings.retreat_speed
				movement_goal = global_position + away * 80.0
		Behavior.CHASE, Behavior.CAPTURE:
			if not hunting or not is_live(target):
				return
			var goal := target.global_position
			if behavior == Behavior.CHASE and supporting_hunt and global_position.distance_to(goal) > 64.0:
				var approach := (goal - global_position).normalized()
				goal += approach.orthogonal() * settings.flank_offset * (1.0 if entity_id % 2 == 0 else -1.0)
			_towards(goal, settings.chase_speed, delta)


func resolve_interactions(delta: float) -> void:
	if not hunting or current_behavior != Behavior.CAPTURE:
		return
	if not is_live(target) or global_position.distance_to(target.global_position) > settings.capture_distance:
		capture_progress = 0.0
		return

	# 1) Recheck dogs after movement, including between sampled perception updates.
	for dog in gameplay_engine.entity_service.dogs:
		if dog.alive and global_position.distance_to(dog.global_position) < settings.dog_threat_distance:
			nearest_threat = dog
			leave_hunt()
			return

	capture_progress += delta
	if capture_progress + 0.000001 >= settings.capture_duration:
		if gameplay_engine.entity_service.capture(target):
			gameplay_engine.finish_hunt()


func finish_behavior(behavior: Behavior) -> void:
	if behavior == Behavior.CAPTURE:
		capture_progress = 0.0


func get_debug_details() -> String:
	if hunting:
		return "%s | Capture %.2f / %.2f s" % ["Supporting" if supporting_hunt else "Leading", capture_progress, settings.capture_duration]
	return "Next round %.1f s" % gameplay_engine.hunt_rest_remaining

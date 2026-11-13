class_name WolfController
extends AnimalController

var settings: WolfConfig
var hunting: bool = false
var capture_progress: float = 0.0
var hunt_elapsed: float = 0.0
var nearest_threat: SheepdogController
var _search_remaining: float = 0.0
var _timed_out_target: SheepController


func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	super.initialize(engine, id, at_position)
	current_behavior = Behavior.SEARCH


func refresh_config() -> void:
	settings = gameplay_engine.config.wolf
	movement_config = settings
	super.refresh_config()


func update_hunt(delta: float) -> void:
	nearest_threat = null
	var nearest_distance := settings.dog_threat_distance
	for dog in gameplay_engine.entity_service.dogs:
		if dog.alive:
			var distance := global_position.distance_to(dog.global_position)
			if distance < nearest_distance:
				nearest_threat = dog
				nearest_distance = distance
	if is_live(nearest_threat):
		leave_hunt()
		return

	if hunting:
		hunt_elapsed += delta
		if not is_live(target) or global_position.distance_to(target.global_position) >= perception_radius:
			leave_hunt()
		elif hunt_elapsed + 0.000001 >= settings.hunt_duration:
			_timed_out_target = target as SheepController
			leave_hunt()
			return
		else:
			return

	_search_remaining -= delta
	if _search_remaining <= 0.0:
		_choose_prey()
		_search_remaining = settings.search_interval


func _prey_weight(prey: SheepController) -> float:
	var competitors: int = 0
	for wolf in gameplay_engine.entity_service.wolves:
		if wolf != self and wolf.alive and wolf.hunting and wolf.target == prey:
			if wolf.hunt_elapsed < wolf.settings.hunt_duration and wolf.global_position.distance_to(prey.global_position) < wolf.perception_radius:
				competitors += 1
	return 1.0 / maxf(global_position.distance_to(prey.global_position), 1.0) / (1.0 + competitors * settings.competition_weight)


func _choose_prey() -> void:
	var candidates: Array[SheepController] = []
	for sheep in gameplay_engine.entity_service.sheep:
		if sheep.alive and global_position.distance_to(sheep.global_position) < perception_radius:
			candidates.append(sheep)
	if candidates.size() > 1:
		candidates.erase(_timed_out_target)
	_timed_out_target = null
	var weights: Array[float] = []
	var total: float = 0.0
	for sheep in candidates:
		var weight := _prey_weight(sheep)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return

	var choice: float = gameplay_engine.rng.randf() * total
	for index in range(candidates.size()):
		choice -= weights[index]
		if choice < 0.0 or index == candidates.size() - 1:
			begin_hunt(candidates[index])
			return


func perceive(delta: float) -> void:
	super.perceive(delta)
	bt_player.blackboard.set_var(&"threat", is_live(nearest_threat))
	bt_player.blackboard.set_var(&"has_prey", hunting and is_live(target))
	bt_player.blackboard.set_var(&"can_capture", hunting and is_live(target) and global_position.distance_to(target.global_position) <= settings.capture_distance)
	bt_player.blackboard.set_var(&"target", target)


func begin_hunt(prey: SheepController) -> void:
	target = prey
	hunting = true
	hunt_elapsed = 0.0
	capture_progress = 0.0


func leave_hunt() -> void:
	hunting = false
	target = null
	capture_progress = 0.0
	hunt_elapsed = 0.0
	_search_remaining = 0.0


func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	match behavior:
		Behavior.SEARCH:
			_update_wander(160.0)
			_towards(_wander_point, move_speed, delta)
		Behavior.FLEE:
			if is_live(nearest_threat):
				var away := (global_position - nearest_threat.global_position).normalized()
				if away.is_zero_approx():
					away = Vector2.from_angle(entity_id * 2.399963)
				_speed_limit = settings.retreat_speed
				desired_velocity = away * settings.retreat_speed
				movement_goal = global_position + away * 80.0
		Behavior.CHASE, Behavior.CAPTURE:
			if hunting and is_live(target):
				_towards(target.global_position, settings.chase_speed, delta)


func resolve_interactions(delta: float) -> void:
	if not hunting or current_behavior != Behavior.CAPTURE:
		return
	if not is_live(target) or global_position.distance_to(target.global_position) > settings.capture_distance:
		capture_progress = 0.0
		return

	# 1) Recheck dogs at the positions resulting from this step.
	for dog in gameplay_engine.entity_service.dogs:
		if dog.alive and global_position.distance_to(dog.global_position) < settings.dog_threat_distance:
			nearest_threat = dog
			leave_hunt()
			return

	capture_progress += delta
	if capture_progress + 0.000001 >= settings.capture_duration:
		if gameplay_engine.entity_service.capture(target):
			leave_hunt()


func finish_behavior(behavior: Behavior) -> void:
	if behavior == Behavior.CAPTURE:
		capture_progress = 0.0


func get_debug_details() -> String:
	if hunting:
		return "Hunting sheep #%d | Chase %.1f s | Capture %.2f / %.2f s" % [target.entity_id, hunt_elapsed, capture_progress, settings.capture_duration] if is_live(target) else "Replacing prey"
	return "Avoiding dog" if is_live(nearest_threat) else "Searching for prey"

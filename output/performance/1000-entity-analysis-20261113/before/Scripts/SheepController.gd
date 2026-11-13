class_name SheepController
extends AnimalController

var avoidance_radius: float:
	get:
		return lerpf(perception_radius, settings.emergency_distance, float(hunger) / 100.0)

var settings: SheepConfig
var hunger: int = 0
var grazing_progress: float = 0.0
var grass_target_index: int = -1
var grass_target := Vector2.ZERO
var local_flock_center := Vector2.ZERO
var neighbor_count: int = 0
var nearest_threat: WolfController
var threat_memory: float = 0.0
var meals_eaten: int = 0
var last_meal_patch: int = -1
var _hunger_fraction: float = 0.0
var _feeding: bool = false
var _retarget_remaining: float = 0.0
var _meal_completed: bool = false
var _threat_direction := Vector2.ZERO
var _observed_wolves: Array[WolfController] = []

func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	super.initialize(engine, id, at_position)
	hunger = gameplay_engine.rng.randi_range(settings.initial_hunger_min, settings.initial_hunger_max)

func refresh_config() -> void:
	settings = gameplay_engine.config.sheep
	movement_config = settings
	_retarget_remaining = 0.0
	super.refresh_config()

func _get_query_radius() -> float:
	return maxf(super._get_query_radius(), settings.flock_radius)

func _scan_neighbors(service: EntityService) -> void:
	local_flock_center = Vector2.ZERO
	neighbor_count = 0
	_observed_wolves.clear()

	for index in _nearby:
		if index == perception_index:
			continue

		var distance_squared := global_position.distance_squared_to(service.perception_positions[index])
		if service.perception_kinds[index] == Kind.SHEEP and distance_squared < settings.flock_radius * settings.flock_radius:
			local_flock_center += service.perception_positions[index]
			neighbor_count += 1
		elif service.perception_kinds[index] == Kind.WOLF and distance_squared < perception_radius * perception_radius:
			_observed_wolves.append(service.entities[index] as WolfController)

	local_flock_center = local_flock_center / neighbor_count if neighbor_count > 0 else global_position

func perceive(delta: float) -> void:
	_hunger_fraction += settings.hunger_per_second * delta
	var gained := floori(_hunger_fraction + 0.000001)
	_hunger_fraction = maxf(0.0, _hunger_fraction - gained)
	hunger = clampi(hunger + gained, 0, 100)
	if hunger == 100:
		_hunger_fraction = 0.0
	super.perceive(delta)
	_retarget_remaining -= delta
	_update_threat(delta)

	if hunger >= settings.hungry_threshold:
		_feeding = true
	elif hunger <= settings.full_threshold:
		_feeding = false

	var threatened := is_live(nearest_threat) or threat_memory > 0.0
	if threatened or not _feeding:
		_set_grass_target(-1)
		_retarget_remaining = 0.0
	else:
		var valid := _grass_available(grass_target_index) and not _grass_unsafe(grass_target_index)
		var lost_target := grass_target_index >= 0 and not valid
		if lost_target or _meal_completed or (_retarget_remaining <= 0.0 and current_behavior != Behavior.GRAZE):
			_choose_grass(valid)
			_retarget_remaining = settings.retarget_interval
	_meal_completed = false

	grass_target = gameplay_engine.grass_positions[grass_target_index] if _grass_available(grass_target_index) else global_position
	bt_player.blackboard.set_var(&"threat", threatened)
	bt_player.blackboard.set_var(&"hungry", _feeding and _grass_available(grass_target_index))
	bt_player.blackboard.set_var(&"at_grass", global_position.distance_to(grass_target) <= settings.grazing_distance)

func _update_threat(delta: float) -> void:
	nearest_threat = null
	var nearest_distance: float = INF
	var away := Vector2.ZERO
	for wolf in _observed_wolves:
		if not is_live(wolf):
			continue

		var offset := global_position - wolf.global_position
		var distance := offset.length()
		var radius: float = avoidance_radius if wolf.hunting else settings.emergency_distance
		if distance >= radius:
			continue

		away += offset.normalized() / maxf(distance, 1.0)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_threat = wolf

	if is_live(nearest_threat):
		threat_memory = settings.safety_duration
		_threat_direction = away.normalized()
		if _threat_direction.is_zero_approx():
			_threat_direction = Vector2.from_angle(entity_id * 2.399963)
	else:
		threat_memory = maxf(0.0, threat_memory - delta)

func _grass_available(index: int) -> bool:
	return index >= 0 and index < gameplay_engine.grass_bites.size() and gameplay_engine.grass_bites[index] > 0

func _grass_unsafe(index: int) -> bool:
	if not _grass_available(index):
		return true

	var point: Vector2 = gameplay_engine.grass_positions[index]
	for wolf in gameplay_engine.entity_service.wolves:
		if wolf.alive:
			var radius: float = avoidance_radius if wolf.hunting else settings.emergency_distance
			if point.distance_squared_to(wolf.global_position) < radius * radius:
				return true
	return false

func _grass_score(index: int) -> float:
	var claims: int = gameplay_engine.grass_claims[index] - (1 if index == grass_target_index else 0)
	var food: float = float(gameplay_engine.grass_bites[index]) / gameplay_engine.config.grass.bites
	return global_position.distance_to(gameplay_engine.grass_positions[index]) / gameplay_engine.config.grass.patch_radius \
		+ settings.crowd_weight * maxi(0, claims) + (1.0 - food)

func _choose_grass(keep_current: bool) -> void:
	var best := grass_target_index if keep_current else -1
	var current_score: float = _grass_score(best) if best >= 0 else INF
	var best_score := current_score
	for index in range(gameplay_engine.grass_positions.size()):
		if not _grass_available(index):
			continue
		if index != grass_target_index and gameplay_engine.grass_claims[index] >= gameplay_engine.grass_bites[index]:
			continue

		var score := _grass_score(index)
		if score < best_score and not _grass_unsafe(index):
			best = index
			best_score = score

	if not keep_current or best_score <= current_score * (1.0 - settings.retarget_improvement):
		_set_grass_target(best)

func _set_grass_target(index: int) -> void:
	if grass_target_index == index:
		return

	if grass_target_index >= 0 and grass_target_index < gameplay_engine.grass_claims.size():
		gameplay_engine.grass_claims[grass_target_index] = maxi(0, gameplay_engine.grass_claims[grass_target_index] - 1)
	grass_target_index = index
	if index >= 0:
		gameplay_engine.grass_claims[index] += 1
	grazing_progress = 0.0

func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	match behavior:
		Behavior.FLOCK:
			_update_wander(85.0)
			_towards(_wander_point, move_speed * settings.idle_speed_scale, delta)
			_follow_neighbors(settings.idle_cohesion)
		Behavior.SEEK_FOOD:
			_towards(grass_target, move_speed, delta)
			if global_position.distance_to(grass_target) > settings.grazing_distance * 2.0:
				_follow_neighbors(settings.foraging_cohesion)
		Behavior.GRAZE:
			movement_goal = grass_target
		Behavior.FLEE:
			_speed_limit = settings.flee_speed
			desired_velocity = _threat_direction * settings.flee_speed
			movement_goal = global_position + _threat_direction * 80.0

func _follow_neighbors(weight: float) -> void:
	if neighbor_count > 0 and global_position.distance_to(local_flock_center) > 36.0:
		desired_velocity += (local_flock_center - global_position).normalized() * _speed_limit * weight

func resolve_interactions(delta: float) -> void:
	if current_behavior != Behavior.GRAZE:
		return
	if not _grass_available(grass_target_index) or global_position.distance_to(grass_target) > settings.grazing_distance:
		grazing_progress = 0.0
		return

	grazing_progress += delta
	if grazing_progress + 0.000001 >= settings.grazing_duration:
		if gameplay_engine.consume_grass(grass_target_index):
			hunger = maxi(0, hunger - settings.hunger_per_bite)
			meals_eaten += 1
			last_meal_patch = gameplay_engine.grass_patch_indices[grass_target_index]
		grazing_progress = 0.0
		_meal_completed = true

func finish_behavior(behavior: Behavior) -> void:
	if behavior == Behavior.GRAZE:
		grazing_progress = 0.0

func get_debug_details() -> String:
	return "Hunger %d%% | Avoid %.1f px | Grass %d | Meals %d" % [hunger, avoidance_radius, grass_target_index, meals_eaten]

func die() -> void:
	_set_grass_target(-1)
	super.die()

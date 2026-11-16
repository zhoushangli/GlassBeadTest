class_name WolfController
extends AnimalController

enum Strategy { FRONTAL, SIDE, REAR, HOWL }
const STRATEGY_NAMES := ["Frontal", "Side", "Rear", "Howl"]

var settings: WolfConfig
var hunting: bool = false
var hunt_elapsed: float = 0.0
var charging: bool = false
var strategy: Strategy = Strategy.FRONTAL
var strategy_failures: Array[float] = [0.0, 0.0, 0.0, 0.0]
var nearest_threat: SheepdogController
var retreating: bool = false
var resting: bool = false
var rest_elapsed: float = 0.0
var howl_elapsed: float = 1000.0
var howled: bool = false
var howl_pending: bool = false

func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	super.initialize(engine, id, at_position)
	current_behavior = Behavior.PATROL

func refresh_config() -> void:
	settings = gameplay_engine.config.wolf
	movement_config = settings
	super.refresh_config()

func find_dog(radius: float) -> SheepdogController:
	var result: SheepdogController
	var best := radius
	for dog in gameplay_engine.entity_service.dogs:
		if not dog.alive:
			continue
		var distance := global_position.distance_to(dog.global_position)
		if distance < best or (is_equal_approx(distance, best) and result != null and dog.entity_id < result.entity_id):
			result = dog
			best = distance
	return result

func perceive(delta: float) -> void:
	super.perceive(delta)
	for index in range(strategy_failures.size()):
		strategy_failures[index] = maxf(0.0, strategy_failures[index] - settings.strategy_decay * delta)
	howl_elapsed += delta
	if resting:
		rest_elapsed += delta
		resting = rest_elapsed < settings.rest_duration
	nearest_threat = find_dog(settings.dog_threat_distance * (2.0 if retreating else 1.0))
	if hunting:
		hunt_elapsed += delta
		observe_target(delta)
		if not is_live(target) or hunt_elapsed >= settings.hunt_duration or (not target_visible and unseen_elapsed >= settings.memory_duration):
			end_hunt(false)
	if not hunting and not resting and not is_live(nearest_threat) and not retreating:
		_choose_prey()
	bt_player.blackboard.set_var(&"dog_near", is_live(nearest_threat))
	bt_player.blackboard.set_var(&"needs_rest", resting or (retreating and not is_live(nearest_threat)))
	bt_player.blackboard.set_var(&"lost_sight", hunting and not target_visible)
	bt_player.blackboard.set_var(&"has_prey", hunting)
	bt_player.blackboard.set_var(&"charge", hunting and target_visible and (charging or global_position.distance_to(last_seen_position) <= settings.capture_distance * settings.charge_distance_scale))

func _choose_prey() -> void:
	var started := Time.get_ticks_usec() if gameplay_engine.profile_service.detailed_stats_enabled else 0
	var best: SheepController
	var distance: float = INF
	var service: EntityService = gameplay_engine.entity_service
	for index in service.get_nearby_indices(global_position, perception_radius):
		if service.perception_kinds[index] != Kind.SHEEP:
			continue
		var point := service.perception_positions[index]
		if not can_see(point):
			continue
		var candidate := service.entities[index] as SheepController
		var next_distance := global_position.distance_squared_to(point)
		if next_distance < distance or (is_equal_approx(next_distance, distance) and best != null and candidate.entity_id < best.entity_id):
			best = candidate
			distance = next_distance
	if best != null:
		begin_hunt(best)
	if gameplay_engine.profile_service.detailed_stats_enabled:
		gameplay_engine.profile_service.record_hotspot("WolfTarget", started)

func begin_hunt(prey: SheepController) -> void:
	target = prey
	hunting = true
	hunt_elapsed = 0.0
	charging = false
	howled = false
	var total: float = 0.0
	for failures in strategy_failures:
		total += 1.0 / (1.0 + failures)
	var choice: float = gameplay_engine.rng.randf() * total
	for index in range(strategy_failures.size()):
		choice -= 1.0 / (1.0 + strategy_failures[index])
		if choice <= 0.0 or index == strategy_failures.size() - 1:
			strategy = index as Strategy
			break
	observe_target(0.0)

func end_hunt(success: bool) -> void:
	if not hunting:
		return
	strategy_failures[strategy] = maxf(0.0, strategy_failures[strategy] + (-1.5 if success else 1.0))
	hunting = false
	charging = false
	target = null
	target_visible = false
	resting = true
	rest_elapsed = 0.0

func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	match behavior:
		Behavior.RETREAT:
			end_hunt(false)
			retreating = true
			if is_live(nearest_threat):
				var away := (global_position - nearest_threat.global_position).normalized()
				if away.is_zero_approx():
					away = facing
				_towards(global_position + away * 100.0, settings.retreat_speed, delta)
		Behavior.REST:
			if retreating:
				retreating = false
				resting = true
				rest_elapsed = 0.0
			movement_goal = global_position
			_speed_limit = 0.0
		Behavior.SEARCH:
			_towards(last_seen_position, move_speed, delta)
		Behavior.CHASE:
			charging = true
			_towards(last_seen_position, settings.chase_speed, delta)
		Behavior.STALK:
			var point := last_seen_position
			var direction := last_seen_velocity.normalized()
			if direction.is_zero_approx():
				direction = Vector2.RIGHT
			match strategy:
				Strategy.SIDE:
					point += direction.orthogonal() * settings.strategy_offset
				Strategy.REAR:
					point -= direction * settings.strategy_offset
				Strategy.HOWL:
					if not howled and howl_elapsed >= settings.howl_cooldown and global_position.distance_to(last_seen_position) <= settings.howl_trigger_distance:
						howl_pending = true
						howled = true
						howl_elapsed = 0.0
			_towards(clamp_to_arena(point), move_speed, delta)
		Behavior.PATROL:
			_update_wander(160.0)
			_towards(_wander_point, move_speed * settings.patrol_speed_scale, delta)

func resolve_interactions(_delta: float) -> void:
	if howl_pending:
		howl_pending = false
		for sheep in gameplay_engine.entity_service.sheep:
			if sheep.alive and global_position.distance_to(sheep.global_position) <= settings.howl_radius:
				sheep.receive_howl(global_position)
	if not hunting or current_behavior != Behavior.CHASE:
		return
	if not is_live(target):
		end_hunt(false)
		return
	nearest_threat = find_dog(settings.dog_threat_distance)
	if is_live(nearest_threat):
		end_hunt(false)
		retreating = true
		return
	if can_see(target.global_position) and global_position.distance_to(target.global_position) <= settings.capture_distance:
		if gameplay_engine.entity_service.capture(target):
			end_hunt(true)

func get_debug_details() -> String:
	return "%s | Hunt %.1f s | Unseen %.1f s | Failures %s" % [STRATEGY_NAMES[strategy], hunt_elapsed, unseen_elapsed, strategy_failures]

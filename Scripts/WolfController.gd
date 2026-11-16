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

func initialize(id: int, at_position: Vector2) -> void:
	super.initialize(id, at_position)
	current_behavior = Behavior.PATROL

func refresh_config() -> void:
	settings = g_gameplayEngine.config.wolf
	movement_config = settings
	super.refresh_config()

func find_dog(radius: float) -> SheepdogController:
	var result: SheepdogController
	var best := radius
	for dog in g_gameplayEngine.entity_service.dogs:
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

func _choose_prey() -> void:
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var best: SheepController
	var distance: float = INF
	var service: EntityService = g_gameplayEngine.entity_service
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
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("WolfTarget", started)

func begin_hunt(prey: SheepController) -> void:
	target = prey
	hunting = true
	hunt_elapsed = 0.0
	charging = false
	howled = false
	var total: float = 0.0
	for failures in strategy_failures:
		total += 1.0 / (1.0 + failures)
	var choice: float = g_gameplayEngine.rng.randf() * total
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

func has_nearby_dog() -> bool:
	return is_live(nearest_threat)

func needs_rest() -> bool:
	return resting or (retreating and not is_live(nearest_threat))

func has_lost_prey() -> bool:
	return hunting and not target_visible

func has_prey() -> bool:
	return hunting

func can_charge() -> bool:
	return hunting and target_visible and (charging or global_position.distance_to(last_seen_position) <= settings.capture_distance * settings.charge_distance_scale)

func resolve_interactions(_delta: float) -> void:
	if howl_pending:
		howl_pending = false
		for sheep in g_gameplayEngine.entity_service.sheep:
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
		if g_gameplayEngine.entity_service.capture(target):
			end_hunt(true)

func get_debug_details() -> String:
	return "%s | Hunt %.1f s | Unseen %.1f s | Failures %s" % [STRATEGY_NAMES[strategy], hunt_elapsed, unseen_elapsed, strategy_failures]

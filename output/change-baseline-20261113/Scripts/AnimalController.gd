class_name AnimalController
extends Node2D

enum Kind { SHEEP, WOLF, SHEEPDOG }
enum Behavior { FLOCK, SEEK_FOOD, GRAZE, FLEE, SEARCH, CHASE, CAPTURE, PATROL, INTERCEPT, DRIVE, RETURN, DEAD }

const BEHAVIOR_NAMES := [
	"Flock", "Seek grass", "Graze", "Flee", "Search", "Chase",
	"Capture", "Patrol", "Intercept", "Drive off", "Return", "Dead"
]
const KIND_NAMES := ["Sheep", "Wolf", "Sheepdog"]

@export var kind: Kind = Kind.SHEEP
@export_group("Movement")
@export var move_speed: float = 55.0
@export var urgent_speed: float = 110.0
@export var retreat_speed: float = 110.0
@export var return_speed: float = 55.0
@export var perception_radius: float = 190.0
@export_group("Appearance")
@export var base_color := Color("#b8d94b")
@export var behavior_colors: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var bt_player: BTPlayer = $BTPlayer

var gameplay_engine: Node
var entity_id: int = 0
var alive: bool = true
var current_behavior: Behavior = Behavior.FLOCK
var target: AnimalController
var velocity := Vector2.ZERO
var desired_velocity := Vector2.ZERO
var movement_goal := Vector2.ZERO
var flock_center := Vector2.ZERO
var guard_point := Vector2.ZERO
var nearest_threat: AnimalController
var nearest_prey: AnimalController
var candidate_prey: AnimalController
var candidate_wolf: AnimalController
var cooperation_target: AnimalController
var supporting_hunt: bool = false
var capture_progress: float = 0.0
var grazing_progress: float = 0.0
var satiated_remaining: float = 0.0
var death_remaining: float = 0.0
var threat_memory: float = 0.0
var separation := Vector2.ZERO
var local_flock_center := Vector2.ZERO
var neighbor_count: int = 0
var sheep_count: int = 0
var grass_target := Vector2.ZERO
var intercept_point := Vector2.ZERO
var _threat_direction := Vector2.ZERO
var _wander_point := Vector2.ZERO
var _wander_remaining: float = 0.0
var _returning: bool = false
var _interception_complete: bool = false
var _speed_limit: float = 0.0


func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	gameplay_engine = engine
	entity_id = id
	position = at_position
	_wander_point = position
	satiated_remaining = gameplay_engine.rng.randf_range(0.0, 4.0)
	if kind == Kind.WOLF:
		current_behavior = Behavior.SEARCH
	elif kind == Kind.SHEEPDOG:
		current_behavior = Behavior.PATROL


func _ready() -> void:
	sprite.self_modulate = base_color


func is_live(animal: AnimalController) -> bool:
	return is_instance_valid(animal) and animal.alive


func perceive(delta: float) -> void:
	var settings: SimulationConfig = gameplay_engine.config
	separation = Vector2.ZERO
	local_flock_center = Vector2.ZERO
	flock_center = Vector2.ZERO
	neighbor_count = 0
	sheep_count = 0
	nearest_threat = null
	nearest_prey = null
	cooperation_target = null
	candidate_wolf = null
	var nearest_threat_distance: float = INF
	var nearest_prey_distance: float = INF
	var leader_id: int = entity_id
	var away := Vector2.ZERO
	var observed_wolves: Array[AnimalController] = []

	# 1) 每个角色逐一检查全部实体，不保留跨帧的邻居查询结果
	for other in gameplay_engine.entity_service.entities:
		if not other.alive:
			continue
		if other.kind == Kind.SHEEP:
			flock_center += other.global_position
			sheep_count += 1
		if other == self:
			continue

		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if other.kind == kind:
			if distance < settings.separation_distance:
				var direction := offset.normalized()
				if distance < 0.001:
					direction = Vector2.RIGHT if entity_id < other.entity_id else Vector2.LEFT
				separation += direction * (1.0 - distance / settings.separation_distance)
			if distance < settings.flock_radius:
				local_flock_center += other.global_position
				neighbor_count += 1

		if kind == Kind.SHEEP and other.kind == Kind.WOLF and distance < perception_radius:
			away += offset.normalized()
			if distance < nearest_threat_distance:
				nearest_threat = other
				nearest_threat_distance = distance

		if kind == Kind.WOLF:
			if other.kind == Kind.SHEEPDOG and distance < settings.dog_threat_distance:
				away += offset.normalized()
				if distance < nearest_threat_distance:
					nearest_threat = other
					nearest_threat_distance = distance
			elif other.kind == Kind.SHEEP and distance < perception_radius and distance < nearest_prey_distance:
				nearest_prey = other
				nearest_prey_distance = distance
			elif other.kind == Kind.WOLF and distance < settings.cooperation_radius:
				if other.entity_id < leader_id and is_live(other.target):
					if global_position.distance_to(other.target.global_position) < perception_radius:
						leader_id = other.entity_id
						cooperation_target = other.target

		if kind == Kind.SHEEPDOG and other.kind == Kind.WOLF and distance < perception_radius:
			observed_wolves.append(other)

	if sheep_count > 0:
		flock_center /= sheep_count
	else:
		flock_center = settings.arena_size * 0.5
	if neighbor_count > 0:
		local_flock_center /= neighbor_count
	else:
		local_flock_center = global_position

	satiated_remaining = maxf(0.0, satiated_remaining - delta)
	_wander_remaining -= delta
	if is_live(nearest_threat):
		threat_memory = settings.safety_duration if kind == Kind.SHEEP else 0.0
		_threat_direction = away.normalized()
		if _threat_direction.is_zero_approx():
			_threat_direction = Vector2.from_angle(entity_id * 2.399963)
	else:
		threat_memory = maxf(0.0, threat_memory - delta)

	# 2) 生成本步事实，优先级和动作选择由行为树资源决定
	if kind == Kind.SHEEP:
		var grass_distance: float = INF
		grass_target = global_position
		for point in settings.grass_positions:
			var distance := global_position.distance_to(point)
			if distance < grass_distance:
				grass_distance = distance
				grass_target = point
		bt_player.blackboard.set_var(&"threat", is_live(nearest_threat) or threat_memory > 0.0)
		bt_player.blackboard.set_var(&"hungry", satiated_remaining <= 0.0 and not settings.grass_positions.is_empty())
		bt_player.blackboard.set_var(&"at_grass", grass_distance <= settings.grass_radius)
	elif kind == Kind.WOLF:
		if is_live(target) and global_position.distance_to(target.global_position) >= perception_radius:
			target = null
		candidate_prey = target if is_live(target) else nearest_prey
		if is_live(cooperation_target):
			candidate_prey = cooperation_target
		bt_player.blackboard.set_var(&"threat", is_live(nearest_threat))
		bt_player.blackboard.set_var(&"has_prey", is_live(candidate_prey))
		bt_player.blackboard.set_var(&"can_capture", is_live(candidate_prey) and global_position.distance_to(candidate_prey.global_position) <= settings.capture_distance)
	else:
		_perceive_dog(observed_wolves)

	bt_player.blackboard.set_var(&"target", target)
	bt_player.blackboard.set_var(&"nearest_threat", nearest_threat)


func _perceive_dog(observed_wolves: Array[AnimalController]) -> void:
	var settings: SimulationConfig = gameplay_engine.config
	var angle: float = float(entity_id % 4) * PI * 0.5 + gameplay_engine.simulation_time * 0.18
	guard_point = flock_center + Vector2.from_angle(angle) * 95.0
	guard_point = guard_point.clamp(Vector2.ONE * 20.0, settings.arena_size - Vector2.ONE * 20.0)
	var best_distance: float = INF
	if sheep_count > 0:
		for wolf in observed_wolves:
			if wolf.global_position.distance_to(flock_center) <= settings.protection_radius:
				var distance := global_position.distance_to(wolf.global_position)
				if distance < best_distance:
					candidate_wolf = wolf
					best_distance = distance

	if global_position.distance_to(flock_center) > settings.dog_leash:
		_returning = true
	if is_live(target) and not is_live(candidate_wolf):
		_returning = true
	if _returning and global_position.distance_to(guard_point) <= 24.0:
		_returning = false
		target = null

	if candidate_wolf != target:
		_interception_complete = false
	if is_live(candidate_wolf):
		var from_flock := candidate_wolf.global_position - flock_center
		intercept_point = candidate_wolf.global_position - from_flock.normalized() * 42.0
		if global_position.distance_to(intercept_point) <= 24.0:
			_interception_complete = true

	bt_player.blackboard.set_var(&"must_return", _returning)
	bt_player.blackboard.set_var(&"has_threat", is_live(candidate_wolf))
	bt_player.blackboard.set_var(&"needs_intercept", not _interception_complete)


func decide(delta: float) -> void:
	desired_velocity = Vector2.ZERO
	_speed_limit = move_speed
	bt_player.update(delta)


func perform_behavior(behavior: Behavior, delta: float) -> void:
	set_behavior(behavior)
	var settings: SimulationConfig = gameplay_engine.config

	match behavior:
		Behavior.FLOCK:
			_update_wander(85.0)
			var direction := (_wander_point - global_position).normalized()
			if neighbor_count > 0 and global_position.distance_to(local_flock_center) > 36.0:
				direction += (local_flock_center - global_position).normalized() * 0.8
			desired_velocity = direction.normalized() * move_speed
			movement_goal = _wander_point
		Behavior.SEEK_FOOD:
			_towards(grass_target, move_speed, delta)
		Behavior.GRAZE:
			movement_goal = grass_target
			grazing_progress += delta
			if grazing_progress >= settings.grazing_duration:
				satiated_remaining = gameplay_engine.rng.randf_range(settings.satiated_duration.x, settings.satiated_duration.y)
				grazing_progress = 0.0
		Behavior.FLEE:
			var speed := urgent_speed if kind == Kind.SHEEP else retreat_speed
			_speed_limit = speed
			desired_velocity = _threat_direction * speed
			movement_goal = global_position + _threat_direction * 80.0
			if kind == Kind.WOLF:
				target = null
				supporting_hunt = false
				capture_progress = 0.0
		Behavior.SEARCH:
			target = null
			supporting_hunt = false
			_update_wander(240.0)
			_towards(_wander_point, move_speed, delta)
		Behavior.CHASE, Behavior.CAPTURE:
			if not is_live(candidate_prey):
				target = null
				return
			if target != candidate_prey:
				capture_progress = 0.0
			target = candidate_prey
			supporting_hunt = is_live(cooperation_target)
			var goal := target.global_position
			if behavior == Behavior.CHASE and supporting_hunt and global_position.distance_to(goal) > 64.0:
				var approach := (goal - global_position).normalized()
				var side := 1.0 if entity_id % 2 == 0 else -1.0
				goal += approach.orthogonal() * settings.flank_offset * side
			_towards(goal, urgent_speed, delta)
		Behavior.PATROL:
			target = null
			_towards(guard_point, move_speed, delta)
		Behavior.INTERCEPT:
			target = candidate_wolf
			_towards(intercept_point, urgent_speed, delta)
		Behavior.DRIVE:
			target = candidate_wolf
			if is_live(target):
				_towards(target.global_position, urgent_speed, delta)
		Behavior.RETURN:
			target = null
			_towards(guard_point, return_speed, delta)

	bt_player.blackboard.set_var(&"target", target)


func finish_behavior(behavior: Behavior) -> void:
	if behavior == Behavior.CAPTURE:
		capture_progress = 0.0
	elif behavior == Behavior.GRAZE:
		grazing_progress = 0.0


func _update_wander(distance: float) -> void:
	if _wander_remaining <= 0.0 or global_position.distance_to(_wander_point) < 15.0:
		var direction := Vector2.from_angle(gameplay_engine.rng.randf_range(-PI, PI))
		_wander_point = global_position + direction * distance
		_wander_point = _wander_point.clamp(Vector2(20.0, 100.0), gameplay_engine.config.arena_size - Vector2(20.0, 65.0))
		_wander_remaining = gameplay_engine.rng.randf_range(1.5, 3.5)


func _towards(point: Vector2, speed: float, delta: float) -> void:
	movement_goal = point
	_speed_limit = speed
	var difference := point - global_position
	desired_velocity = difference.normalized() * minf(speed, difference.length() / maxf(delta, 0.00001))


func move(delta: float) -> void:
	if not alive:
		death_remaining -= delta
		return

	var settings: SimulationConfig = gameplay_engine.config
	velocity = desired_velocity + separation * move_speed
	velocity = velocity.limit_length(_speed_limit)
	global_position += velocity * delta
	global_position = global_position.clamp(Vector2(12.0, 94.0), settings.arena_size - Vector2(12.0, 58.0))
	if kind == Kind.WOLF and velocity.length() > 1.0:
		sprite.rotation = velocity.angle()


func resolve_interactions(delta: float) -> void:
	if kind != Kind.WOLF or current_behavior != Behavior.CAPTURE:
		return

	var settings: SimulationConfig = gameplay_engine.config
	if not is_live(target) or global_position.distance_to(target.global_position) > settings.capture_distance:
		capture_progress = 0.0
		return

	for other in gameplay_engine.entity_service.entities:
		if other.alive and other.kind == Kind.SHEEPDOG:
			if global_position.distance_to(other.global_position) < settings.dog_threat_distance:
				capture_progress = 0.0
				return

	capture_progress += delta
	if capture_progress + 0.000001 >= settings.capture_duration:
		gameplay_engine.entity_service.capture(target)
		capture_progress = 0.0
		target = null


func set_behavior(behavior: Behavior) -> void:
	current_behavior = behavior
	sprite.self_modulate = behavior_colors.get(BEHAVIOR_NAMES[behavior], base_color)


func die() -> void:
	alive = false
	death_remaining = gameplay_engine.config.death_duration
	bt_player.active = false
	bt_player.restart()
	target = null
	velocity = Vector2.ZERO
	desired_velocity = Vector2.ZERO
	current_behavior = Behavior.DEAD
	sprite.self_modulate = Color("#7b8794")

class_name AnimalController
extends Node2D

enum Kind { SHEEP, WOLF, SHEEPDOG }
enum Behavior { FLOCK, ALERT, HERDED, FLEE, SEARCH, STALK, CHASE, PATROL, COLLECT, DRIVE, RETURN, REST, RETREAT, DEAD }

const BEHAVIOR_NAMES := [
	"Flock", "Alert", "Herded", "Flee", "Search", "Stalk", "Chase",
	"Patrol", "Collect", "Drive off", "Return", "Rest", "Retreat", "Dead"
]
const KIND_NAMES := ["Sheep", "Wolf", "Sheepdog"]

@export var kind: Kind = Kind.SHEEP
@export var base_color := Color("#b8d94b")
@export var behavior_colors: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var bt_player: BTPlayer = $BTPlayer

var move_speed: float:
	get:
		return movement_config.move_speed
var perception_radius: float:
	get:
		return movement_config.perception_radius

var gameplay_engine: Node
var movement_config: Resource
var entity_id: int = 0
var alive: bool = true
var current_behavior: Behavior = Behavior.FLOCK
var target: AnimalController
var facing := Vector2.RIGHT
var last_seen_position := Vector2.ZERO
var last_seen_velocity := Vector2.ZERO
var unseen_elapsed: float = 0.0
var target_visible: bool = false
var velocity := Vector2.ZERO
var desired_velocity := Vector2.ZERO
var movement_goal := Vector2.ZERO
var separation := Vector2.ZERO
var death_remaining: float = 0.0
var perception_index: int = -1
var _nearby: Array[int] = []
var _wander_point := Vector2.ZERO
var _wander_remaining: float = 0.0
var _speed_limit: float = 0.0
var _perception_remaining: float = 0.0
var _perception_ready: bool = false

func initialize(engine: Node, id: int, at_position: Vector2) -> void:
	gameplay_engine = engine
	entity_id = id
	position = at_position
	_wander_point = position
	facing = Vector2.from_angle(gameplay_engine.rng.randf_range(-PI, PI))
	refresh_config()

func _ready() -> void:
	sprite.self_modulate = behavior_colors.get(BEHAVIOR_NAMES[current_behavior], base_color)
	sprite.rotation = facing.angle() + PI * 0.5

func refresh_config() -> void:
	_perception_ready = false

func is_live(animal: AnimalController) -> bool:
	return is_instance_valid(animal) and animal.alive

func can_see(point: Vector2) -> bool:
	var offset := point - global_position
	if offset.length_squared() > perception_radius * perception_radius:
		return false
	return offset.is_zero_approx() or facing.dot(offset.normalized()) + 0.000001 >= cos(deg_to_rad(movement_config.vision_angle * 0.5))

func observe_target(delta: float) -> void:
	if not is_live(target):
		target_visible = false
		unseen_elapsed = 0.0
		return
	target_visible = can_see(target.global_position)
	if target_visible:
		last_seen_position = target.global_position
		last_seen_velocity = target.velocity
		unseen_elapsed = 0.0
	else:
		unseen_elapsed += delta

func perceive(delta: float) -> void:
	_wander_remaining -= delta
	_perception_remaining -= delta
	if not _perception_ready or _perception_remaining <= 0.0:
		var service: EntityService = gameplay_engine.entity_service
		_nearby = service.get_nearby_indices(global_position, _get_query_radius())
		var started := Time.get_ticks_usec() if gameplay_engine.profile_service.detailed_stats_enabled else 0
		_scan_separation(service)
		if gameplay_engine.profile_service.detailed_stats_enabled:
			gameplay_engine.profile_service.record_hotspot("Separation", started)
			started = Time.get_ticks_usec()
		_scan_neighbors(service)
		if gameplay_engine.profile_service.detailed_stats_enabled:
			gameplay_engine.profile_service.record_hotspot("NeighborScan", started)
		_perception_remaining = gameplay_engine.config.perception_interval
		if not _perception_ready:
			_perception_remaining *= fmod(entity_id * 0.618034, 1.0)
		_perception_ready = true

func _get_query_radius() -> float:
	return maxf(perception_radius, gameplay_engine.config.separation_distance)

func _scan_separation(service: EntityService) -> void:
	separation = Vector2.ZERO
	var distance_limit: float = gameplay_engine.config.separation_distance
	if distance_limit <= 0.0:
		return

	for index in _nearby:
		if index == perception_index or service.perception_kinds[index] != kind:
			continue

		var offset := global_position - service.perception_positions[index]
		var distance_squared := offset.length_squared()
		if distance_squared >= distance_limit * distance_limit:
			continue

		var distance := sqrt(distance_squared)
		var direction := offset.normalized()
		if distance < 0.001:
			direction = Vector2.RIGHT if entity_id < service.entities[index].entity_id else Vector2.LEFT
		separation += direction * (1.0 - distance / distance_limit)

func _scan_neighbors(_service: EntityService) -> void:
	pass

func decide(delta: float) -> void:
	desired_velocity = Vector2.ZERO
	_speed_limit = move_speed
	bt_player.update(delta)

func perform_behavior(_behavior: Behavior, _delta: float) -> void:
	pass

func finish_behavior(_behavior: Behavior) -> void:
	pass

func _update_wander(distance: float) -> void:
	if _wander_remaining <= 0.0 or global_position.distance_to(_wander_point) < 15.0:
		var direction := Vector2.from_angle(gameplay_engine.rng.randf_range(-PI, PI))
		_wander_point = clamp_to_arena(global_position + direction * distance)
		_wander_remaining = gameplay_engine.rng.randf_range(1.5, 3.5)

func clamp_to_arena(point: Vector2) -> Vector2:
	return point.clamp(Vector2(12.0, 94.0), gameplay_engine.config.arena_size - Vector2(12.0, 58.0))

func _towards(point: Vector2, speed: float, delta: float) -> void:
	movement_goal = point
	_speed_limit = speed
	var difference := point - global_position
	desired_velocity = difference.normalized() * minf(speed, difference.length() / maxf(delta, 0.00001))

func separation_velocity() -> Vector2:
	return separation * move_speed

func move(delta: float) -> void:
	if not alive:
		death_remaining -= delta
		return

	var previous := global_position
	velocity = (desired_velocity + separation_velocity()).limit_length(_speed_limit)
	global_position = clamp_to_arena(global_position + velocity * delta)
	velocity = (global_position - previous) / maxf(delta, 0.00001)
	if not velocity.is_zero_approx():
		facing = velocity.normalized()
		sprite.rotation = facing.angle() + PI * 0.5

func resolve_interactions(_delta: float) -> void:
	pass

func set_behavior(behavior: Behavior) -> void:
	if current_behavior == behavior:
		return

	current_behavior = behavior
	sprite.self_modulate = behavior_colors.get(BEHAVIOR_NAMES[behavior], base_color)

func get_debug_details() -> String:
	return ""

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

extends Node

signal simulation_stepped
signal grass_reset
signal grass_changed(index: int)

@export var config: SimulationConfig
@onready var entity_service: EntityService = $EntityService
@onready var debug_service: DebugService = $DebugService

var rng := RandomNumberGenerator.new()
var running: bool = false
var paused: bool = false
var simulation_time: float = 0.0
var step_count: int = 0
var last_step_ms: float = 0.0
var last_perception_ms: float = 0.0
var last_decision_ms: float = 0.0
var last_movement_ms: float = 0.0
var hud: DebugHUD
var grass_positions := PackedVector2Array()
var grass_bites := PackedInt32Array()
var grass_regrow_remaining := PackedFloat32Array()
var _pending_spawns: Array[Vector2i] = []
var _reset_pending: bool = false
var _step_pending: bool = false


func start_simulation(world: Node2D, debug_hud: DebugHUD, settings: SimulationConfig) -> void:
	stop_simulation()
	config = settings
	hud = debug_hud
	entity_service.initialize(self, world.get_node("Animals"))
	debug_service.initialize(self)
	hud.initialize(self)
	running = true
	reset_simulation()


func stop_simulation() -> void:
	running = false
	_pending_spawns.clear()
	_reset_pending = false
	_step_pending = false
	debug_service.clear_selection()
	if is_instance_valid(entity_service.container):
		entity_service.clear()
	hud = null


func reset_simulation() -> void:
	debug_service.clear_selection()
	entity_service.clear()
	_pending_spawns.clear()
	_reset_pending = false
	_step_pending = false
	rng.seed = config.random_seed
	simulation_time = 0.0
	step_count = 0
	last_step_ms = 0.0
	last_perception_ms = 0.0
	last_decision_ms = 0.0
	last_movement_ms = 0.0
	paused = false
	reset_grass()
	entity_service.spawn_initial()


func reset_grass() -> void:
	grass_positions.clear()
	grass_bites.clear()
	grass_regrow_remaining.clear()

	for center in config.grass_positions:
		for index in range(config.grass_per_patch):
			var radius := maxf(0.0, config.grass_radius - 10.0) * sqrt(float(index) / maxi(1, config.grass_per_patch - 1))
			grass_positions.append(center + Vector2.from_angle(index * 2.399963) * radius)
			grass_bites.append(config.grass_bites)
			grass_regrow_remaining.append(0.0)

	grass_reset.emit()


func find_grass(point: Vector2) -> int:
	var nearest: int = -1
	var nearest_distance: float = INF
	for index in range(grass_positions.size()):
		if grass_bites[index] <= 0:
			continue

		var distance := point.distance_squared_to(grass_positions[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index

	return nearest


func consume_grass(index: int) -> bool:
	if index < 0 or index >= grass_bites.size() or grass_bites[index] <= 0:
		return false

	grass_bites[index] -= 1
	if grass_bites[index] == 0:
		grass_regrow_remaining[index] = config.grass_regrow_duration
	grass_changed.emit(index)
	return true


func _update_grass(delta: float) -> void:
	for index in range(grass_bites.size()):
		if grass_bites[index] > 0:
			continue

		grass_regrow_remaining[index] = maxf(0.0, grass_regrow_remaining[index] - delta)
		if grass_regrow_remaining[index] <= 0.00001:
			grass_regrow_remaining[index] = 0.0
			grass_bites[index] = config.grass_bites
			grass_changed.emit(index)


func request_spawn(kind: AnimalController.Kind, count: int) -> void:
	_pending_spawns.append(Vector2i(kind, count))


func request_reset() -> void:
	_reset_pending = true


func request_single_step() -> void:
	if paused:
		_step_pending = true


func random_position() -> Vector2:
	return Vector2(
		rng.randf_range(24.0, config.arena_size.x - 24.0),
		rng.randf_range(100.0, config.arena_size.y - 65.0))


func _physics_process(delta: float) -> void:
	if not running:
		return

	# 1) 在遍历实体之前处理调试命令
	if _reset_pending:
		reset_simulation()
	for request in _pending_spawns:
		entity_service.spawn(request.x, request.y)
	_pending_spawns.clear()

	if not paused:
		simulate_step(delta)
	elif _step_pending:
		_step_pending = false
		simulate_step(1.0 / 60.0)


func simulate_step(delta: float) -> void:
	var started := Time.get_ticks_usec()
	# 1) 更新草丛和本步空间索引，再统一执行感知与行为树
	_update_grass(delta)
	entity_service.rebuild_spatial_index()
	for animal in entity_service.entities:
		if animal.alive:
			animal.perceive(delta)
	var perceived := Time.get_ticks_usec()

	for animal in entity_service.entities:
		if animal.alive:
			animal.decide(delta)
	var decided := Time.get_ticks_usec()

	# 2) 所有角色移动后结算交互，死亡立即生效，释放延后处理
	for animal in entity_service.entities:
		animal.move(delta)
	for animal in entity_service.entities:
		if animal.alive:
			animal.resolve_interactions(delta)
	entity_service.remove_expired()

	simulation_time += delta
	step_count += 1
	var finished := Time.get_ticks_usec()
	last_perception_ms = (perceived - started) / 1000.0
	last_decision_ms = (decided - perceived) / 1000.0
	last_movement_ms = (finished - decided) / 1000.0
	last_step_ms = (finished - started) / 1000.0
	simulation_stepped.emit()


func _process(_delta: float) -> void:
	if running:
		debug_service.refresh()
		if is_instance_valid(hud):
			hud.refresh()

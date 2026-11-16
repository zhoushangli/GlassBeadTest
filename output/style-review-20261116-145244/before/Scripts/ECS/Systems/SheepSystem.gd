class_name SheepSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func perceive_batch(delta: float) -> void:
	var started_at := Time.get_ticks_usec()
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var context := common.perception_context(delta)
	context.panic_duration = g_gameplayEngine.config.sheep.panic_duration
	context.common = common
	var jobs: JobService = g_gameplayEngine.job_service
	var prepared_at := Time.get_ticks_usec()
	jobs.run_batches(&"Sheep", g_gameplayEngine.entity_service.sheep_rows, SheepPerceptionJob, context, self)
	jobs.record_stage(&"Sheep", started_at, prepared_at)

func apply_batch(output: Dictionary, delta: float) -> void:
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.submit_stats(output.stats)
	for result: Dictionary in output.entries:
		var row: int = result.row
		common.submit_perception(result, delta)
		data.sheep_local_flock_center[row] = result.center
		data.sheep_neighbor_count[row] = result.count
		data.sheep_alignment[row] = result.alignment
		data.sheep_panic_strength[row] = result.panic
		data.motion_intent[row] = AnimalData.MotionIntent.SHEEP
		if g_gameplayEngine.config.sheep.wander_weight > 0.0:
			common.get_wander_point(data.handles[row], 85.0)

func calculate_batch(output: Dictionary, rows: PackedInt32Array, context: Dictionary) -> void:
	var stats := AnimalSystem.batch_stats(context)
	var entries: Array[Dictionary] = []
	var grid: Dictionary = context.grid
	var common: AnimalSystem = context.common
	for row in rows:
		var result := common.calculate_perception(row, context, stats)
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		var cell: int = grid.row_cells[row]
		var count: int = grid.flock_counts[cell] - 1
		var aligned: int = grid.alignment_counts[cell] - 1
		result.center = (grid.flock_sums[cell] - grid.positions[row]) / count if count > 0 else grid.positions[row]
		result.count = count
		result.alignment = (grid.alignment_sums[cell] - grid.velocities[row]) / aligned if aligned > 0 else Vector2.ZERO
		result.panic = maxf(0.0, data.sheep_panic_strength[row] - context.delta / context.panic_duration) if context.panic_duration > 0.0 else 0.0
		if stats.detailed:
			stats.hotspots.NeighborScan += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.NeighborScan += 1
		entries.append(result)
	output.entries = entries
	output.stats = stats

func _scan_neighbors(animal: AnimalEntity, grid: GridService) -> void:
	var row := animal.row
	var cell := grid.row_cells[row]
	var count := grid.flock_counts[cell] - 1
	var aligned := grid.alignment_counts[cell] - 1
	data.sheep_local_flock_center[row] = (grid.flock_position_sums[cell] - grid.perception_positions[row]) / count if count > 0 else grid.perception_positions[row]
	data.sheep_neighbor_count[row] = count
	data.sheep_alignment[row] = (grid.alignment_velocity_sums[cell] - grid.perception_velocities[row]) / aligned if aligned > 0 else Vector2.ZERO

func receive_howl(animal: AnimalEntity, source: Vector2) -> void:
	var row := animal.row
	data.sheep_panic_source[row] = source
	data.sheep_panic_strength[row] = 1.0 if g_gameplayEngine.config.sheep.panic_duration > 0.0 else 0.0

func perceive(animal: AnimalEntity, delta: float) -> void:
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	g_gameplayEngine.animal_system.perceive(animal, delta)
	data.sheep_panic_strength[row] = maxf(0.0, data.sheep_panic_strength[row] - delta / settings.panic_duration) if settings.panic_duration > 0.0 else 0.0
	data.motion_intent[row] = AnimalData.MotionIntent.SHEEP
	if settings.wander_weight > 0.0:
		g_gameplayEngine.animal_system.get_wander_point(animal, 85.0)

func update_steering(delta: float) -> void:
	var settings: SheepConfig = g_gameplayEngine.config.sheep
	var margin := 40.0
	var lower := Vector2(12.0, 94.0) + Vector2.ONE * margin
	var upper: Vector2 = g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0) - Vector2.ONE * margin
	for row in g_gameplayEngine.entity_service.sheep_rows:
		var cohesion := (data.sheep_local_flock_center[row] - data.motion_position[row]).normalized() if data.sheep_neighbor_count[row] > 0 else Vector2.ZERO
		var flock := data.sheep_alignment[row] * settings.alignment_weight + cohesion * settings.move_speed * settings.cohesion_weight
		var panic := data.sheep_panic_strength[row]
		var danger := maxf(data.sheep_threat_strength[row], panic)
		var escape := (data.sheep_threat_direction[row] + (data.motion_position[row] - data.sheep_panic_source[row]).normalized() * panic).limit_length(1.0)
		if danger > 0.0 and escape.is_zero_approx():
			escape = Vector2.from_angle(data.identity_entity_id[row] * 2.399963) * danger
		var dog := data.sheep_dog_pressure[row]
		var speed := lerpf(lerpf(settings.move_speed * settings.idle_speed_scale, settings.move_speed, minf(1.0, dog.length())), settings.flee_speed, danger)
		var steering := escape * speed * settings.wolf_pressure_weight
		steering += dog * speed * settings.dog_pressure_weight * (1.0 - danger)
		steering += flock * lerpf(1.0, 0.25, danger)
		steering += (data.motion_wander_point[row] - data.motion_position[row]).normalized() * speed * settings.wander_weight * (1.0 - danger)
		steering += data.motion_separation[row] * settings.move_speed * settings.separation_weight
		var boundary := (lower - data.motion_position[row]).max(Vector2.ZERO) - (data.motion_position[row] - upper).max(Vector2.ZERO)
		steering += boundary / margin * speed * 2.0
		data.motion_desired_velocity[row] = data.motion_velocity[row].lerp(steering.limit_length(speed), minf(1.0, settings.steering_rate * delta))
		data.motion_speed_limit[row] = speed
		data.motion_movement_goal[row] = data.motion_position[row] + data.motion_desired_velocity[row]

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	return "Neighbors %d | Wolf %.2f | Dog %.2f | Panic %.2f | Speed %.1f" % [data.sheep_neighbor_count[row], data.sheep_threat_strength[row], data.sheep_dog_pressure[row].length(), data.sheep_panic_strength[row], data.motion_velocity[row].length()]

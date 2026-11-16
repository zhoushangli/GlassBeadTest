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

func apply_batch(job: SheepPerceptionJob) -> void:
	var delta: float = job.context.delta
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.submit_stats(job.stats)
	var rows := job.rows
	var remaining := job.remaining
	var refresh := job.refresh_flags
	var separation := job.separations
	var centers := job.centers
	var counts := job.neighbor_counts
	var alignment := job.alignments
	var panic := job.panic_strengths
	var perception_remaining := data.memory_perception_remaining
	var perception_ready := data.memory_perception_ready
	var wander_remaining := data.motion_wander_remaining
	var local_centers := data.sheep_local_flock_center
	var neighbor_counts := data.sheep_neighbor_count
	var alignments := data.sheep_alignment
	var panic_strengths := data.sheep_panic_strength
	var intents := data.motion_intent
	var separations := data.motion_separation
	var wander: bool = g_gameplayEngine.config.sheep.wander_weight > 0.0
	for index in range(rows.size()):
		var row := rows[index]
		perception_remaining[row] = remaining[index]
		perception_ready[row] = 1
		wander_remaining[row] -= delta
		if refresh[index]:
			data.memory_nearby[row] = job.nearby_members.slice(job.nearby_offsets[index], job.nearby_offsets[index + 1])
			separations[row] = separation[index]
		local_centers[row] = centers[index]
		neighbor_counts[row] = counts[index]
		alignments[row] = alignment[index]
		panic_strengths[row] = panic[index]
		intents[row] = AnimalData.MotionIntent.SHEEP
		if wander:
			common.get_wander_point(data.handles[row], 85.0)

func calculate_batch(job: SheepPerceptionJob) -> void:
	job.resize_output()
	var rows := job.rows
	var context := job.context
	var stats := AnimalSystem.batch_stats(context)
	var grid: Dictionary = context.grid
	var positions: PackedVector2Array = grid.positions
	var velocities: PackedVector2Array = grid.velocities
	var kinds: PackedInt32Array = grid.kinds
	var cells: PackedInt32Array = grid.row_cells
	var flock_counts: PackedInt32Array = grid.flock_counts
	var flock_sums: PackedVector2Array = grid.flock_sums
	var alignment_counts: PackedInt32Array = grid.alignment_counts
	var alignment_sums: PackedVector2Array = grid.alignment_sums
	var perception_remaining := data.memory_perception_remaining
	var perception_ready := data.memory_perception_ready
	var ids := data.identity_entity_id
	var separations := data.motion_separation
	var panic_strengths := data.sheep_panic_strength
	var delta: float = context.delta
	var interval: float = context.interval
	var distance_limit: float = context.distance
	var panic_duration: float = context.panic_duration
	var remaining := job.remaining
	var refresh := job.refresh_flags
	var separation := job.separations
	var centers := job.centers
	var counts := job.neighbor_counts
	var alignment := job.alignments
	var panic := job.panic_strengths
	for index in range(rows.size()):
		var row := rows[index]
		remaining[index] = perception_remaining[row] - delta
		refresh[index] = int(not perception_ready[row] or remaining[index] <= 0.0)
		var nearby := data.memory_nearby[row]
		separation[index] = separations[row]
		if refresh[index]:
			nearby = GridService.query_snapshot(positions[row], distance_limit, AnimalEntity.Kind.SHEEP, grid, stats)
			var started_at := Time.get_ticks_usec() if stats.detailed else 0
			var force := Vector2.ZERO
			if distance_limit > 0.0:
				for other in nearby:
					if other == row or kinds[other] != AnimalEntity.Kind.SHEEP:
						continue
					var offset := positions[row] - positions[other]
					var squared := offset.length_squared()
					if squared >= distance_limit * distance_limit:
						continue
					var distance := sqrt(squared)
					var direction := offset.normalized()
					if distance < 0.001:
						direction = Vector2.RIGHT if ids[row] < ids[other] else Vector2.LEFT
					force += direction * (1.0 - distance / distance_limit)
			separation[index] = force
			if stats.detailed:
				stats.hotspots.Separation += (Time.get_ticks_usec() - started_at) / 1000.0
				stats.calls.Separation += 1
			remaining[index] = interval
			if not perception_ready[row]:
				remaining[index] *= fmod(ids[row] * 0.618034, 1.0)
		job.nearby_members.append_array(nearby)
		job.nearby_offsets[index + 1] = job.nearby_members.size()

		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		var cell := cells[row]
		var count := flock_counts[cell] - 1
		var aligned := alignment_counts[cell] - 1
		centers[index] = (flock_sums[cell] - positions[row]) / count if count > 0 else positions[row]
		counts[index] = count
		alignment[index] = (alignment_sums[cell] - velocities[row]) / aligned if aligned > 0 else Vector2.ZERO
		panic[index] = maxf(0.0, panic_strengths[row] - delta / panic_duration) if panic_duration > 0.0 else 0.0
		if stats.detailed:
			stats.hotspots.NeighborScan += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.NeighborScan += 1
	job.stats = stats

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
	data.sheep_panic_revision[row] += 1
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

static func calculate_snapshot(job: SheepPerceptionJob) -> void:
	job.resize_output()
	var snapshot := job.context
	job.stats = AnimalSystem.batch_stats(snapshot)
	var wolves := GridService.snapshot_pressure(AnimalEntity.Kind.WOLF, snapshot, snapshot.grid)
	var dogs := GridService.snapshot_pressure(AnimalEntity.Kind.SHEEPDOG, snapshot, snapshot.grid)
	var grid: Dictionary = snapshot.grid
	var settings: Dictionary = snapshot.settings
	var positions: PackedVector2Array = snapshot.motion_position
	var velocities: PackedVector2Array = snapshot.motion_velocity
	var panic_strengths: PackedFloat64Array = snapshot.sheep_panic_strength
	var panic_sources: PackedVector2Array = snapshot.sheep_panic_source
	var wander_points: PackedVector2Array = snapshot.motion_wander_point
	var ids: PackedInt64Array = snapshot.identity_entity_id
	for index in range(job.rows.size()):
		var row := job.rows[index]
		job.refresh_flags[index] = int(not snapshot.memory_perception_ready[row] or snapshot.memory_perception_remaining[row] <= 0.0)
		job.separations[index] = AnimalSystem.snapshot_separation(row, snapshot, job.stats, bool(job.refresh_flags[index]))
		var cell: int = grid.row_cells[row]
		job.neighbor_counts[index] = grid.flock_counts[cell] - 1
		var aligned: int = grid.alignment_counts[cell] - 1
		job.centers[index] = (grid.flock_sums[cell] - positions[row]) / job.neighbor_counts[index] if job.neighbor_counts[index] > 0 else positions[row]
		job.alignments[index] = (grid.alignment_sums[cell] - velocities[row]) / aligned if aligned > 0 else Vector2.ZERO
		job.threat_directions[index] = wolves.sheep_threat_direction[row]
		job.threat_strengths[index] = wolves.sheep_threat_strength[row]
		job.dog_pressures[index] = dogs.sheep_dog_pressure[row]
		var cohesion: Vector2 = (job.centers[index] - positions[row]).normalized() if job.neighbor_counts[index] > 0 else Vector2.ZERO
		var flock: Vector2 = job.alignments[index] * settings.alignment_weight + cohesion * settings.move_speed * settings.cohesion_weight
		var panic: float = panic_strengths[row]
		var danger := maxf(job.threat_strengths[index], panic)
		var escape: Vector2 = (job.threat_directions[index] + (positions[row] - panic_sources[row]).normalized() * panic).limit_length(1.0)
		if danger > 0.0 and escape.is_zero_approx():
			escape = Vector2.from_angle(ids[row] * 2.399963) * danger
		job.speed_limits[index] = lerpf(lerpf(settings.move_speed * settings.idle_speed_scale, settings.move_speed, minf(1.0, job.dog_pressures[index].length())), settings.flee_speed, danger)
		var steering: Vector2 = escape * job.speed_limits[index] * settings.wolf_pressure_weight
		steering += job.dog_pressures[index] * job.speed_limits[index] * settings.dog_pressure_weight * (1.0 - danger)
		steering += flock * lerpf(1.0, 0.25, danger)
		steering += (wander_points[row] - positions[row]).normalized() * job.speed_limits[index] * settings.wander_weight * (1.0 - danger)
		steering += job.separations[index] * settings.move_speed * settings.separation_weight
		job.desired_velocities[index] = steering.limit_length(job.speed_limits[index])
	job.wolf_pressure = wolves.field
	job.dog_pressure = dogs.field
	job.pressure_source_pairs = wolves.pairs + dogs.pairs

func apply_decision(job: SheepPerceptionJob) -> void:
	var snapshot := job.context
	g_gameplayEngine.animal_system.submit_stats(job.stats)
	var slots: PackedInt32Array = snapshot.row_to_slot
	var uids: PackedInt64Array = snapshot.identity_uid
	var revisions: PackedInt64Array = snapshot.sheep_panic_revision
	var ready: PackedByteArray = snapshot.memory_perception_ready
	var ids: PackedInt64Array = snapshot.identity_entity_id
	var slot_rows := data.slot_to_row
	var live_uids := data.identity_uid
	var alive := data.identity_alive
	var live_revisions := data.sheep_panic_revision
	var centers := data.sheep_local_flock_center
	var counts := data.sheep_neighbor_count
	var alignments := data.sheep_alignment
	var threats := data.sheep_threat_direction
	var strengths := data.sheep_threat_strength
	var dogs := data.sheep_dog_pressure
	var intents := data.motion_intent
	var velocities := data.motion_desired_velocity
	var speeds := data.motion_speed_limit
	var separations := data.motion_separation
	var perception_ready := data.memory_perception_ready
	var remaining := data.memory_perception_remaining
	var age: float = g_gameplayEngine.simulation_time - snapshot.time
	for result_index in range(job.rows.size()):
		var index := job.rows[result_index]
		var slot := slots[index]
		if slot >= slot_rows.size():
			continue

		var row := slot_rows[slot]
		if row < 0 or row >= data.active_count or not alive[row] or live_uids[row] != uids[index] or live_revisions[row] != revisions[index]:
			continue

		if job.refresh_flags[result_index]:
			separations[row] = job.separations[result_index]
			perception_ready[row] = 1
			var interval: float = snapshot.interval
			if not ready[index]:
				interval *= fmod(ids[index] * 0.618034, 1.0)
			remaining[row] = maxf(0.0, interval - age)
		centers[row] = job.centers[result_index]
		counts[row] = job.neighbor_counts[result_index]
		alignments[row] = job.alignments[result_index]
		threats[row] = job.threat_directions[result_index]
		strengths[row] = job.threat_strengths[result_index]
		dogs[row] = job.dog_pressures[result_index]
		intents[row] = AnimalData.MotionIntent.SHEEP
		velocities[row] = job.desired_velocities[result_index]
		speeds[row] = job.speed_limits[result_index]
	g_gameplayEngine.grid_service.wolf_pressure = job.wolf_pressure
	g_gameplayEngine.grid_service.dog_pressure = job.dog_pressure
	g_gameplayEngine.grid_service.pressure_source_pairs = job.pressure_source_pairs

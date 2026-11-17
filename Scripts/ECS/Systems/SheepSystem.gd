class_name SheepSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func receive_howl(animal: AnimalEntity, source: Vector2) -> void:
	var row := animal.row
	data.sheep_panic_revision[row] += 1
	data.sheep_panic_source[row] = source
	data.sheep_panic_strength[row] = 1.0 if g_gameplayEngine.config.sheep.panic_duration > 0.0 else 0.0

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	return "Neighbors %d | Wolf %.2f | Dog %.2f | Panic %.2f | Speed %.1f" % [data.sheep_neighbor_count[row], data.sheep_threat_strength[row], data.sheep_dog_pressure[row].length(), data.sheep_panic_strength[row], data.motion_velocity[row].length()]

func apply_decision(job: SheepPerceptionJob) -> void:
	var snapshot := job.snapshot
	g_gameplayEngine.animal_system.submit_stats(job.stats)
	var animal_ids: PackedInt64Array = snapshot.identity_animal_id
	var revisions: PackedInt64Array = snapshot.sheep_panic_revision
	var ready: PackedByteArray = snapshot.memory_perception_ready
	var ids: PackedInt64Array = snapshot.identity_entity_id
	var slot_rows := data.slot_to_row
	var live_ids := data.identity_animal_id
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

	# 1) Reject reused slots and results captured before a newer howl changed panic.
	for result_index in range(job.rows.size()):
		var index := job.rows[result_index]
		var id := animal_ids[index]
		var slot := AnimalID.get_slot(id)
		if slot >= slot_rows.size():
			continue

		var row := slot_rows[slot]
		if row < 0 or row >= data.active_count or not alive[row] or live_ids[row] != id or live_revisions[row] != revisions[index]:
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

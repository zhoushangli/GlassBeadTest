class_name SheepPerceptionJob
extends Job

var separations := PackedVector2Array()
var refresh_flags := PackedByteArray()
var remaining := PackedFloat64Array()

var centers := PackedVector2Array()
var alignments := PackedVector2Array()
var threat_directions := PackedVector2Array()
var threat_strengths := PackedFloat64Array()
var dog_pressures := PackedVector2Array()
var desired_velocities := PackedVector2Array()
var speed_limits := PackedFloat64Array()
var neighbor_counts := PackedInt32Array()
var panic_strengths := PackedFloat64Array()

var wolf_pressure := PackedVector2Array()
var dog_pressure := PackedVector2Array()
var pressure_source_pairs: int = 0

var nearby_offsets := PackedInt32Array()
var nearby_members := PackedInt32Array()

func apply_result() -> void:
	if snapshot != null:
		var started_at := Time.get_ticks_usec()
		_apply_decision()
		record_application(0, started_at)
		return

	assert(false, "Sheep batch results require the reference implementation")

func resize_output() -> void:
	separations.resize(rows.size())
	refresh_flags.resize(rows.size())
	remaining.resize(rows.size())
	centers.resize(rows.size())
	alignments.resize(rows.size())
	threat_directions.resize(rows.size())
	threat_strengths.resize(rows.size())
	dog_pressures.resize(rows.size())
	desired_velocities.resize(rows.size())
	speed_limits.resize(rows.size())
	neighbor_counts.resize(rows.size())
	panic_strengths.resize(rows.size())
	nearby_offsets.resize(rows.size() + 1)
	nearby_offsets.fill(0)
	nearby_members.clear()

func _apply_decision() -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	submit_stats(stats)
	var animal_ids: PackedInt64Array = snapshot.identity.animal_id
	var revisions: PackedInt64Array = snapshot.sheep.panic_revision
	var ready: PackedByteArray = snapshot.memory.perception_ready
	var ids: PackedInt64Array = snapshot.identity.entity_id
	var slot_rows := data.index.slot_to_row
	var live_ids := data.identity.animal_id
	var alive := data.identity.alive
	var live_revisions := data.sheep.panic_revision
	var centers := data.sheep.local_flock_center
	var counts := data.sheep.neighbor_count
	var alignments := data.sheep.alignment
	var threats := data.sheep.threat_direction
	var strengths := data.sheep.threat_strength
	var dogs := data.sheep.dog_pressure
	var intents := data.motion.intent
	var velocities := data.motion.desired_velocity
	var speeds := data.motion.speed_limit
	var separations := data.motion.separation
	var perception_ready := data.memory.perception_ready
	var remaining := data.memory.perception_remaining
	var age: float = g_gameplayEngine.simulation_time - snapshot.time
	var active_count := data.index.active_count

	# 1) Reject reused slots and results captured before a newer howl changed panic.
	for result_index in range(rows.size()):
		var index := rows[result_index]
		var id := animal_ids[index]
		var slot := AnimalID.get_slot(id)
		if slot >= slot_rows.size():
			continue

		var row := slot_rows[slot]
		if row < 0 or row >= active_count or not alive[row] or live_ids[row] != id or live_revisions[row] != revisions[index]:
			continue

		if refresh_flags[result_index]:
			separations[row] = self.separations[result_index]
			perception_ready[row] = 1
			var interval: float = snapshot.interval
			if not ready[index]:
				interval *= fmod(ids[index] * 0.618034, 1.0)
			remaining[row] = maxf(0.0, interval - age)

		centers[row] = self.centers[result_index]
		counts[row] = neighbor_counts[result_index]
		alignments[row] = self.alignments[result_index]
		threats[row] = threat_directions[result_index]
		strengths[row] = threat_strengths[result_index]
		dogs[row] = dog_pressures[result_index]
		intents[row] = AnimalData.MotionIntent.SHEEP
		velocities[row] = desired_velocities[result_index]
		speeds[row] = speed_limits[result_index]

	spatial.pressure.wolf = wolf_pressure
	spatial.pressure.dog = dog_pressure
	spatial.pressure.source_pairs = pressure_source_pairs

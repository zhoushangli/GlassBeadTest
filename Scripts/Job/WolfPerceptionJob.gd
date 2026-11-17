class_name WolfPerceptionJob
extends Job

var dogs := PackedInt32Array()

var separations := PackedVector2Array()
var refresh_flags := PackedByteArray()
var remaining := PackedFloat64Array()
var target_rows := PackedInt32Array()
var visible_flags := PackedByteArray()
var last_positions := PackedVector2Array()
var last_velocities := PackedVector2Array()

var threat_rows := PackedInt32Array()
var prey_rows := PackedInt32Array()
var unseen_elapsed := PackedFloat64Array()

var nearby_offsets := PackedInt32Array()
var nearby_members := PackedInt32Array()

func execute() -> void:
	if snapshot != null:
		var started := Time.get_ticks_usec()
		resize_output()
		stats = AnimalSystem.batch_stats(snapshot.stats, snapshot.detailed)
		for index in range(rows.size()):
			var row := rows[index]
			refresh_flags[index] = int(not snapshot.memory_perception_ready[row] or snapshot.memory_perception_remaining[row] <= 0.0)
			separations[index] = AnimalSystem.snapshot_separation(row, snapshot, grid, stats, bool(refresh_flags[index]))
			target_rows[index] = snapshot.memory_target[row]
			var target_row := target_rows[index]
			var visible := target_row >= 0 and AnimalSystem.snapshot_can_see(row, snapshot.motion_position[target_row], snapshot)
			visible_flags[index] = int(visible)
			last_positions[index] = snapshot.motion_position[target_row] if visible else snapshot.memory_last_seen_position[row]
			last_velocities[index] = snapshot.motion_velocity[target_row] if visible else snapshot.memory_last_seen_velocity[row]
			var best := -1
			var distance: float = snapshot.config.wolf.dog_threat_distance * (2.0 if snapshot.wolf_retreating[row] else 1.0)
			for other in snapshot.dogs:
				var next: float = snapshot.motion_position[row].distance_to(snapshot.motion_position[other])
				if next < distance or (is_equal_approx(next, distance) and best >= 0 and snapshot.identity_entity_id[other] < snapshot.identity_entity_id[best]):
					best = other
					distance = next
			threat_rows[index] = best
			prey_rows[index] = -1
			if not snapshot.wolf_hunting[row] and not snapshot.wolf_resting[row] and not snapshot.wolf_retreating[row] and best < 0:
				distance = INF
				for other in GridService.query_snapshot(snapshot.motion_position[row], snapshot.config.wolf.perception_radius, AnimalEntity.Kind.SHEEP, grid, stats):
					if not AnimalSystem.snapshot_can_see(row, snapshot.motion_position[other], snapshot):
						continue

					var next: float = snapshot.motion_position[row].distance_squared_to(snapshot.motion_position[other])
					if next < distance or (is_equal_approx(next, distance) and prey_rows[index] >= 0 and snapshot.identity_entity_id[other] < snapshot.identity_entity_id[prey_rows[index]]):
						prey_rows[index] = other
						distance = next
		execute_ms = (Time.get_ticks_usec() - started) / 1000.0
		return

	target.calculate_batch(self)

func apply_result() -> void:
	if snapshot != null:
		target.apply_decision(self)
		return

	target.apply_batch(self)

func resize_output() -> void:
	separations.resize(rows.size())
	refresh_flags.resize(rows.size())
	remaining.resize(rows.size())
	target_rows.resize(rows.size())
	visible_flags.resize(rows.size())
	last_positions.resize(rows.size())
	last_velocities.resize(rows.size())
	threat_rows.resize(rows.size())
	prey_rows.resize(rows.size())
	unseen_elapsed.resize(rows.size())
	nearby_offsets.resize(rows.size() + 1)
	nearby_offsets.fill(0)
	nearby_members.clear()

func copy_input(source: Job) -> void:
	super.copy_input(source)
	dogs = (source as WolfPerceptionJob).dogs

func release_input() -> void:
	super.release_input()
	dogs = PackedInt32Array()

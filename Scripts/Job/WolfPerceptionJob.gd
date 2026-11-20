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
		stats = Job.batch_stats(snapshot.stats, snapshot.detailed)

		# 1) Evaluate visibility and dog threats without reading live animal storage.
		for index in range(rows.size()):
			var row := rows[index]
			refresh_flags[index] = int(not snapshot.memory.perception_ready[row] or snapshot.memory.perception_remaining[row] <= 0.0)
			separations[index] = Job.snapshot_separation(row, snapshot, grid, stats, bool(refresh_flags[index]))
			target_rows[index] = snapshot.memory.target[row]
			var target_row := target_rows[index]
			var visible := target_row >= 0 and Job.snapshot_can_see(row, snapshot.motion.position[target_row], snapshot)
			visible_flags[index] = int(visible)
			last_positions[index] = snapshot.motion.position[target_row] if visible else snapshot.memory.last_seen_position[row]
			last_velocities[index] = snapshot.motion.velocity[target_row] if visible else snapshot.memory.last_seen_velocity[row]

			var best := -1
			var distance: float = snapshot.config.wolf.dog_threat_distance * (2.0 if snapshot.wolf.retreating[row] else 1.0)
			for other in snapshot.index.dog_rows:
				var next: float = snapshot.motion.position[row].distance_to(snapshot.motion.position[other])
				if next < distance or (is_equal_approx(next, distance) and best >= 0 and snapshot.identity.entity_id[other] < snapshot.identity.entity_id[best]):
					best = other
					distance = next

			threat_rows[index] = best
			prey_rows[index] = -1
			if not snapshot.wolf.hunting[row] and not snapshot.wolf.resting[row] and not snapshot.wolf.retreating[row] and best < 0:
				distance = INF
				for other in GridSnapshot.query_snapshot(snapshot.motion.position[row], snapshot.config.wolf.perception_radius, AnimalEntity.Kind.SHEEP, grid, stats):
					if not Job.snapshot_can_see(row, snapshot.motion.position[other], snapshot):
						continue

					var next: float = snapshot.motion.position[row].distance_squared_to(snapshot.motion.position[other])
					if next < distance or (is_equal_approx(next, distance) and prey_rows[index] >= 0 and snapshot.identity.entity_id[other] < snapshot.identity.entity_id[prey_rows[index]]):
						prey_rows[index] = other
						distance = next

		execute_ms = (Time.get_ticks_usec() - started) / 1000.0
		return

	_calculate_batch()

func apply_result() -> void:
	if snapshot != null:
		var started_at := Time.get_ticks_usec()
		_apply_decision()
		record_application(1, started_at)
		return

	_apply_batch()

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

func _calculate_batch() -> void:
	var data := batch_input
	resize_output()
	var stats := Job.batch_stats(spatial_stats, detailed)
	for result_index in range(rows.size()):
		var row := rows[result_index]
		calculate_perception(row, self, stats, result_index, remaining, refresh_flags, separations, nearby_offsets, nearby_members)
		var best: int = -1
		var distance: float = config.wolf.dog_threat_distance * (2.0 if data.wolf.retreating[row] else 1.0)
		for dog_row in dogs:
			var next_distance := data.motion.position[row].distance_to(data.motion.position[dog_row])
			if next_distance < distance or (is_equal_approx(next_distance, distance) and best >= 0 and data.identity.entity_id[dog_row] < data.identity.entity_id[best]):
				best = dog_row
				distance = next_distance

		threat_rows[result_index] = best
		calculate_observation(row, delta, self, result_index)
		prey_rows[result_index] = -1
		var resting: bool = data.wolf.resting[row] and data.wolf.rest_elapsed[row] + delta < config.wolf.rest_duration
		if not data.wolf.hunting[row] and not resting and best < 0 and not data.wolf.retreating[row]:
			var started_at := Time.get_ticks_usec() if stats.detailed else 0
			distance = INF
			for index in GridSnapshot.query_snapshot(data.motion.position[row], config.wolf.perception_radius, AnimalEntity.Kind.SHEEP, grid, stats):
				var point: Vector2 = grid.cells.positions[index]
				if not can_see(data.index.handles[row], point):
					continue

				var next_distance := data.motion.position[row].distance_squared_to(point)
				if next_distance < distance or (is_equal_approx(next_distance, distance) and prey_rows[result_index] >= 0 and data.identity.entity_id[index] < data.identity.entity_id[prey_rows[result_index]]):
					prey_rows[result_index] = index
					distance = next_distance
			if stats.detailed:
				stats.hotspots.WolfTarget += (Time.get_ticks_usec() - started_at) / 1000.0
				stats.calls.WolfTarget += 1

	self.stats = stats

func _apply_batch() -> void:
	submit_stats(stats)
	for index in range(rows.size()):
		var row := rows[index]
		var animal := data.index.handles[row]
		var settings: WolfConfig = data.settings[row]
		submit_perception(row, remaining[index], bool(refresh_flags[index]), nearby_members.slice(nearby_offsets[index], nearby_offsets[index + 1]), separations[index], delta)
		for strategy in range(4):
			data.wolf.strategy_failures[row][strategy] = maxf(0.0, data.wolf.strategy_failures[row][strategy] - settings.strategy_decay * delta)
		data.wolf.howl_elapsed[row] += delta
		if data.wolf.resting[row]:
			data.wolf.rest_elapsed[row] += delta
			data.wolf.resting[row] = int(data.wolf.rest_elapsed[row] < settings.rest_duration)
		data.wolf.nearest_threat[row] = data.index.handles[threat_rows[index]] if threat_rows[index] >= 0 else null

		if data.wolf.hunting[row]:
			data.wolf.hunt_elapsed[row] += delta
			submit_observation(row, bool(visible_flags[index]), unseen_elapsed[index], last_positions[index], last_velocities[index])
			if data.live(data.memory.target[row]) == null or data.wolf.hunt_elapsed[row] >= settings.hunt_duration or (not data.memory.target_visible[row] and data.memory.unseen_elapsed[row] >= settings.memory_duration):
				g_gameplayEngine.wolf_system.end_hunt(animal, false)

		if not data.wolf.hunting[row] and not data.wolf.resting[row] and data.live(data.wolf.nearest_threat[row]) == null and not data.wolf.retreating[row] and prey_rows[index] >= 0:
			g_gameplayEngine.wolf_system.begin_hunt(animal, data.index.handles[prey_rows[index]])

func _apply_decision() -> void:
	submit_stats(stats)

	# 1) Revalidate life identities and hunt state before applying delayed perception.
	for index in range(rows.size()):
		var snapshot_row := rows[index]
		var animal := snapshot_animal(snapshot, snapshot_row)
		if animal == null:
			continue

		var row := animal.row
		if data.wolf.hunting[row] != snapshot.wolf.hunting[snapshot_row] or data.wolf.resting[row] != snapshot.wolf.resting[snapshot_row] or data.wolf.retreating[row] != snapshot.wolf.retreating[snapshot_row] or data.live(data.memory.target[row]) != snapshot_animal(snapshot, target_rows[index]):
			continue

		var threat := snapshot_animal(snapshot, threat_rows[index])
		var prey := snapshot_animal(snapshot, prey_rows[index])
		if (threat_rows[index] >= 0 and threat == null) or (prey_rows[index] >= 0 and prey == null) or (target_rows[index] >= 0 and snapshot_animal(snapshot, target_rows[index]) == null):
			continue

		apply_snapshot_perception(row, snapshot_row, snapshot, separations[index], bool(refresh_flags[index]), target_rows[index], bool(visible_flags[index]), last_positions[index], last_velocities[index])
		data.wolf.nearest_threat[row] = threat
		if prey != null and not data.wolf.hunting[row] and not data.wolf.resting[row] and not data.wolf.retreating[row] and threat == null:
			g_gameplayEngine.wolf_system.begin_hunt(animal, prey)
		g_gameplayEngine.advance_decision(animal)

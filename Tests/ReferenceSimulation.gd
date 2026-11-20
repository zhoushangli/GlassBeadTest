extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func perceive_batch(delta: float) -> void:
	var started_at := Time.get_ticks_usec()
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var input: SheepJob = SheepJob.new()
	input.capture_batch(delta)

	var jobs: JobService = g_gameplayEngine.job_service
	var prepared_at := Time.get_ticks_usec()
	input.reference = self
	jobs.run_batches(&"Sheep", g_gameplayEngine.data_service.animals.index.sheep_rows, SheepJob, input)
	jobs.record_stage(&"Sheep", started_at, prepared_at)

func apply_batch(job: SheepPerceptionJob) -> void:
	var delta: float = job.delta
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
	var perception_remaining := data.memory.perception_remaining
	var perception_ready := data.memory.perception_ready
	var wander_remaining := data.motion.wander_remaining
	var local_centers := data.sheep.local_flock_center
	var neighbor_counts := data.sheep.neighbor_count
	var alignments := data.sheep.alignment
	var panic_strengths := data.sheep.panic_strength
	var intents := data.motion.intent
	var separations := data.motion.separation
	var wander: bool = g_gameplayEngine.config.sheep.wander_weight > 0.0
	for index in range(rows.size()):
		var row := rows[index]
		perception_remaining[row] = remaining[index]
		perception_ready[row] = 1
		wander_remaining[row] -= delta
		if refresh[index]:
			data.memory.nearby[row] = job.nearby_members.slice(job.nearby_offsets[index], job.nearby_offsets[index + 1])
			separations[row] = separation[index]
		local_centers[row] = centers[index]
		neighbor_counts[row] = counts[index]
		alignments[row] = alignment[index]
		panic_strengths[row] = panic[index]
		intents[row] = AnimalData.MotionIntent.SHEEP
		if wander:
			common.get_wander_point(data.index.handles[row], 85.0)

func calculate_batch(job: SheepPerceptionJob) -> void:
	job.resize_output()
	var rows := job.rows
	var stats := Job.batch_stats(job.spatial_stats, job.detailed)
	var grid: GridSnapshot = job.grid
	var positions: PackedVector2Array = grid.cells.positions
	var velocities: PackedVector2Array = grid.cells.velocities
	var kinds: PackedInt32Array = grid.cells.kinds
	var cells: PackedInt32Array = grid.cells.row_cells
	var flock_counts: PackedInt32Array = grid.flock.counts
	var flock_sums: PackedVector2Array = grid.flock.sums
	var alignment_counts: PackedInt32Array = grid.flock.alignment_counts
	var alignment_sums: PackedVector2Array = grid.flock.alignment_sums
	var perception_remaining := data.memory.perception_remaining
	var perception_ready := data.memory.perception_ready
	var ids := data.identity.entity_id
	var separations := data.motion.separation
	var panic_strengths := data.sheep.panic_strength
	var delta: float = job.delta
	var interval: float = job.interval
	var distance_limit: float = job.distance
	var panic_duration: float = job.config.sheep.panic_duration
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
		var nearby := data.memory.nearby[row]
		separation[index] = separations[row]
		if refresh[index]:
			nearby = GridSnapshot.query_snapshot(positions[row], distance_limit, AnimalEntity.Kind.SHEEP, grid, stats)
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
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var row := animal.row
	var cell := spatial.current.cells.row_cells[row]
	var count := spatial.current.flock.counts[cell] - 1
	var aligned := spatial.current.flock.alignment_counts[cell] - 1
	data.sheep.local_flock_center[row] = (spatial.current.flock.sums[cell] - spatial.current.cells.positions[row]) / count if count > 0 else spatial.current.cells.positions[row]
	data.sheep.neighbor_count[row] = count
	data.sheep.alignment[row] = (spatial.current.flock.alignment_sums[cell] - spatial.current.cells.velocities[row]) / aligned if aligned > 0 else Vector2.ZERO

func perceive(animal: AnimalEntity, delta: float) -> void:
	var row := animal.row
	var settings: SheepConfig = data.settings[row]
	g_gameplayEngine.animal_system.perceive(animal, delta)
	_scan_neighbors(animal, g_gameplayEngine.grid_service)
	data.sheep.panic_strength[row] = maxf(0.0, data.sheep.panic_strength[row] - delta / settings.panic_duration) if settings.panic_duration > 0.0 else 0.0
	data.motion.intent[row] = AnimalData.MotionIntent.SHEEP
	if settings.wander_weight > 0.0:
		g_gameplayEngine.animal_system.get_wander_point(animal, 85.0)

func update_steering(delta: float) -> void:
	var settings: SheepConfig = g_gameplayEngine.config.sheep
	var margin := 40.0
	var lower := Vector2(12.0, 94.0) + Vector2.ONE * margin
	var upper: Vector2 = g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0) - Vector2.ONE * margin

	for row in g_gameplayEngine.data_service.animals.index.sheep_rows:
		var cohesion := (data.sheep.local_flock_center[row] - data.motion.position[row]).normalized() if data.sheep.neighbor_count[row] > 0 else Vector2.ZERO
		var flock := data.sheep.alignment[row] * settings.alignment_weight + cohesion * settings.move_speed * settings.cohesion_weight
		var panic := data.sheep.panic_strength[row]
		var danger := maxf(data.sheep.threat_strength[row], panic)
		var escape := (data.sheep.threat_direction[row] + (data.motion.position[row] - data.sheep.panic_source[row]).normalized() * panic).limit_length(1.0)
		if danger > 0.0 and escape.is_zero_approx():
			escape = Vector2.from_angle(data.identity.entity_id[row] * 2.399963) * danger

		var dog := data.sheep.dog_pressure[row]
		var speed := lerpf(lerpf(settings.move_speed * settings.idle_speed_scale, settings.move_speed, minf(1.0, dog.length())), settings.flee_speed, danger)
		var steering := escape * speed * settings.wolf_pressure_weight
		steering += dog * speed * settings.dog_pressure_weight * (1.0 - danger)
		steering += flock * lerpf(1.0, 0.25, danger)
		steering += (data.motion.wander_point[row] - data.motion.position[row]).normalized() * speed * settings.wander_weight * (1.0 - danger)
		steering += data.motion.separation[row] * settings.move_speed * settings.separation_weight

		var boundary := (lower - data.motion.position[row]).max(Vector2.ZERO) - (data.motion.position[row] - upper).max(Vector2.ZERO)
		steering += boundary / margin * speed * 2.0

		data.motion.desired_velocity[row] = data.motion.velocity[row].lerp(steering.limit_length(speed), minf(1.0, settings.steering_rate * delta))
		data.motion.speed_limit[row] = speed
		data.motion.movement_goal[row] = data.motion.position[row] + data.motion.desired_velocity[row]

func update_all_steering(delta: float) -> void:
	update_steering(delta)
	g_gameplayEngine.wolf_system.prepare_motion_goals()
	g_gameplayEngine.dog_system.prepare_motion_goals()

	for row in range(data.index.active_count):
		if data.motion.intent[row] != AnimalData.MotionIntent.POINT:
			continue

		var difference := data.motion.movement_goal[row] - data.motion.position[row]
		data.motion.desired_velocity[row] = difference.normalized() * minf(data.motion.speed_limit[row], difference.length() / maxf(delta, 0.00001))

static func calculate_snapshot(job: SheepPerceptionJob) -> void:
	# 1) Build shared wolf and dog pressure from the same immutable snapshot.
	job.resize_output()
	var snapshot := job.snapshot
	job.stats = Job.batch_stats(snapshot.stats, snapshot.detailed)
	var wolves := snapshot_pressure(AnimalEntity.Kind.WOLF, snapshot, job.grid)
	var dogs := snapshot_pressure(AnimalEntity.Kind.SHEEPDOG, snapshot, job.grid)
	var grid: GridSnapshot = job.grid
	var settings: SheepConfig = snapshot.config.sheep
	var positions: PackedVector2Array = snapshot.motion.position
	var velocities: PackedVector2Array = snapshot.motion.velocity
	var panic_strengths: PackedFloat64Array = snapshot.sheep.panic_strength
	var panic_sources: PackedVector2Array = snapshot.sheep.panic_source
	var wander_points: PackedVector2Array = snapshot.motion.wander_point
	var ids: PackedInt64Array = snapshot.identity.entity_id

	# 2) Combine local flock motion with separation, danger and wandering forces.
	for index in range(job.rows.size()):
		var row := job.rows[index]
		job.refresh_flags[index] = int(not snapshot.memory.perception_ready[row] or snapshot.memory.perception_remaining[row] <= 0.0)
		job.separations[index] = Job.snapshot_separation(row, snapshot, job.grid, job.stats, bool(job.refresh_flags[index]))
		var cell: int = grid.cells.row_cells[row]
		job.neighbor_counts[index] = grid.flock.counts[cell] - 1
		var aligned: int = grid.flock.alignment_counts[cell] - 1
		job.centers[index] = (grid.flock.sums[cell] - positions[row]) / job.neighbor_counts[index] if job.neighbor_counts[index] > 0 else positions[row]
		job.alignments[index] = (grid.flock.alignment_sums[cell] - velocities[row]) / aligned if aligned > 0 else Vector2.ZERO
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

static func update_movement(storage: AnimalData, delta: float) -> void:
	var data := storage
	var lower := Vector2(12.0, 94.0)
	var upper: Vector2 = g_gameplayEngine.config.arena_size - Vector2(12.0, 58.0)

	for row in range(data.index.active_count):
		if data.motion.intent[row] == AnimalData.MotionIntent.POINT:
			var difference := data.motion.movement_goal[row] - data.motion.position[row]
			data.motion.desired_velocity[row] = difference.normalized() * minf(data.motion.speed_limit[row], difference.length() / maxf(delta, 0.00001))
		elif data.motion.intent[row] == AnimalData.MotionIntent.SHEEP:
			var response: float = minf(1.0, g_gameplayEngine.config.sheep.steering_rate * delta)
			var boundary := (lower + Vector2.ONE * 40.0 - data.motion.position[row]).max(Vector2.ZERO) - (data.motion.position[row] - upper + Vector2.ONE * 40.0).max(Vector2.ZERO)
			var steering := data.motion.desired_velocity[row] + boundary / 40.0 * data.motion.speed_limit[row] * 2.0
			data.motion.velocity[row] = data.motion.velocity[row].lerp(steering.limit_length(data.motion.speed_limit[row]), response)

		var previous := data.motion.position[row]
		var separation := Vector2.ZERO
		if data.identity.kind[row] != AnimalEntity.Kind.SHEEP:
			separation = data.motion.separation[row] * data.settings[row].move_speed
		var desired := data.motion.velocity[row] if data.motion.intent[row] == AnimalData.MotionIntent.SHEEP else data.motion.desired_velocity[row]
		var velocity := (desired + separation).limit_length(data.motion.speed_limit[row])
		var position := (previous + velocity * delta).clamp(lower, upper)
		velocity = (position - previous) / maxf(delta, 0.00001)

		data.motion.position[row] = position
		data.motion.velocity[row] = velocity
		if not velocity.is_zero_approx():
			data.motion.facing[row] = velocity.normalized()

static func build_snapshot(snapshot: AnimalSnapshot) -> GridSnapshot:
	var grid := GridAggregateJob.build_snapshot(snapshot)
	var job: GridJob = GridJob.new()
	job.rows = grid.cells.occupied
	job.grid = grid
	job.flock_offsets = GridSnapshot.snapshot_offsets(snapshot.config.sheep.flock_radius, grid.cell_size)
	job.alignment_offsets = GridSnapshot.snapshot_offsets(snapshot.config.sheep.alignment_radius, grid.cell_size)
	job.execute()
	for index in range(job.rows.size()):
		var cell := job.rows[index]
		grid.flock.counts[cell] = job.flock_counts[index]
		grid.flock.sums[cell] = job.flock_sums[index]
		grid.flock.alignment_counts[cell] = job.alignment_counts[index]
		grid.flock.alignment_sums[cell] = job.alignment_sums[index]
	return grid

static func rebuild(grid: GridService) -> void:
	g_gameplayEngine.animal_service.refresh_config()
	GridAggregateJob.publish_grid(build_snapshot(GridAggregateJob.capture_snapshot()))

static func snapshot_pressure(kind: AnimalEntity.Kind, snapshot: AnimalSnapshot, source_grid: GridSnapshot) -> GridSnapshot.PressureResult:
	var grid := source_grid
	var positions: PackedVector2Array = grid.cells.positions
	var counts: PackedInt32Array = grid.cells.counts
	var offsets: PackedInt32Array = grid.cells.offsets
	var packed_members: PackedInt32Array = grid.cells.members
	var needed: PackedByteArray = grid.pressure.needed
	var columns: int = grid.width
	var height: int = grid.height
	var size: float = grid.cell_size
	var sample_count: int = grid.pressure.sample_count
	var data: GridSnapshot.PressureResult = GridSnapshot.PressureResult.new()
	var count := snapshot.index.sheep_rows.size() + snapshot.index.wolf_rows.size() + snapshot.index.dog_rows.size()
	data.sheep_threat_direction.resize(count)
	data.sheep_threat_strength.resize(count)
	data.sheep_dog_pressure.resize(count)
	var directions := data.sheep_threat_direction
	var strengths := data.sheep_threat_strength
	var dog_forces := data.sheep_dog_pressure
	var pairs := 0
	var is_wolf := kind == AnimalEntity.Kind.WOLF
	var radius: float = snapshot.config.sheep.wolf_pressure_distance if is_wolf else snapshot.config.sheep.herding_distance
	var radius_squared := radius * radius
	var field := PackedVector2Array()
	field.resize((columns + 1) * (height + 1))
	var sources: PackedInt32Array = snapshot.index.wolf_rows if is_wolf else snapshot.index.dog_rows
	if is_wolf:
		directions.fill(Vector2.ZERO)
		strengths.fill(0.0)
	else:
		dog_forces.fill(Vector2.ZERO)

	var affected := PackedInt32Array()
	var in_range := PackedByteArray()
	in_range.resize(count)

	# 1) Accumulate only sample points needed by sheep this step.
	for source_row in sources if radius > 0.0 else PackedInt32Array():
		var source: Vector2 = positions[source_row]
		var multiplier: float = snapshot.config.sheep.hunting_pressure_multiplier if is_wolf and snapshot.wolf.hunting[source_row] else 1.0
		if sample_count > 0:
			var first := Vector2i(((source - Vector2.ONE * radius) / size).ceil()).max(Vector2i.ZERO)
			var last := Vector2i(((source + Vector2.ONE * radius) / size).floor()).min(Vector2i(columns, height))
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var node: int = y * (columns + 1) + x
					if not needed[node]:
						continue

					var offset: Vector2 = Vector2(x, y) * size - source
					var distance_squared: float = offset.length_squared()
					if distance_squared > radius_squared:
						continue

					var distance: float = sqrt(distance_squared)
					var direction: Vector2 = offset / distance if distance > 0.0 else Vector2.ZERO
					var strength := (1.0 - distance / radius) * multiplier
					field[node] += direction * strength
					pairs += 1

		# 2) Keep the actual influence radius independent of the sampled vector.
		var first_cell := Vector2i(((source - Vector2.ONE * radius) / size).floor()).max(Vector2i.ZERO)
		var last_cell := Vector2i(((source + Vector2.ONE * radius) / size).floor()).min(Vector2i(columns - 1, height - 1))
		for y in range(first_cell.y, last_cell.y + 1):
			for x in range(first_cell.x, last_cell.x + 1):
				var bucket: int = (y * columns + x) * 3 + AnimalEntity.Kind.SHEEP
				for member in range(offsets[bucket], offsets[bucket + 1]):
					var row: int = packed_members[member]
					if counts[bucket] < GridSnapshot.PRESSURE_SHARED_MIN_SHEEP:
						var offset: Vector2 = positions[row] - source
						var distance_squared: float = offset.length_squared()
						if distance_squared > radius_squared:
							continue

						var distance: float = sqrt(distance_squared)
						var direction: Vector2 = offset / distance if distance > 0.0 else Vector2.ZERO
						if is_wolf:
							var strength := (1.0 - distance / radius) * multiplier
							strengths[row] = minf(1.0, strengths[row] + strength)
							directions[row] += direction * strength
						else:
							dog_forces[row] += direction * (1.0 - distance / radius)
					else:
						var distance: float = positions[row].distance_to(source)
						if distance > radius:
							continue

						if is_wolf:
							strengths[row] = minf(1.0, strengths[row] + (1.0 - distance / radius) * multiplier)
						if not in_range[row]:
							in_range[row] = 1
							affected.append(row)

	# 3) Interpolate the field, but never create a threat outside the true radius.
	for row in affected:
		var value := sample_snapshot_pressure(positions[row], field, grid)
		if is_wolf:
			directions[row] = value if strengths[row] > 0.0 else Vector2.ZERO
		else:
			dog_forces[row] = value

	data.field = field
	data.pairs = pairs
	return data

static func sample_snapshot_pressure(point: Vector2, field: PackedVector2Array, grid: GridSnapshot) -> Vector2:
	var coordinate: Vector2 = point / grid.cell_size
	var x := clampi(floori(coordinate.x), 0, grid.width - 1)
	var y := clampi(floori(coordinate.y), 0, grid.height - 1)
	var fraction: Vector2 = (coordinate - Vector2(x, y)).clamp(Vector2.ZERO, Vector2.ONE)
	var node: int = y * (grid.width + 1) + x
	return field[node].lerp(field[node + 1], fraction.x).lerp(field[node + grid.width + 1].lerp(field[node + grid.width + 2], fraction.x), fraction.y)

static func accumulate_pressure(grid_service: GridService, kind: AnimalEntity.Kind) -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	g_gameplayEngine.animal_service.refresh_config()
	var snapshot: AnimalSnapshot = GridAggregateJob.capture_snapshot()
	var grid := grid_service.query_context()
	grid.cells.counts = spatial.current.cells.counts
	grid.pressure.needed = spatial.current.pressure.needed
	grid.pressure.sample_count = spatial.current.pressure.sample_count
	var output := snapshot_pressure(kind, snapshot, grid)
	var data: AnimalData = g_gameplayEngine.data_service.animals
	if kind == AnimalEntity.Kind.WOLF:
		spatial.pressure.wolf = output.field
		data.sheep.threat_direction.fill(Vector2.ZERO)
		data.sheep.threat_strength.fill(0.0)
		for row in g_gameplayEngine.data_service.animals.index.sheep_rows:
			data.sheep.threat_direction[row] = output.sheep_threat_direction[row]
			data.sheep.threat_strength[row] = output.sheep_threat_strength[row]
	else:
		spatial.pressure.dog = output.field
		data.sheep.dog_pressure.fill(Vector2.ZERO)
		for row in g_gameplayEngine.data_service.animals.index.sheep_rows:
			data.sheep.dog_pressure[row] = output.sheep_dog_pressure[row]
	spatial.pressure.source_pairs += output.pairs

static func apply_cells(grid_service: GridService, result: GridJob) -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	for index in range(result.rows.size()):
		var cell: int = result.rows[index]
		spatial.current.flock.counts[cell] = result.flock_counts[index]
		spatial.current.flock.sums[cell] = result.flock_sums[index]
		spatial.current.flock.alignment_counts[cell] = result.alignment_counts[index]
		spatial.current.flock.alignment_sums[cell] = result.alignment_sums[index]

	for node in result.nodes:
		if not spatial.current.pressure.needed[node]:
			spatial.current.pressure.needed[node] = 1
			spatial.current.pressure.nodes.append(node)

class SheepJob extends SheepPerceptionJob:
	var reference: RefCounted

	func apply_result() -> void:
		if snapshot != null:
			super.apply_result()
		else:
			reference.apply_batch(self)

	func copy_input(source: Job) -> void:
		super.copy_input(source)
		reference = (source as SheepJob).reference

	func release_input() -> void:
		super.release_input()
		reference = null
	func execute() -> void:
		if snapshot != null:
			load("res://Tests/ReferenceSimulation.gd").calculate_snapshot(self)
		else:
			reference.calculate_batch(self)

class GridJob extends Job:
	var reference: RefCounted
	var flock_counts := PackedInt32Array()
	var flock_sums := PackedVector2Array()
	var alignment_counts := PackedInt32Array()
	var alignment_sums := PackedVector2Array()
	var nodes := PackedInt32Array()
	var flock_offsets := PackedInt32Array()
	var alignment_offsets := PackedInt32Array()

	func execute() -> void:
		if snapshot != null:
			var started := Time.get_ticks_usec()
			grid = load("res://Tests/ReferenceSimulation.gd").build_snapshot(snapshot)
			execute_ms = (Time.get_ticks_usec() - started) / 1000.0
			return

		var cells := rows
		var counts: PackedInt32Array = grid.cells.counts
		var position_sums: PackedVector2Array = grid.flock.position_sums
		var velocity_sums: PackedVector2Array = grid.flock.velocity_sums
		var columns: int = grid.width
		var height: int = grid.height

		flock_counts.resize(cells.size())
		flock_sums.resize(cells.size())
		alignment_counts.resize(cells.size())
		alignment_sums.resize(cells.size())

		nodes.clear()
		for index in range(cells.size()):
			var cell := cells[index]
			var x := cell % columns
			var y := cell / columns
			if counts[cell * 3 + AnimalEntity.Kind.SHEEP] >= GridSnapshot.PRESSURE_SHARED_MIN_SHEEP:
				var base := int(y) * (columns + 1) + x
				for node in [base, base + 1, base + columns + 1, base + columns + 2]:
					nodes.append(node)

			var count := 0
			var sum := Vector2.ZERO
			for offset in range(0, flock_offsets.size(), 2):
				var nx := x + flock_offsets[offset]
				var ny := y + flock_offsets[offset + 1]
				if nx >= 0 and nx < columns and ny >= 0 and ny < height:
					var neighbor := ny * columns + nx
					count += counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
					sum += position_sums[neighbor]
			flock_counts[index] = count
			flock_sums[index] = sum

			count = 0
			sum = Vector2.ZERO
			for offset in range(0, alignment_offsets.size(), 2):
				var nx := x + alignment_offsets[offset]
				var ny := y + alignment_offsets[offset + 1]
				if nx >= 0 and nx < columns and ny >= 0 and ny < height:
					var neighbor := ny * columns + nx
					count += counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
					sum += velocity_sums[neighbor]
			alignment_counts[index] = count
			alignment_sums[index] = sum

	func apply_result() -> void:
		if snapshot != null:
			assert(false, "Reference grid jobs only produce comparison output")
			return

		load("res://Tests/ReferenceSimulation.gd").apply_cells(g_gameplayEngine.grid_service, self)

	func release_input() -> void:
		super.release_input()
		flock_offsets = PackedInt32Array()
		alignment_offsets = PackedInt32Array()

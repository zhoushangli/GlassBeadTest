class_name GridAggregateJob
extends Job

func execute() -> void:
	var started := Time.get_ticks_usec()
	grid = build_snapshot(snapshot)
	execute_ms = (Time.get_ticks_usec() - started) / 1000.0

func apply_result() -> void:
	var job: SheepComputeJob = SheepComputeJob.new()
	job.stage = &"Compute"
	job.snapshot = snapshot
	job.grid = grid
	job.grid_ms = execute_ms
	if not g_gameplayEngine.compute_service.submit(job):
		for kind in snapshot.due:
			g_gameplayEngine.data_service.decisions.waiting.erase(kind)
		job.release_input()

func capture(due: PackedInt32Array) -> void:
	snapshot = capture_snapshot(due)

static func capture_snapshot(due: PackedInt32Array = PackedInt32Array([0, 1, 2])) -> AnimalSnapshot:
	# 1) Capture common inputs and species membership before submitting worker jobs.
	var engine := g_gameplayEngine
	var data: AnimalData = engine.data_service.animals
	var snapshot: AnimalSnapshot = AnimalSnapshot.new()
	snapshot.captured_usec = Time.get_ticks_usec()
	snapshot.time = engine.simulation_time
	snapshot.stats = engine.grid_service.spatial_stats_enabled
	snapshot.detailed = engine.profile_service.detailed_stats_enabled
	snapshot.config = engine.data_service.decisions.config
	snapshot.distance = snapshot.config.separation_distance
	snapshot.interval = snapshot.config.perception_interval
	snapshot.due = due
	snapshot.index.sheep_rows = engine.data_service.animals.index.sheep_rows.duplicate()
	snapshot.index.wolf_rows = engine.data_service.animals.index.wolf_rows.duplicate()
	snapshot.index.dog_rows = engine.data_service.animals.index.dog_rows.duplicate()

	snapshot.identity.animal_id = data.identity.animal_id.slice(0, data.index.active_count)
	snapshot.identity.entity_id = data.identity.entity_id.slice(0, data.index.active_count)
	snapshot.identity.kind = PackedInt32Array(Array(data.identity.kind.slice(0, data.index.active_count)))
	snapshot.motion.position = data.motion.position.slice(0, data.index.active_count)
	snapshot.motion.velocity = data.motion.velocity.slice(0, data.index.active_count)
	snapshot.motion.separation = data.motion.separation.slice(0, data.index.active_count)
	snapshot.memory.perception_ready = data.memory.perception_ready.slice(0, data.index.active_count)
	snapshot.memory.perception_remaining = data.memory.perception_remaining.slice(0, data.index.active_count)
	snapshot.wolf.hunting = data.wolf.hunting.slice(0, data.index.active_count)

	# 2) Capture sheep inputs for the required GPU pass.
	snapshot.sheep.panic_strength = data.sheep.panic_strength.slice(0, data.index.active_count)
	snapshot.sheep.panic_source = data.sheep.panic_source.slice(0, data.index.active_count)
	snapshot.sheep.panic_revision = data.sheep.panic_revision.slice(0, data.index.active_count)
	snapshot.motion.wander_point = data.motion.wander_point.slice(0, data.index.active_count)

	if due.has(1) or due.has(2):
		snapshot.motion.facing = data.motion.facing.slice(0, data.index.active_count)
		snapshot.memory.vision_radius_squared = data.memory.vision_radius_squared.slice(0, data.index.active_count)
		snapshot.memory.vision_cos = data.memory.vision_cos.slice(0, data.index.active_count)
		snapshot.memory.target_visible = data.memory.target_visible.slice(0, data.index.active_count)
		snapshot.memory.unseen_elapsed = data.memory.unseen_elapsed.slice(0, data.index.active_count)
		snapshot.memory.last_seen_position = data.memory.last_seen_position.slice(0, data.index.active_count)
		snapshot.memory.last_seen_velocity = data.memory.last_seen_velocity.slice(0, data.index.active_count)

	if due.has(1):
		snapshot.wolf.resting = data.wolf.resting.slice(0, data.index.active_count)
		snapshot.wolf.retreating = data.wolf.retreating.slice(0, data.index.active_count)

	if due.has(2):
		snapshot.dog.region = data.dog.region.slice(0, data.index.active_count)
		snapshot.dog.returning = data.dog.returning.slice(0, data.index.active_count)
		snapshot.dog.assignment_remaining = data.dog.assignment_remaining.slice(0, data.index.active_count)
		snapshot.dog.protection_center = data.dog.protection_center.slice(0, data.index.active_count)

	if due.has(1) or due.has(2):
		# 1) Convert live handles to snapshot-local rows before leaving the main thread.
		snapshot.memory.target.resize(data.index.active_count)
		snapshot.memory.target.fill(-1)
		var observers := PackedInt32Array()
		if due.has(1):
			observers.append_array(snapshot.index.wolf_rows)
		if due.has(2):
			observers.append_array(snapshot.index.dog_rows)
		for row in observers:
			var handle := data.live(data.memory.target[row])
			snapshot.memory.target[row] = handle.row if handle != null else -1

	if due.has(2):
		snapshot.dog.collected_sheep.resize(data.index.active_count)
		snapshot.dog.collected_sheep.fill(-1)
		for row in snapshot.index.dog_rows:
			var collected := data.live(data.dog.collected_sheep[row])
			snapshot.dog.collected_sheep[row] = collected.row if collected != null else -1

	snapshot.prepare_ms = (Time.get_ticks_usec() - snapshot.captured_usec) / 1000.0
	return snapshot

static func build_snapshot(snapshot: AnimalSnapshot) -> GridSnapshot:
	var size: float = snapshot.config.grid_cell_size
	var columns := ceili(snapshot.config.arena_size.x / size)
	var height := ceili(snapshot.config.arena_size.y / size)
	var cells := columns * height
	var count: int = snapshot.index.sheep_rows.size() + snapshot.index.wolf_rows.size() + snapshot.index.dog_rows.size()
	var positions: PackedVector2Array = snapshot.motion.position
	var velocities: PackedVector2Array = snapshot.motion.velocity
	var kinds := snapshot.identity.kind
	var counts := PackedInt32Array()
	var offsets := PackedInt32Array()
	var packed_members := PackedInt32Array()
	var captured_cells := PackedInt32Array()
	var position_sums := PackedVector2Array()
	var velocity_sums := PackedVector2Array()
	counts.resize(cells * 3)
	offsets.resize(cells * 3 + 1)
	packed_members.resize(count)
	captured_cells.resize(count)
	position_sums.resize(cells)
	velocity_sums.resize(cells)

	# 1) Pack spatial membership from the captured active rows.
	for row in range(count):
		var point := positions[row]
		var cell := clampi(floori(point.y / size), 0, height - 1) * columns + clampi(floori(point.x / size), 0, columns - 1)
		captured_cells[row] = cell
		counts[cell * 3 + kinds[row]] += 1
		if kinds[row] == AnimalEntity.Kind.SHEEP:
			position_sums[cell] += point
			velocity_sums[cell] += velocities[row]

	for bucket in range(cells * 3):
		offsets[bucket + 1] = offsets[bucket] + counts[bucket]
	var cursors := offsets.duplicate()
	for row in range(count):
		var bucket := captured_cells[row] * 3 + kinds[row]
		packed_members[cursors[bucket]] = row
		cursors[bucket] += 1

	# 2) Collect occupied cells for GPU aggregation and regional statistics.
	var occupied := PackedInt32Array()
	var populated := PackedInt32Array()
	var nonempty := 0
	var occupancy_max := 0
	for cell in range(cells):
		var occupancy := counts[cell * 3] + counts[cell * 3 + 1] + counts[cell * 3 + 2]
		if occupancy > 0:
			populated.append(cell)
			nonempty += 1
			occupancy_max = maxi(occupancy_max, occupancy)
		if counts[cell * 3] > 0:
			occupied.append(cell)

	var flock_count := PackedInt32Array()
	var flock_sum := PackedVector2Array()
	var aligned_count := PackedInt32Array()
	var aligned_sum := PackedVector2Array()
	flock_count.resize(cells)
	flock_sum.resize(cells)
	aligned_count.resize(cells)
	aligned_sum.resize(cells)

	# 3) Deduplicate pressure sample nodes shared by densely populated sheep cells.
	var needed := PackedByteArray()
	needed.resize((columns + 1) * (height + 1))
	var nodes := PackedInt32Array()
	var requested_nodes := PackedInt32Array()
	for cell in occupied:
		if counts[cell * 3] >= GridSnapshot.PRESSURE_SHARED_MIN_SHEEP:
			var base: int = (cell / columns) * (columns + 1) + cell % columns
			requested_nodes.append_array(PackedInt32Array([base, base + 1, base + columns + 1, base + columns + 2]))
	for node in requested_nodes:
		if not needed[node]:
			needed[node] = 1
			nodes.append(node)

	# 4) Publish snapshot columns and aggregate occupied 4-by-4-cell dog regions.
	var grid: GridSnapshot = GridSnapshot.new()
	grid.cell_size = size
	grid.width = columns
	grid.height = height
	grid.cells.positions = positions
	grid.cells.velocities = velocities
	grid.cells.kinds = kinds
	grid.cells.counts = counts
	grid.cells.offsets = offsets
	grid.cells.members = packed_members
	grid.cells.row_cells = captured_cells
	grid.flock.position_sums = position_sums
	grid.flock.velocity_sums = velocity_sums
	grid.flock.counts = flock_count
	grid.flock.sums = flock_sum
	grid.flock.alignment_counts = aligned_count
	grid.flock.alignment_sums = aligned_sum
	grid.pressure.nodes = nodes
	grid.pressure.needed = needed
	grid.pressure.sample_count = nodes.size()
	grid.nonempty_cells = nonempty
	grid.max_occupancy = occupancy_max
	grid.cells.populated = populated
	grid.cells.occupied = occupied
	grid.captured_usec = snapshot.captured_usec
	grid.time = snapshot.time
	grid.animal_ids = snapshot.identity.animal_id
	grid.regions.width = ceili(columns / 4.0)
	grid.regions.height = ceili(height / 4.0)

	var regions := grid.regions.width * grid.regions.height
	grid.regions.counts.resize(regions)
	grid.regions.centers.resize(regions)
	grid.regions.velocities.resize(regions)
	for cell in occupied:
		var region := floori(float(cell % columns) / 4.0) + floori(float(cell / columns) / 4.0) * grid.regions.width
		grid.regions.counts[region] += counts[cell * 3]
		grid.regions.centers[region] += position_sums[cell]
		grid.regions.velocities[region] += velocity_sums[cell]

	for region in range(regions):
		if grid.regions.counts[region] == 0:
			continue

		grid.regions.occupied.append(region)
		grid.regions.centers[region] /= grid.regions.counts[region]
		grid.regions.velocities[region] /= grid.regions.counts[region]

	return grid

static func publish_grid(grid: GridSnapshot) -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	spatial.current = grid
	spatial.version += 1
	spatial.pressure.wolf.resize((grid.width + 1) * (grid.height + 1))
	spatial.pressure.wolf.fill(Vector2.ZERO)
	spatial.pressure.dog.resize((grid.width + 1) * (grid.height + 1))
	spatial.pressure.dog.fill(Vector2.ZERO)
	spatial.pressure.source_pairs = 0

	g_gameplayEngine.grid_service.reset_spatial_stats()
	if g_gameplayEngine.grid_service.spatial_stats_enabled:
		g_gameplayEngine.grid_service.spatial_nonempty_cells = grid.nonempty_cells
		g_gameplayEngine.grid_service.spatial_max_occupancy = grid.max_occupancy

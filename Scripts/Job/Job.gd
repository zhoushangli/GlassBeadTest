class_name Job
extends RefCounted

enum State { IDLE, PENDING, WORKING, COMPLETED, APPLIED, DISCARDED }

var stage: StringName
var batch: int = 0
# Map each output index to its input row; asynchronous rows belong to the snapshot.
# e.g. rows = PackedInt32Array([7, 2]) maps output index 1 to snapshot row 2.
var rows := PackedInt32Array()
var snapshot: AnimalSnapshot
var grid: GridSnapshot
var config: SimulationConfig
var data: AnimalData = g_gameplayEngine.data_service.animals
var batch_input: AnimalData
var delta: float = 0.0
var distance: float = 0.0
var interval: float = 0.0
var spatial_stats: bool = false
var detailed: bool = false
var version: int = -1
var sequence: int = 0
var submitted_usec: int = 0
var execution_started_usec: int = 0
var execution_finished_usec: int = 0
var grid_ms: float = 0.0
var stats: Dictionary = {}
var execute_ms: float = 0.0
var task_id: int = -1
var state: State = State.IDLE

func execute() -> void:
	assert(false, "Job.execute must be implemented")

func run_profiled() -> void:
	execution_started_usec = Time.get_ticks_usec()
	execute()
	execution_finished_usec = Time.get_ticks_usec()

func apply_result() -> void:
	assert(false, "Job.apply_result must be implemented")

func release_input() -> void:
	rows = PackedInt32Array()
	snapshot = null
	grid = null
	config = null
	batch_input = null

func copy_input(source: Job) -> void:
	snapshot = source.snapshot
	grid = source.grid
	config = source.config
	data = source.data
	batch_input = source.batch_input
	delta = source.delta
	distance = source.distance
	interval = source.interval
	spatial_stats = source.spatial_stats
	detailed = source.detailed

func can_start() -> bool:
	return true

func cancel() -> void:
	pass

func is_cancelled() -> bool:
	return false

func capture_batch(interval_delta: float) -> void:
	delta = interval_delta
	grid = g_gameplayEngine.data_service.spatial.current
	config = g_gameplayEngine.config.copy_config()
	distance = config.separation_distance
	interval = config.perception_interval
	spatial_stats = g_gameplayEngine.grid_service.spatial_stats_enabled
	detailed = g_gameplayEngine.profile_service.detailed_stats_enabled
	_capture_batch_storage()

static func snapshot_can_see(row: int, point: Vector2, snapshot: AnimalSnapshot) -> bool:
	var offset: Vector2 = point - snapshot.motion.position[row]
	return offset.length_squared() <= snapshot.memory.vision_radius_squared[row] and (offset.is_zero_approx() or snapshot.motion.facing[row].dot(offset.normalized()) + 0.000001 >= snapshot.memory.vision_cos[row])

static func snapshot_separation(row: int, snapshot: AnimalSnapshot, grid: GridSnapshot, stats: Dictionary, refresh: bool) -> Vector2:
	var separation: Vector2 = snapshot.motion.separation[row]
	if refresh:
		separation = Vector2.ZERO
		var distance: float = snapshot.distance
		var nearby := GridSnapshot.query_snapshot(snapshot.motion.position[row], distance, grid.cells.kinds[row], grid, stats)
		for other in nearby:
			if other == row:
				continue

			var offset: Vector2 = snapshot.motion.position[row] - snapshot.motion.position[other]
			var length := offset.length()
			if distance <= 0.0 or length >= distance:
				continue

			var direction := offset.normalized() if length >= 0.001 else (Vector2.RIGHT if snapshot.identity.entity_id[row] < snapshot.identity.entity_id[other] else Vector2.LEFT)
			separation += direction * (1.0 - length / distance)
	return separation

# Resolve snapshot identity against current storage instead of trusting an old row.
# e.g. a captured animal resolves to null even if its former row now holds a survivor.

func snapshot_animal(snapshot: AnimalSnapshot, index: int) -> AnimalEntity:
	if index < 0 or index >= snapshot.identity.animal_id.size():
		return null

	var row := data.row_of_id(snapshot.identity.animal_id[index])
	return data.index.handles[row] if row >= 0 and row < data.index.active_count and data.identity.alive[row] else null

func apply_snapshot_perception(row: int, snapshot_row: int, snapshot: AnimalSnapshot, separation: Vector2, refresh: bool, target: int, visible: bool, last_position: Vector2, last_velocity: Vector2) -> void:
	# 1) Subtract snapshot age so completed work does not restart an old sampling interval.
	if refresh:
		data.motion.separation[row] = separation
		data.memory.perception_ready[row] = 1
		var interval: float = snapshot.interval
		if not snapshot.memory.perception_ready[snapshot_row]:
			interval *= fmod(snapshot.identity.entity_id[snapshot_row] * 0.618034, 1.0)
		data.memory.perception_remaining[row] = maxf(0.0, interval - (g_gameplayEngine.simulation_time - snapshot.time))

	if data.live(data.memory.target[row]) != snapshot_animal(snapshot, target):
		return

	data.memory.target_visible[row] = int(visible)
	if visible:
		data.memory.last_seen_position[row] = last_position
		data.memory.last_seen_velocity[row] = last_velocity
		data.memory.unseen_elapsed[row] = g_gameplayEngine.simulation_time - snapshot.time

static func batch_stats(enabled: bool, detailed: bool) -> Dictionary:
	return {"enabled": enabled, "detailed": detailed, "queries": 0, "candidates": 0, "max_candidates": 0,
		"hotspots": {"NearbyQuery": 0.0, "Separation": 0.0, "NeighborScan": 0.0, "WolfTarget": 0.0, "DogAnchor": 0.0},
		"calls": {"NearbyQuery": 0, "Separation": 0, "NeighborScan": 0, "WolfTarget": 0, "DogAnchor": 0}}

func calculate_perception(row: int, job: Job, stats: Dictionary, index: int, remaining_values: PackedFloat64Array, refresh_flags: PackedByteArray, separations: PackedVector2Array, nearby_offsets: PackedInt32Array, nearby_members: PackedInt32Array) -> void:
	var data := batch_input
	var remaining: float = data.memory.perception_remaining[row] - job.delta
	var refresh := not data.memory.perception_ready[row] or remaining <= 0.0
	var nearby := data.memory.nearby[row]
	var separation := data.motion.separation[row]
	if refresh:
		nearby = GridSnapshot.query_snapshot(data.motion.position[row], job.distance, data.identity.kind[row], job.grid, stats)
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		separation = Vector2.ZERO
		var distance_limit: float = job.distance
		var positions: PackedVector2Array = job.grid.cells.positions
		var kinds: PackedInt32Array = job.grid.cells.kinds
		if distance_limit > 0.0:
			for other in nearby:
				if other == row or kinds[other] != data.identity.kind[row]:
					continue

				var offset := data.motion.position[row] - positions[other]
				var squared := offset.length_squared()
				if squared >= distance_limit * distance_limit:
					continue

				var distance := sqrt(squared)
				var direction := offset.normalized()
				if distance < 0.001:
					direction = Vector2.RIGHT if data.identity.entity_id[row] < data.identity.entity_id[other] else Vector2.LEFT
				separation += direction * (1.0 - distance / distance_limit)
		if stats.detailed:
			stats.hotspots.Separation += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.Separation += 1
		remaining = job.interval
		if not data.memory.perception_ready[row]:
			remaining *= fmod(data.identity.entity_id[row] * 0.618034, 1.0)

	remaining_values[index] = remaining
	refresh_flags[index] = int(refresh)
	separations[index] = separation
	nearby_members.append_array(nearby)
	nearby_offsets[index + 1] = nearby_members.size()

func calculate_observation(row: int, delta: float, job: WolfPerceptionJob, index: int) -> void:
	var data := batch_input
	var target := data.live(data.memory.target[row])
	job.visible_flags[index] = 0
	job.unseen_elapsed[index] = 0.0
	job.last_positions[index] = Vector2.ZERO
	job.last_velocities[index] = Vector2.ZERO
	if target == null:
		return

	var visible := can_see(data.index.handles[row], data.motion.position[target.row])
	job.visible_flags[index] = int(visible)
	job.unseen_elapsed[index] = 0.0 if visible else data.memory.unseen_elapsed[row] + delta
	job.last_positions[index] = data.motion.position[target.row]
	job.last_velocities[index] = data.motion.velocity[target.row]

func submit_perception(row: int, remaining: float, refresh: bool, nearby: PackedInt32Array, separation: Vector2, delta: float, advance_wander: bool = true) -> void:
	if advance_wander:
		data.motion.wander_remaining[row] -= delta
	data.memory.perception_remaining[row] = remaining
	data.memory.perception_ready[row] = 1
	if refresh:
		data.memory.nearby[row] = nearby
		data.motion.separation[row] = separation

func submit_observation(row: int, visible: bool, elapsed: float, position: Vector2, velocity: Vector2) -> void:
	data.memory.target_visible[row] = int(visible)
	data.memory.unseen_elapsed[row] = elapsed
	if visible:
		data.memory.last_seen_position[row] = position
		data.memory.last_seen_velocity[row] = velocity

func can_see(animal: AnimalEntity, point: Vector2) -> bool:
	var data := batch_input if batch_input != null else self.data
	var row := animal.row
	var offset := point - data.motion.position[row]
	if offset.length_squared() > data.memory.vision_radius_squared[row]:
		return false

	return offset.is_zero_approx() or data.motion.facing[row].dot(offset.normalized()) + 0.000001 >= data.memory.vision_cos[row]

func submit_stats(stats: Dictionary) -> void:
	var grid: GridService = g_gameplayEngine.grid_service
	grid.spatial_query_count += stats.queries
	grid.spatial_candidate_count += stats.candidates
	grid.spatial_max_candidates = maxi(grid.spatial_max_candidates, stats.max_candidates)
	if stats.detailed:
		var profile: ProfileService = g_gameplayEngine.profile_service
		for name in stats.hotspots:
			profile.last_hotspots_ms[name] += stats.hotspots[name]
			profile.last_hotspot_calls[name] += stats.calls[name]

func record_application(kind: int, started_at: int) -> float:
	var apply_ms := (Time.get_ticks_usec() - started_at) / 1000.0
	var profile: ProfileService = g_gameplayEngine.profile_service
	var stage_name: StringName = [&"Sheep", &"Wolf", &"Dog"][kind]
	profile.record_duration("Species/" + String(stage_name) + "/Apply", apply_ms)
	g_gameplayEngine.data_service.decisions.applied[kind] += 1
	return apply_ms

func _capture_batch_storage() -> void:
	# 1) Copy only columns used by synchronous worker calculations.
	var captured := AnimalData.new()
	var count := data.index.active_count
	captured.index.active_count = count
	captured.index.slot_to_row = data.index.slot_to_row.duplicate()
	captured.index.row_to_slot = data.index.row_to_slot.slice(0, count)
	captured.identity.animal_id = data.identity.animal_id.slice(0, count)
	captured.identity.entity_id = data.identity.entity_id.slice(0, count)
	captured.identity.kind = data.identity.kind.slice(0, count)
	captured.identity.alive = data.identity.alive.slice(0, count)
	captured.motion.position = data.motion.position.slice(0, count)
	captured.motion.velocity = data.motion.velocity.slice(0, count)
	captured.motion.facing = data.motion.facing.slice(0, count)
	captured.motion.separation = data.motion.separation.slice(0, count)
	captured.memory.perception_remaining = data.memory.perception_remaining.slice(0, count)
	captured.memory.perception_ready = data.memory.perception_ready.slice(0, count)
	captured.memory.nearby = data.memory.nearby.slice(0, count).duplicate(true)
	captured.memory.target_visible = data.memory.target_visible.slice(0, count)
	captured.memory.unseen_elapsed = data.memory.unseen_elapsed.slice(0, count)
	captured.memory.vision_radius_squared = data.memory.vision_radius_squared.slice(0, count)
	captured.memory.vision_cos = data.memory.vision_cos.slice(0, count)
	captured.wolf.retreating = data.wolf.retreating.slice(0, count)
	captured.wolf.resting = data.wolf.resting.slice(0, count)
	captured.wolf.rest_elapsed = data.wolf.rest_elapsed.slice(0, count)
	captured.wolf.hunting = data.wolf.hunting.slice(0, count)
	captured.dog.protection_center = data.dog.protection_center.slice(0, count)

	# 2) Resolve targets into isolated handles so workers cannot observe live row changes.
	captured.index.handles.resize(count)
	for row in range(count):
		var handle := AnimalEntity.new()
		handle.id = captured.identity.animal_id[row]
		handle.row = row
		captured.index.handles[row] = handle
	captured.memory.target.resize(count)
	captured.dog.protected_sheep.resize(count)
	captured.dog.collected_sheep.resize(count)
	for row in range(count):
		var target := data.live(data.memory.target[row])
		var anchor := data.live(data.dog.protected_sheep[row])
		var collected := data.live(data.dog.collected_sheep[row])
		captured.memory.target[row] = captured.index.handles[target.row] if target != null else null
		captured.dog.protected_sheep[row] = captured.index.handles[anchor.row] if anchor != null else null
		captured.dog.collected_sheep[row] = captured.index.handles[collected.row] if collected != null else null
	batch_input = captured

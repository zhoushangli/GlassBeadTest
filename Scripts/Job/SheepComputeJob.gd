class_name SheepComputeJob
extends SheepPerceptionJob

var resources: ComputeShaderService.Resources
var metrics: ProfileService.Metrics = ProfileService.Metrics.new()
var input_bytes := PackedByteArray()
var index_bytes := PackedByteArray()
var error: String = ""

var _mutex: Mutex = Mutex.new()
var _cancelled: bool = false

func execute() -> void:
	var started := Time.get_ticks_usec()
	if is_cancelled() or not error.is_empty():
		return

	# 1) Pack the immutable input on the device thread.
	var pack_started := Time.get_ticks_usec()
	_pack()
	metrics.pack_ms = (Time.get_ticks_usec() - pack_started) / 1000.0
	if is_cancelled():
		return

	# 2) Submit, synchronize and retrieve data on the same device thread.
	var bytes := _execute_gpu()
	input_bytes = PackedByteArray()
	index_bytes = PackedByteArray()
	if not is_cancelled() and error.is_empty():
		_decode(bytes)
	execute_ms = (Time.get_ticks_usec() - started) / 1000.0

func apply_result() -> void:
	var engine := g_gameplayEngine
	if not error.is_empty():
		for kind in snapshot.due:
			engine.data_service.decisions.waiting.erase(kind)
		engine.fail_step("GPU sheep calculation failed: " + error)
		return

	GridAggregateJob.publish_grid(grid)
	for kind in snapshot.due:
		if kind == AnimalEntity.Kind.SHEEP:
			super.apply_result()
		else:
			var job: Job = WolfPerceptionJob.new() if kind == AnimalEntity.Kind.WOLF else DogPerceptionJob.new()
			job.stage = &"Wolf" if kind == AnimalEntity.Kind.WOLF else &"Dog"
			job.rows = snapshot.rows_for(kind)
			job.snapshot = snapshot
			job.grid = grid
			job.grid_ms = grid_ms
			engine.job_service.submit_async(job)
		engine.data_service.decisions.waiting.erase(kind)

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func release_input() -> void:
	super.release_input()
	resources = null
	input_bytes = PackedByteArray()
	index_bytes = PackedByteArray()

func _pack() -> void:
	# 1) Serialize numeric columns in the order consumed by SheepCompute.glsl.
	var settings: SheepConfig = snapshot.config.sheep
	var values := PackedFloat32Array([grid.cell_size, snapshot.distance, settings.flock_radius, settings.alignment_radius,
		settings.wolf_pressure_distance, settings.herding_distance, settings.hunting_pressure_multiplier, settings.move_speed,
		settings.flee_speed, settings.idle_speed_scale, settings.wander_weight, settings.separation_weight,
		settings.alignment_weight, settings.cohesion_weight, settings.wolf_pressure_weight, settings.dog_pressure_weight])
	values.resize(32)
	var positions: PackedVector2Array = grid.cells.positions
	var ids: PackedInt64Array = snapshot.identity.entity_id
	var fallback := PackedVector2Array()
	fallback.resize(positions.size())
	for row in range(positions.size()):
		fallback[row] = Vector2.from_angle(ids[row] * 2.399963)

	var bytes := values.to_byte_array()
	var vector_columns: Array[PackedVector2Array] = [positions, grid.cells.velocities, snapshot.motion.separation]
	for column in vector_columns:
		bytes.append_array(column.to_byte_array())
	bytes.append_array(_float32(snapshot.sheep.panic_strength).to_byte_array())
	bytes.append_array(_float32(snapshot.memory.perception_remaining).to_byte_array())
	for column: PackedVector2Array in [snapshot.sheep.panic_source, snapshot.motion.wander_point, fallback]:
		bytes.append_array(column.to_byte_array())
	bytes.append_array(grid.flock.position_sums.to_byte_array())
	bytes.append_array(grid.flock.velocity_sums.to_byte_array())

	var flock_offsets := GridSnapshot.snapshot_offsets(settings.flock_radius, grid.cell_size)
	var alignment_offsets := GridSnapshot.snapshot_offsets(settings.alignment_radius, grid.cell_size)
	var occupied: PackedInt32Array = grid.cells.occupied
	var nodes: PackedInt32Array = grid.pressure.nodes

	# 2) Map sparse cells and nodes to compact GPU output indices.
	var cell_map := PackedInt32Array()
	cell_map.resize(grid.flock.position_sums.size())
	cell_map.fill(-1)
	for index in range(occupied.size()):
		cell_map[occupied[index]] = index

	var node_map := PackedInt32Array()
	node_map.resize((grid.width + 1) * (grid.height + 1))
	node_map.fill(-1)
	for index in range(nodes.size()):
		node_map[nodes[index]] = index

	# 3) Store integer column offsets in the shader header before appending their contents.
	var indices := PackedInt32Array([grid.width, grid.height, positions.size(), snapshot.index.sheep_rows.size(), snapshot.index.wolf_rows.size(),
		snapshot.index.dog_rows.size(), occupied.size(), nodes.size()])
	indices.resize(26)
	var columns: Array[PackedInt32Array] = [grid.cells.offsets, grid.cells.members, grid.cells.row_cells, snapshot.index.sheep_rows, snapshot.index.wolf_rows,
		snapshot.index.dog_rows, grid.cells.counts, flock_offsets, alignment_offsets, occupied, cell_map, nodes, node_map, _int32(ids), _int32(snapshot.memory.perception_ready), _int32(snapshot.wolf.hunting)]
	var header_fields := [8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 20, 21, 22, 23, 24, 25]
	for index in range(columns.size()):
		indices[header_fields[index]] = indices.size()
		indices.append_array(columns[index])

	indices[17] = flock_offsets.size() / 2
	indices[18] = alignment_offsets.size() / 2
	input_bytes = bytes
	index_bytes = indices.to_byte_array()
	metrics.upload_bytes = input_bytes.size() + index_bytes.size()
	metrics.download_bytes = maxi(4, (occupied.size() * 8 + nodes.size() * 6 + snapshot.index.sheep_rows.size() * 16) * 4)

func _decode(bytes: PackedByteArray) -> void:
	# 1) Restore per-cell flock aggregates from the compact occupied-cell output.
	var started := Time.get_ticks_usec()
	var values := bytes.to_float32_array()
	var occupied: PackedInt32Array = grid.cells.occupied
	var flock_counts: PackedInt32Array = grid.flock.counts
	var flock_sums: PackedVector2Array = grid.flock.sums
	var alignment_counts: PackedInt32Array = grid.flock.alignment_counts
	var alignment_sums: PackedVector2Array = grid.flock.alignment_sums
	for index in range(occupied.size()):
		var cell := occupied[index]
		var p: int = index * 8
		flock_counts[cell] = int(values[p])
		flock_sums[cell] = Vector2(values[p + 1], values[p + 2])
		alignment_counts[cell] = int(values[p + 4])
		alignment_sums[cell] = Vector2(values[p + 5], values[p + 6])

	# 2) Expand sampled pressure nodes into fields shared by species jobs and debug drawing.
	var wolf_field := PackedVector2Array()
	var dog_field := PackedVector2Array()
	wolf_field.resize((grid.width + 1) * (grid.height + 1))
	dog_field.resize(wolf_field.size())
	var pairs := 0
	for index in range(grid.pressure.nodes.size()):
		var node: int = grid.pressure.nodes[index]
		var p: int = occupied.size() * 8 + index * 6
		wolf_field[node] = Vector2(values[p], values[p + 1])
		dog_field[node] = Vector2(values[p + 2], values[p + 3])
		pairs += int(values[p + 4] + values[p + 5])

	# 3) Decode sheep outputs using the same result layout as the CPU perception path.
	rows = snapshot.index.sheep_rows if snapshot.due.has(0) else PackedInt32Array()
	resize_output()
	stats = Job.batch_stats(snapshot.stats, snapshot.detailed)
	wolf_pressure = wolf_field
	dog_pressure = dog_field
	pressure_source_pairs = pairs
	for index in range(rows.size()):
		var p: int = occupied.size() * 8 + grid.pressure.nodes.size() * 6 + index * 16
		separations[index] = Vector2(values[p], values[p + 1])
		centers[index] = Vector2(values[p + 2], values[p + 3])
		alignments[index] = Vector2(values[p + 4], values[p + 5])
		threat_directions[index] = Vector2(values[p + 6], values[p + 7])
		threat_strengths[index] = values[p + 8]
		dog_pressures[index] = Vector2(values[p + 9], values[p + 10])
		desired_velocities[index] = Vector2(values[p + 11], values[p + 12])
		speed_limits[index] = values[p + 13]
		neighbor_counts[index] = int(values[p + 14])
		refresh_flags[index] = int(values[p + 15] > 0.0)

	metrics.decode_ms = (Time.get_ticks_usec() - started) / 1000.0

func _int32(column: Variant) -> PackedInt32Array:
	var values := PackedInt32Array()
	values.resize(column.size())
	for index in range(values.size()):
		values[index] = column[index]
	return values

func _float32(column: PackedFloat64Array) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(column.size())
	for index in range(values.size()):
		values[index] = column[index]
	return values

func record_application(kind: int, started_at: int) -> float:
	var apply_ms := super.record_application(kind, started_at)
	var profile: ProfileService = g_gameplayEngine.profile_service
	metrics.backend = "gpu"
	metrics.apply_ms = apply_ms
	metrics.grid_ms = grid_ms
	metrics.prepare_ms = snapshot.prepare_ms
	metrics.execute_ms = execute_ms
	metrics.latency_ms = (Time.get_ticks_usec() - snapshot.captured_usec) / 1000.0
	var cpu_ms := metrics.pack_ms + metrics.decode_ms
	metrics.processing_ms = metrics.prepare_ms + metrics.grid_ms + cpu_ms + metrics.apply_ms + metrics.upload_submit_ms + maxf(0.0, metrics.gpu_ms) + maxf(0.0, metrics.buffer_read_ms)
	for metric in ["pack_ms", "device_queue_ms", "upload_submit_ms", "gpu_wait_ms", "buffer_read_ms", "decode_ms"]:
		profile.record_duration("Compute/" + metric, metrics.get(metric))
	profile.record_duration("Compute/GPU", metrics.gpu_ms)
	profile.preprocessing_samples.append(metrics)
	if profile.preprocessing_samples.size() > 4096:
		profile.preprocessing_samples = profile.preprocessing_samples.slice(2048)
	return apply_ms

func _execute_gpu() -> PackedByteArray:
	assert(OS.get_thread_caller_id() == resources.owner_thread_id)
	if is_cancelled():
		return PackedByteArray()
	var started_at := Time.get_ticks_usec()
	var sizes := PackedInt32Array([input_bytes.size(), index_bytes.size(), metrics.download_bytes])
	var resized := false
	for index in range(3):
		if sizes[index] > resources.capacities[index]:
			if resources.uniform.is_valid():
				resources.device.free_rid(resources.uniform)
				resources.uniform = RID()
			if resources.buffers[index].is_valid():
				resources.device.free_rid(resources.buffers[index])
			resources.capacities[index] = maxi(sizes[index], resources.capacities[index] * 2)
			resources.buffers[index] = resources.device.storage_buffer_create(resources.capacities[index])
			if not resources.buffers[index].is_valid():
				error = "Compute buffer creation failed"
				return PackedByteArray()

			resized = true
	if resized or not resources.uniform.is_valid():
		var uniforms: Array[RDUniform] = []
		for index in range(3):
			var uniform: RDUniform = RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = index
			uniform.add_id(resources.buffers[index])
			uniforms.append(uniform)
		resources.uniform = resources.device.uniform_set_create(uniforms, resources.shader, 0)
		if not resources.uniform.is_valid():
			error = "Compute uniform creation failed"
			return PackedByteArray()

	for index in range(2):
		var bytes := input_bytes if index == 0 else index_bytes
		var upload_error := resources.device.buffer_update(resources.buffers[index], 0, sizes[index], bytes)
		if upload_error != OK:
			error = "Compute upload failed: %s" % upload_error
			return PackedByteArray()

	var sequence := metrics.gpu_sequence
	resources.device.capture_timestamp("Compute:%d:begin" % sequence)
	var list := resources.device.compute_list_begin()
	resources.device.compute_list_bind_compute_pipeline(list, resources.pipeline)
	resources.device.compute_list_bind_uniform_set(list, resources.uniform, 0)
	var counts := PackedInt32Array([grid.cells.occupied.size(), grid.pressure.nodes.size(), snapshot.index.sheep_rows.size() if snapshot.due.has(0) else 0])
	for stage in range(3):
		if counts[stage] == 0:
			continue

		var push := PackedInt32Array([stage]).to_byte_array()
		resources.device.compute_list_set_push_constant(list, push, push.size())
		resources.device.compute_list_dispatch(list, ceili(counts[stage] / 64.0), 1, 1)
		resources.device.compute_list_add_barrier(list)
	resources.device.compute_list_end()
	resources.device.capture_timestamp("Compute:%d:end" % sequence)
	resources.device.submit()
	metrics.upload_submit_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	started_at = Time.get_ticks_usec()
	resources.device.sync()
	metrics.gpu_wait_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	var begin_time: int = -1
	for index in range(resources.device.get_captured_timestamps_count()):
		var name := resources.device.get_captured_timestamp_name(index)
		if name == "Compute:%d:begin" % sequence:
			begin_time = resources.device.get_captured_timestamp_gpu_time(index)
		elif name == "Compute:%d:end" % sequence and begin_time >= 0:
			metrics.gpu_ms = (resources.device.get_captured_timestamp_gpu_time(index) - begin_time) / 1000000.0
	if is_cancelled():
		return PackedByteArray()

	started_at = Time.get_ticks_usec()
	var output := resources.device.buffer_get_data(resources.buffers[2], 0, sizes[2])
	metrics.buffer_read_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	if output.size() != sizes[2]:
		error = "Compute readback size mismatch"
	return output

class_name SheepCompute
extends RefCounted

const SHADER_PATH := "res://Shaders/Simulation/SheepCompute.glsl"

var busy: bool = false
var failure: String = ""
var completed: Dictionary = {}
var _sequence: int = 0
var _closed: bool = false
var _workers: Array[int] = []
var _render_closed: bool = false

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _uniform_set := RID()
var _buffers: Array[RID] = [RID(), RID(), RID()]
var _capacities := PackedInt32Array([0, 0, 0])
var gpu_timings: Dictionary = {}
var _timestamp_frame: int = -1

func available() -> bool:
	return not _closed and failure.is_empty() and DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]

func submit(grid: Dictionary, snapshot: Dictionary) -> void:
	assert(not busy and available())
	busy = true
	_sequence += 1
	if not RenderingServer.frame_post_draw.is_connected(_timestamp_tick):
		RenderingServer.frame_post_draw.connect(_timestamp_tick)
	_workers.append(WorkerThreadPool.add_task(_prepare.bind(grid, snapshot, _sequence), false, "ComputePack"))
	_reap_workers.call_deferred()

func _prepare(grid: Dictionary, snapshot: Dictionary, sequence: int) -> void:
	var started := Time.get_ticks_usec()
	var packed := _pack(grid, snapshot)
	var metrics := {"pack_ms": (Time.get_ticks_usec() - started) / 1000.0, "upload_submit_ms": 0.0, "gpu_ms": -1.0,
		"decode_ms": 0.0, "readback_ms": 0.0, "upload_bytes": packed[0].size() + packed[1].size(), "download_bytes": packed[2]}
	RenderingServer.call_on_render_thread(_render_submit.bind(packed, grid, snapshot, metrics, sequence))

func _reap_workers() -> void:
	for index in range(_workers.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_workers[index]):
			WorkerThreadPool.wait_for_task_completion(_workers[index])
			_workers.remove_at(index)
	if not _workers.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if not tree.process_frame.is_connected(_reap_workers):
			tree.process_frame.connect(_reap_workers, CONNECT_ONE_SHOT)

func take_result() -> Dictionary:
	var output := completed
	completed = {}
	return output

func close() -> void:
	_closed = true
	completed = {}
	if RenderingServer.frame_post_draw.is_connected(_timestamp_tick):
		RenderingServer.frame_post_draw.disconnect(_timestamp_tick)
	RenderingServer.call_on_render_thread(_release)

func _pack(grid: Dictionary, snapshot: Dictionary) -> Array:
	var settings: Dictionary = snapshot.species_settings[0]
	var values := PackedFloat32Array([grid.cell_size, snapshot.distance, settings.flock_radius, settings.alignment_radius,
		settings.wolf_pressure_distance, settings.herding_distance, settings.hunting_pressure_multiplier, settings.move_speed,
		settings.flee_speed, settings.idle_speed_scale, settings.wander_weight, settings.separation_weight,
		settings.alignment_weight, settings.cohesion_weight, settings.wolf_pressure_weight, settings.dog_pressure_weight])
	values.resize(32)
	var positions: PackedVector2Array = grid.positions
	var ids: PackedInt64Array = snapshot.identity_entity_id
	var fallback := PackedVector2Array()
	fallback.resize(positions.size())
	for row in range(positions.size()):
		fallback[row] = Vector2.from_angle(ids[row] * 2.399963)
	var bytes := values.to_byte_array()
	var vector_columns: Array[PackedVector2Array] = [positions, grid.velocities, snapshot.motion_separation]
	for column in vector_columns:
		bytes.append_array(column.slice(0, positions.size()).to_byte_array())
	bytes.append_array(PackedFloat32Array(Array(snapshot.sheep_panic_strength.slice(0, positions.size()))).to_byte_array())
	bytes.append_array(PackedFloat32Array(Array(snapshot.memory_perception_remaining.slice(0, positions.size()))).to_byte_array())
	for column: PackedVector2Array in [snapshot.sheep_panic_source, snapshot.motion_wander_point, fallback]:
		bytes.append_array(column.slice(0, positions.size()).to_byte_array())
	bytes.append_array(grid.position_sums.to_byte_array())
	bytes.append_array(grid.velocity_sums.to_byte_array())

	var flock_offsets := GridService.snapshot_offsets(settings.flock_radius, grid.cell_size)
	var alignment_offsets := GridService.snapshot_offsets(settings.alignment_radius, grid.cell_size)
	var occupied: PackedInt32Array = grid.occupied
	var nodes: PackedInt32Array = grid.pressure_nodes
	var cell_map := PackedInt32Array()
	cell_map.resize(grid.position_sums.size())
	cell_map.fill(-1)
	for index in range(occupied.size()):
		cell_map[occupied[index]] = index
	var node_map := PackedInt32Array()
	node_map.resize((grid.width + 1) * (grid.height + 1))
	node_map.fill(-1)
	for index in range(nodes.size()):
		node_map[nodes[index]] = index
	var indices := PackedInt32Array([grid.width, grid.height, positions.size(), snapshot.sheep.size(), snapshot.wolves.size(),
		snapshot.dogs.size(), occupied.size(), nodes.size()])
	indices.resize(26)
	var columns: Array[PackedInt32Array] = [grid.offsets, grid.members, grid.row_cells, snapshot.sheep, snapshot.wolves,
		snapshot.dogs, grid.counts, flock_offsets, alignment_offsets, occupied, cell_map, nodes, node_map, PackedInt32Array(Array(ids)), PackedInt32Array(Array(snapshot.memory_perception_ready)), PackedInt32Array(Array(snapshot.wolf_hunting))]
	var header_fields := [8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 20, 21, 22, 23, 24, 25]
	for index in range(columns.size()):
		indices[header_fields[index]] = indices.size()
		indices.append_array(columns[index])
	indices[17] = flock_offsets.size() / 2
	indices[18] = alignment_offsets.size() / 2
	return [bytes, indices.to_byte_array(), maxi(4, (occupied.size() * 8 + nodes.size() * 6 + snapshot.sheep.size() * 16) * 4)]

func _render_submit(packed: Array, grid: Dictionary, snapshot: Dictionary, metrics: Dictionary, sequence: int) -> void:
	if _render_closed:
		return
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_receive_error.call_deferred("RenderingDevice unavailable")
		return
	if not _shader.is_valid():
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(SHADER_PATH).replace("#[compute]", "")
		var spirv := _rd.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_compute.is_empty():
			_receive_error.call_deferred(spirv.compile_error_compute)
			return
		_shader = _rd.shader_create_from_spirv(spirv)
		_pipeline = _rd.compute_pipeline_create(_shader)
		if not _pipeline.is_valid():
			_receive_error.call_deferred("Compute pipeline creation failed")
			return

	var started := Time.get_ticks_usec()
	var sizes := [packed[0].size(), packed[1].size(), packed[2]]
	var resized := false
	for index in range(3):
		if sizes[index] > _capacities[index]:
			if _uniform_set.is_valid():
				_rd.free_rid(_uniform_set)
				_uniform_set = RID()
			if _buffers[index].is_valid():
				_rd.free_rid(_buffers[index])
			_capacities[index] = maxi(sizes[index], _capacities[index] * 2)
			_buffers[index] = _rd.storage_buffer_create(_capacities[index])
			resized = true
	if resized or not _uniform_set.is_valid():
		var uniforms: Array[RDUniform] = []
		for index in range(3):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = index
			uniform.add_id(_buffers[index])
			uniforms.append(uniform)
		_uniform_set = _rd.uniform_set_create(uniforms, _shader, 0)
	for index in range(2):
		var error := _rd.buffer_update(_buffers[index], 0, sizes[index], packed[index])
		if error != OK:
			_receive_error.call_deferred("Compute buffer upload failed: %s" % error)
			return

	_rd.capture_timestamp("SheepCompute:%d:begin" % sequence)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
	var counts := [grid.occupied.size(), grid.pressure_nodes.size(), snapshot.sheep.size() if snapshot.due.has(0) else 0]
	for stage in range(3):
		if counts[stage] == 0:
			continue
		var push := PackedInt32Array([stage]).to_byte_array()
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(counts[stage] / 64.0), 1, 1)
		_rd.compute_list_add_barrier(list)
	_rd.compute_list_end()
	_rd.capture_timestamp("SheepCompute:%d:end" % sequence)
	metrics.upload_submit_ms = (Time.get_ticks_usec() - started) / 1000.0
	metrics.readback_started = Time.get_ticks_usec()
	var error := _rd.buffer_get_data_async(_buffers[2], _readback.bind(grid, snapshot, metrics, sequence), 0, sizes[2])
	if error != OK:
		_receive_error.call_deferred("Compute readback failed: %s" % error)

func _timestamp_tick() -> void:
	RenderingServer.call_on_render_thread(_collect_timestamps)

func _collect_timestamps() -> void:
	if _rd == null:
		return
	var frame := _rd.get_captured_timestamps_frame()
	if frame == _timestamp_frame:
		return
	_timestamp_frame = frame
	var begins: Dictionary = {}
	for index in range(_rd.get_captured_timestamps_count()):
		var name := _rd.get_captured_timestamp_name(index)
		if not name.begins_with("SheepCompute:"):
			continue
		var parts := name.split(":")
		var sequence := int(parts[1])
		var timestamp := _rd.get_captured_timestamp_gpu_time(index)
		if parts[2] == "begin":
			begins[sequence] = timestamp
		elif begins.has(sequence):
			var elapsed: float = (timestamp - begins[sequence]) / 1000000.0
			_record_timestamp.call_deferred(sequence, elapsed)

func _readback(bytes: PackedByteArray, grid: Dictionary, snapshot: Dictionary, metrics: Dictionary, sequence: int) -> void:
	_collect_timestamps()
	metrics.gpu_ms = -1.0
	metrics.gpu_sequence = sequence
	metrics.readback_ms = (Time.get_ticks_usec() - metrics.readback_started) / 1000.0
	_receive.call_deferred(bytes, grid, snapshot, metrics)

func _record_timestamp(sequence: int, elapsed: float) -> void:
	gpu_timings[sequence] = elapsed
	if gpu_timings.size() > 4096:
		gpu_timings.erase(gpu_timings.keys()[0])

func _receive_error(message: String) -> void:
	busy = false
	failure = message
	push_warning("SheepCompute: " + message)

func _receive(bytes: PackedByteArray, grid: Dictionary, snapshot: Dictionary, metrics: Dictionary) -> void:
	if _closed:
		return
	_workers.append(WorkerThreadPool.add_task(_decode.bind(bytes, grid, snapshot, metrics), false, "ComputeDecode"))
	_reap_workers.call_deferred()

func _decode(bytes: PackedByteArray, grid: Dictionary, snapshot: Dictionary, metrics: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var values := bytes.to_float32_array()
	var occupied: PackedInt32Array = grid.occupied
	var flock_counts: PackedInt32Array = grid.flock_counts
	var flock_sums: PackedVector2Array = grid.flock_sums
	var alignment_counts: PackedInt32Array = grid.alignment_counts
	var alignment_sums: PackedVector2Array = grid.alignment_sums
	for index in range(occupied.size()):
		var cell := occupied[index]
		var p: int = index * 8
		flock_counts[cell] = int(values[p])
		flock_sums[cell] = Vector2(values[p + 1], values[p + 2])
		alignment_counts[cell] = int(values[p + 4])
		alignment_sums[cell] = Vector2(values[p + 5], values[p + 6])
	var wolf_field := PackedVector2Array()
	var dog_field := PackedVector2Array()
	wolf_field.resize((grid.width + 1) * (grid.height + 1))
	dog_field.resize(wolf_field.size())
	var pairs := 0
	for index in range(grid.pressure_nodes.size()):
		var node: int = grid.pressure_nodes[index]
		var p: int = occupied.size() * 8 + index * 6
		wolf_field[node] = Vector2(values[p], values[p + 1])
		dog_field[node] = Vector2(values[p + 2], values[p + 3])
		pairs += int(values[p + 4] + values[p + 5])
	var job := SheepPerceptionJob.new()
	job.rows = snapshot.sheep if snapshot.due.has(0) else PackedInt32Array()
	job.resize_output()
	job.stats = AnimalSystem.batch_stats(snapshot)
	job.wolf_pressure = wolf_field
	job.dog_pressure = dog_field
	job.pressure_source_pairs = pairs
	for index in range(job.rows.size()):
		var p: int = occupied.size() * 8 + grid.pressure_nodes.size() * 6 + index * 16
		job.separations[index] = Vector2(values[p], values[p + 1])
		job.centers[index] = Vector2(values[p + 2], values[p + 3])
		job.alignments[index] = Vector2(values[p + 4], values[p + 5])
		job.threat_directions[index] = Vector2(values[p + 6], values[p + 7])
		job.threat_strengths[index] = values[p + 8]
		job.dog_pressures[index] = Vector2(values[p + 9], values[p + 10])
		job.desired_velocities[index] = Vector2(values[p + 11], values[p + 12])
		job.speed_limits[index] = values[p + 13]
		job.neighbor_counts[index] = int(values[p + 14])
		job.refresh_flags[index] = int(values[p + 15] > 0.0)
	job.state = Job.State.COMPLETED
	metrics.decode_ms = (Time.get_ticks_usec() - started) / 1000.0
	_deliver.call_deferred({"grid": grid, "snapshot": snapshot, "metrics": metrics, "sheep": job})

func _deliver(output: Dictionary) -> void:
	busy = false
	if not _closed:
		completed = output

func _release() -> void:
	_render_closed = true
	if _rd == null:
		return
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	for buffer in _buffers:
		if buffer.is_valid():
			_rd.free_rid(buffer)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	_rd = null

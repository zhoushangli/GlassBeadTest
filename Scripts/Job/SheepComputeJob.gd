class_name SheepComputeJob
extends SheepPerceptionJob

var compute: ComputeShaderService
var metrics := ComputeShaderService.Metrics.new()
var input_bytes := PackedByteArray()
var index_bytes := PackedByteArray()
var error: String = ""

var _mutex := Mutex.new()
var _cancelled: bool = false

func execute() -> void:
	var started := Time.get_ticks_usec()
	if is_cancelled():
		return

	# 1) Pack the immutable input on the device thread.
	var pack_started := Time.get_ticks_usec()
	_pack()
	metrics.pack_ms = (Time.get_ticks_usec() - pack_started) / 1000.0
	if is_cancelled():
		return

	# 2) Submit, synchronize and retrieve data on the same device thread.
	var bytes := compute.execute_gpu(self)
	input_bytes = PackedByteArray()
	index_bytes = PackedByteArray()
	if not is_cancelled() and error.is_empty():
		_decode(bytes)
	execute_ms = (Time.get_ticks_usec() - started) / 1000.0

func apply_result() -> void:
	if not error.is_empty():
		target.compute_failed(error, snapshot)
		return

	target.apply_grid(grid, snapshot, self, grid_ms)

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
	compute = null
	input_bytes = PackedByteArray()
	index_bytes = PackedByteArray()

func _pack() -> void:
	var settings: SheepConfig = snapshot.config.sheep
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
		bytes.append_array(column.to_byte_array())
	bytes.append_array(_float32(snapshot.sheep_panic_strength).to_byte_array())
	bytes.append_array(_float32(snapshot.memory_perception_remaining).to_byte_array())
	for column: PackedVector2Array in [snapshot.sheep_panic_source, snapshot.motion_wander_point, fallback]:
		bytes.append_array(column.to_byte_array())
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
		snapshot.dogs, grid.counts, flock_offsets, alignment_offsets, occupied, cell_map, nodes, node_map, _int32(ids), _int32(snapshot.memory_perception_ready), _int32(snapshot.wolf_hunting)]
	var header_fields := [8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 20, 21, 22, 23, 24, 25]
	for index in range(columns.size()):
		indices[header_fields[index]] = indices.size()
		indices.append_array(columns[index])
	indices[17] = flock_offsets.size() / 2
	indices[18] = alignment_offsets.size() / 2
	input_bytes = bytes
	index_bytes = indices.to_byte_array()
	metrics.upload_bytes = input_bytes.size() + index_bytes.size()
	metrics.download_bytes = maxi(4, (occupied.size() * 8 + nodes.size() * 6 + snapshot.sheep.size() * 16) * 4)

func _decode(bytes: PackedByteArray) -> void:
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
	rows = snapshot.sheep if snapshot.due.has(0) else PackedInt32Array()
	resize_output()
	stats = AnimalSystem.batch_stats(snapshot.stats, snapshot.detailed)
	wolf_pressure = wolf_field
	dog_pressure = dog_field
	pressure_source_pairs = pairs
	for index in range(rows.size()):
		var p: int = occupied.size() * 8 + grid.pressure_nodes.size() * 6 + index * 16
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

class_name NumericComputeJob
extends Job

var resources: ComputeShaderService.Resources
var metrics: ProfileService.Metrics = ProfileService.Metrics.new()
var completed: Semaphore = Semaphore.new()
var error: String = ""
var count: int = 0
var structure_version: int = 0
var step: int = 0
var input_bytes := PackedByteArray()
var index_bytes := PackedByteArray()
var columns: Array = []
var output: Array = []
var parameters := PackedFloat32Array()

func capture(storage: AnimalData, settings: SimulationConfig, interval: float) -> void:
	# 1) Copy fixed-step inputs and record the storage generation required at commit.
	var started_at := Time.get_ticks_usec()
	data = storage
	stage = &"Movement"
	delta = interval
	count = storage.index.active_count
	structure_version = storage.index.structure_version
	step = g_gameplayEngine.step_count
	version = g_gameplayEngine.job_service.async_version
	parameters = PackedFloat32Array([interval, settings.sheep.steering_rate, 12.0, 94.0,
		settings.arena_size.x - 12.0, settings.arena_size.y - 58.0, settings.sheep.panic_duration, 0.0,
		settings.sheep.move_speed, settings.wolf.move_speed, settings.sheepdog.move_speed, 0.0])

	columns = [storage.motion.position.slice(0, count), storage.motion.velocity.slice(0, count),
		storage.motion.facing.slice(0, count), storage.motion.desired_velocity.slice(0, count),
		storage.motion.movement_goal.slice(0, count), storage.motion.separation.slice(0, count),
		storage.motion.speed_limit.slice(0, count), storage.motion.intent.slice(0, count), storage.identity.kind.slice(0, count)]

	metrics.prepare_ms = (Time.get_ticks_usec() - started_at) / 1000.0

func execute() -> void:
	if not error.is_empty():
		return

	var started_at := Time.get_ticks_usec()
	input_bytes = PackedByteArray()
	index_bytes = PackedInt32Array([count, 0]).to_byte_array()
	for index in range(6):
		input_bytes.append_array(columns[index].to_byte_array())
	input_bytes.append_array(PackedFloat32Array(Array(columns[6])).to_byte_array())
	for index in [7, 8]:
		index_bytes.append_array(PackedInt32Array(Array(columns[index])).to_byte_array())
	metrics.download_bytes = maxi(4, count * 32)

	metrics.upload_bytes = input_bytes.size() + index_bytes.size()
	metrics.pack_ms = (Time.get_ticks_usec() - started_at) / 1000.0

	var bytes := _execute_gpu()
	if not error.is_empty():
		return

	started_at = Time.get_ticks_usec()
	output.clear()
	for index in range(4):
		output.append(bytes.slice(index * count * 8, (index + 1) * count * 8).to_vector2_array())

	for column: Variant in output:
		for value: Variant in column:
			if (value is Vector2 and not value.is_finite()) or (value is float and not is_finite(value)):
				error = "Numeric output contains a non-finite value"
				return

	metrics.decode_ms = (Time.get_ticks_usec() - started_at) / 1000.0

# Commit only to the unchanged simulation step and preserve corpse and pooled suffixes.
# e.g. a movement result replaces rows before active_count without dropping retained corpse positions.
func commit(storage: AnimalData) -> bool:
	if state != State.COMPLETED or not error.is_empty() or version != g_gameplayEngine.job_service.async_version or step != g_gameplayEngine.step_count or count != storage.index.active_count or structure_version != storage.index.structure_version:
		return false

	var names := ["position", "velocity", "facing", "desired_velocity"]
	if output.size() != names.size():
		return false

	for index in range(names.size()):
		if output[index].size() != count:
			return false

	for index in range(names.size()):
		var column: Variant = output[index]
		column.append_array(storage.motion.get(names[index]).slice(count))
		storage.motion.set(names[index], column)

	state = State.APPLIED
	return true

func run() -> bool:
	var compute: ComputeShaderService = g_gameplayEngine.compute_service
	if not compute.available():
		return false
	if count == 0:
		return true
	if not compute.submit_numeric(self):
		return false

	# 1) Wait for this fixed-step numeric result before allowing dependent simulation work.
	var wait_ms := compute.wait_for(self)
	var applied_at := Time.get_ticks_usec()
	var committed := commit(data)

	# 2) Record end-to-end costs, including waiting and decoding rather than GPU time alone.
	metrics.main_wait_ms = wait_ms
	metrics.apply_ms = (Time.get_ticks_usec() - applied_at) / 1000.0
	metrics.execute_ms = (execution_finished_usec - execution_started_usec) / 1000.0
	metrics.latency_ms = metrics.prepare_ms + (Time.get_ticks_usec() - submitted_usec) / 1000.0
	metrics.processing_ms = metrics.prepare_ms + metrics.pack_ms + metrics.upload_submit_ms + maxf(0.0, metrics.gpu_ms) + maxf(0.0, metrics.buffer_read_ms) + metrics.decode_ms + metrics.apply_ms
	var profile: ProfileService = g_gameplayEngine.profile_service
	profile.record_duration("Numeric/" + String(stage) + "/MainWait", wait_ms)
	for metric in ["prepare_ms", "pack_ms", "device_queue_ms", "upload_submit_ms", "gpu_ms", "gpu_wait_ms", "buffer_read_ms", "decode_ms", "apply_ms"]:
		profile.record_duration("Numeric/" + String(stage) + "/" + metric, metrics.get(metric))
	var samples: Array = profile.numeric_samples[String(stage)]
	samples.append(metrics.to_dictionary())
	if samples.size() > 4096:
		samples.pop_front()

	if not committed:
		compute.report_failure(error if not error.is_empty() else "Movement result no longer matches the simulation step")
		profile.count_event("Failed/" + String(stage))
		return false

	state = Job.State.APPLIED
	return true

func _execute_gpu() -> PackedByteArray:
	assert(OS.get_thread_caller_id() == resources.owner_thread_id)
	var kernel := resources
	var started_at := Time.get_ticks_usec()
	var parameter_bytes := parameters.to_byte_array()
	var sizes := PackedInt32Array([maxi(4, input_bytes.size()), index_bytes.size(), metrics.download_bytes, parameter_bytes.size()])
	for index in range(4):
		if sizes[index] <= kernel.capacities[index]:
			continue

		if kernel.uniform.is_valid():
			resources.device.free_rid(kernel.uniform)
			kernel.uniform = RID()
		if kernel.buffers[index].is_valid():
			resources.device.free_rid(kernel.buffers[index])
		kernel.capacities[index] = maxi(sizes[index], kernel.capacities[index] * 2)
		kernel.buffers[index] = resources.device.storage_buffer_create(kernel.capacities[index])
		if not kernel.buffers[index].is_valid():
			error = "Numeric buffer creation failed"
			return PackedByteArray()
		if index == 3:
			kernel.parameters = PackedByteArray()
	if not kernel.uniform.is_valid():
		var uniforms: Array[RDUniform] = []
		for index in range(4):
			var uniform: RDUniform = RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = index
			uniform.add_id(kernel.buffers[index])
			uniforms.append(uniform)
		kernel.uniform = resources.device.uniform_set_create(uniforms, kernel.shader, 0)
		if not kernel.uniform.is_valid():
			error = "Numeric uniform creation failed"
			return PackedByteArray()

	for index in [0, 1, 3]:
		if index == 3 and parameter_bytes == kernel.parameters:
			continue

		if index == 3:
			metrics.upload_bytes += parameter_bytes.size()
		var bytes := parameter_bytes if index == 3 else (input_bytes if index == 0 else index_bytes)
		if not bytes.is_empty() and resources.device.buffer_update(kernel.buffers[index], 0, bytes.size(), bytes) != OK:
			error = "Numeric upload failed"
			return PackedByteArray()
	kernel.parameters = parameter_bytes
	var sequence := self.sequence
	resources.device.capture_timestamp("Numeric:%d:begin" % sequence)
	var list := resources.device.compute_list_begin()
	resources.device.compute_list_bind_compute_pipeline(list, kernel.pipeline)
	resources.device.compute_list_bind_uniform_set(list, kernel.uniform, 0)
	resources.device.compute_list_dispatch(list, maxi(1, ceili(count / 64.0)), 1, 1)
	resources.device.compute_list_end()
	resources.device.capture_timestamp("Numeric:%d:end" % sequence)
	resources.device.submit()
	metrics.upload_submit_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	started_at = Time.get_ticks_usec()
	resources.device.sync()
	metrics.gpu_wait_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	var begin_time: int = -1
	for index in range(resources.device.get_captured_timestamps_count()):
		var name := resources.device.get_captured_timestamp_name(index)
		if name == "Numeric:%d:begin" % sequence:
			begin_time = resources.device.get_captured_timestamp_gpu_time(index)
		elif name == "Numeric:%d:end" % sequence and begin_time >= 0:
			metrics.gpu_ms = (resources.device.get_captured_timestamp_gpu_time(index) - begin_time) / 1000000.0
	started_at = Time.get_ticks_usec()
	var bytes: PackedByteArray = resources.device.buffer_get_data(kernel.buffers[2], 0, sizes[2])
	metrics.buffer_read_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	if bytes.size() != sizes[2]:
		error = "Numeric readback size mismatch"
	return bytes

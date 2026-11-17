class_name ComputeShaderService
extends Service

const SHADER_PATH := "res://Shaders/Simulation/SheepCompute.glsl"

class Metrics extends RefCounted:
	var main_wait_ms: float = 0.0
	var pack_ms: float = 0.0
	var upload_submit_ms: float = 0.0
	var gpu_ms: float = -1.0
	var device_queue_ms: float = -1.0
	var gpu_wait_ms: float = -1.0
	var buffer_read_ms: float = -1.0
	var decode_ms: float = 0.0
	var apply_ms: float = 0.0
	var grid_ms: float = 0.0
	var prepare_ms: float = 0.0
	var execute_ms: float = 0.0
	var latency_ms: float = 0.0
	var processing_ms: float = 0.0
	var upload_bytes: int = 0
	var download_bytes: int = 0
	var gpu_sequence: int = -1
	var backend: String = "cpu"

	func to_dictionary() -> Dictionary:
		return {"main_wait_ms": main_wait_ms, "pack_ms": pack_ms, "upload_submit_ms": upload_submit_ms, "gpu_ms": gpu_ms,
			"device_queue_ms": device_queue_ms, "gpu_wait_ms": gpu_wait_ms, "buffer_read_ms": buffer_read_ms,
			"decode_ms": decode_ms, "apply_ms": apply_ms, "grid_ms": grid_ms, "prepare_ms": prepare_ms,
			"execute_ms": execute_ms, "latency_ms": latency_ms, "processing_ms": processing_ms,
			"upload_bytes": upload_bytes, "download_bytes": download_bytes, "gpu_sequence": gpu_sequence, "backend": backend}

var backend: String = "auto"
var movement_backend: String = "auto"
var timers_backend: String = "cpu"
var numeric_samples: Dictionary = {"Movement": [], "Timers": []}
var fallback_reason: String = ""
var owner_thread_id: int = 0
var failure: String:
	get:
		_mutex.lock()
		var value := _failure
		_mutex.unlock()
		return value
var busy: bool:
	get:
		_mutex.lock()
		var value := _active != null
		_mutex.unlock()
		return value

var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _ready := Semaphore.new()
var _stopping: bool = false
var _failure: String = ""
var _active: SheepComputeJob
var _sequence: int = 0
var _foreground: NumericComputeJob
var _numeric_kernels: Dictionary = {}
var _numeric_failures: Dictionary = {}

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _uniform_set := RID()
var _buffers: Array[RID] = [RID(), RID(), RID()]
var _capacities := PackedInt32Array([0, 0, 0])

func _startup() -> void:
	_failure = ""
	_numeric_failures.clear()
	fallback_reason = ""
	_stopping = false
	_wake = Semaphore.new()
	_ready = Semaphore.new()
	if backend == "cpu":
		return
	if not _supports_device():
		_failure = "RenderingDevice unavailable with %s / %s" % [DisplayServer.get_name(), RenderingServer.get_current_rendering_method()]
		fallback_reason = _failure
		return

	var error := _thread.start(_thread_main)
	if error != OK:
		_failure = "Compute thread creation failed: %s" % error
	else:
		_ready.wait()
	fallback_reason = failure

func _supports_device() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]

func available() -> bool:
	return started and backend != "cpu" and _thread.is_started() and failure.is_empty()

func submit(job: SheepComputeJob) -> bool:
	if not available() or job == null or job.state != Job.State.IDLE or job.is_cancelled() or job.snapshot == null or job.grid == null:
		return false

	_mutex.lock()
	if _stopping or _active != null:
		_mutex.unlock()
		return false

	_sequence += 1
	job.compute = self
	job.stage = &"Compute"
	job.version = g_gameplayEngine.job_service.async_version
	job.sequence = _sequence
	job.metrics.gpu_sequence = _sequence
	job.submitted_usec = Time.get_ticks_usec()
	job.state = Job.State.PENDING
	_active = job
	_mutex.unlock()
	_wake.post()
	return true

func _thread_main() -> void:
	owner_thread_id = OS.get_thread_caller_id()
	_initialize_device()
	_ready.post()
	if failure.is_empty():
		while true:
			_wake.wait()
			_mutex.lock()
			var stopping := _stopping
			var job: Variant = _foreground if _foreground != null else _active
			if job != null and job.state != Job.State.PENDING:
				job = null
			if not stopping and job != null:
				job.state = Job.State.WORKING
			_mutex.unlock()
			if stopping:
				break
			if job == null:
				continue

			job.metrics.device_queue_ms = (Time.get_ticks_usec() - job.submitted_usec) / 1000.0
			job.run_profiled()
			_mutex.lock()
			if not job.error.is_empty():
				if job is NumericComputeJob:
					_numeric_failures[job.pass_kind] = job.error
				else:
					_failure = job.error
			job.state = Job.State.COMPLETED
			if job is NumericComputeJob:
				_foreground = null
				job.completed.post()
			_mutex.unlock()
	_release_device()

func _initialize_device() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		_failure = "Local RenderingDevice creation failed"

func _take_completed(invalid_only: bool = false) -> SheepComputeJob:
	_mutex.lock()
	var job := _active
	if job == null or job.state != Job.State.COMPLETED or (invalid_only and not job.is_cancelled() and job.version == g_gameplayEngine.job_service.async_version):
		_mutex.unlock()
		return null

	_active = null
	_mutex.unlock()
	return job

func _discard(job: SheepComputeJob) -> void:
	job.state = Job.State.DISCARDED
	g_gameplayEngine.profile_service.count_event("Discarded/Compute")
	job.release_input()

func _process(_delta: float) -> void:
	if not started:
		return

	var job := _take_completed(true)
	if job != null:
		_discard(job)

func flush() -> void:
	var job := _take_completed()
	if job == null:
		return
	if job.is_cancelled() or job.version != g_gameplayEngine.job_service.async_version:
		_discard(job)
		return

	var applied_at := Time.get_ticks_usec()
	var profile: ProfileService = g_gameplayEngine.profile_service
	profile.record_duration("Async/Compute/AwaitApply", (applied_at - job.execution_finished_usec) / 1000.0)
	profile.record_duration("Async/Compute/DeviceThread", job.execute_ms)
	job.apply_result()
	profile.record_duration("Async/Compute/Apply", (Time.get_ticks_usec() - applied_at) / 1000.0)
	profile.record_duration("Async/Compute/Latency", (Time.get_ticks_usec() - job.snapshot.captured_usec) / 1000.0)
	profile.count_event("Failed/Compute" if not job.error.is_empty() else "Applied/Compute")
	if not job.error.is_empty():
		fallback_reason = job.error
	job.state = Job.State.APPLIED
	job.release_input()

func _reset() -> void:
	for samples: Array in numeric_samples.values():
		samples.clear()
	_mutex.lock()
	if _active != null:
		_active.cancel()
	_mutex.unlock()
	var job := _take_completed()
	if job != null:
		_discard(job)

func _shutdown() -> void:
	_reset()
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	if _thread.is_started():
		_thread.wait_to_finish()
	if _active != null:
		_discard(_active)
		_active = null

func execute_gpu(job: SheepComputeJob) -> PackedByteArray:
	assert(OS.get_thread_caller_id() == owner_thread_id)
	if job.is_cancelled():
		return PackedByteArray()
	if not _shader.is_valid():
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(SHADER_PATH).replace("#[compute]", "")
		var spirv := _rd.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_compute.is_empty():
			job.error = spirv.compile_error_compute
			return PackedByteArray()

		_shader = _rd.shader_create_from_spirv(spirv)
		if not _shader.is_valid():
			job.error = "Compute shader creation failed"
			return PackedByteArray()

		_pipeline = _rd.compute_pipeline_create(_shader)
		if not _pipeline.is_valid():
			job.error = "Compute pipeline creation failed"
			return PackedByteArray()

	var metrics := job.metrics
	var started_at := Time.get_ticks_usec()
	var sizes := PackedInt32Array([job.input_bytes.size(), job.index_bytes.size(), metrics.download_bytes])
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
			if not _buffers[index].is_valid():
				job.error = "Compute buffer creation failed"
				return PackedByteArray()

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
		if not _uniform_set.is_valid():
			job.error = "Compute uniform creation failed"
			return PackedByteArray()

	for index in range(2):
		var bytes := job.input_bytes if index == 0 else job.index_bytes
		var error := _rd.buffer_update(_buffers[index], 0, sizes[index], bytes)
		if error != OK:
			job.error = "Compute upload failed: %s" % error
			return PackedByteArray()

	var sequence := metrics.gpu_sequence
	_rd.capture_timestamp("Compute:%d:begin" % sequence)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
	var counts := PackedInt32Array([job.grid.occupied.size(), job.grid.pressure_nodes.size(), job.snapshot.sheep.size() if job.snapshot.due.has(0) else 0])
	for stage in range(3):
		if counts[stage] == 0:
			continue

		var push := PackedInt32Array([stage]).to_byte_array()
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(counts[stage] / 64.0), 1, 1)
		_rd.compute_list_add_barrier(list)
	_rd.compute_list_end()
	_rd.capture_timestamp("Compute:%d:end" % sequence)
	_rd.submit()
	metrics.upload_submit_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	started_at = Time.get_ticks_usec()
	_rd.sync()
	metrics.gpu_wait_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	var begin_time: int = -1
	for index in range(_rd.get_captured_timestamps_count()):
		var name := _rd.get_captured_timestamp_name(index)
		if name == "Compute:%d:begin" % sequence:
			begin_time = _rd.get_captured_timestamp_gpu_time(index)
		elif name == "Compute:%d:end" % sequence and begin_time >= 0:
			metrics.gpu_ms = (_rd.get_captured_timestamp_gpu_time(index) - begin_time) / 1000000.0
	if job.is_cancelled():
		return PackedByteArray()

	started_at = Time.get_ticks_usec()
	var output := _rd.buffer_get_data(_buffers[2], 0, sizes[2])
	metrics.buffer_read_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	if output.size() != sizes[2]:
		job.error = "Compute readback size mismatch"
	return output

func run_numeric(storage: AnimalData, delta: float, kind: NumericComputeJob.Pass) -> int:
	var selected_backend := movement_backend if kind == NumericComputeJob.Pass.MOVEMENT else timers_backend
	if selected_backend == "cpu" or storage.active_count == 0:
		return 0
	if not available():
		return -1 if selected_backend == "gpu" else 0
	_mutex.lock()
	var failed: bool = _numeric_failures.has(kind)
	_mutex.unlock()
	if failed:
		return -1 if selected_backend == "gpu" else 0

	var job := NumericComputeJob.new()
	job.capture(storage, g_gameplayEngine.config, delta, kind)
	job.compute = self
	_mutex.lock()
	if _stopping or _foreground != null:
		_mutex.unlock()
		return -1 if selected_backend == "gpu" else 0

	_sequence += 1
	job.sequence = _sequence
	job.metrics.gpu_sequence = _sequence
	job.metrics.backend = "gpu"
	job.submitted_usec = Time.get_ticks_usec()
	job.state = Job.State.PENDING
	_foreground = job
	_mutex.unlock()
	var waiting_at := Time.get_ticks_usec()
	_wake.post()
	job.completed.wait()
	var wait_ms := (Time.get_ticks_usec() - waiting_at) / 1000.0
	var applied_at := Time.get_ticks_usec()
	var committed := job.commit(storage)
	job.metrics.main_wait_ms = wait_ms
	job.metrics.apply_ms = (Time.get_ticks_usec() - applied_at) / 1000.0
	job.metrics.execute_ms = (job.execution_finished_usec - job.execution_started_usec) / 1000.0
	job.metrics.latency_ms = job.metrics.prepare_ms + (Time.get_ticks_usec() - job.submitted_usec) / 1000.0
	job.metrics.processing_ms = job.metrics.prepare_ms + job.metrics.pack_ms + job.metrics.upload_submit_ms + maxf(0.0, job.metrics.gpu_ms) + maxf(0.0, job.metrics.buffer_read_ms) + job.metrics.decode_ms + job.metrics.apply_ms
	var profile: ProfileService = g_gameplayEngine.profile_service
	profile.record_duration("Numeric/" + String(job.stage) + "/MainWait", wait_ms)
	for metric in ["prepare_ms", "pack_ms", "device_queue_ms", "upload_submit_ms", "gpu_ms", "gpu_wait_ms", "buffer_read_ms", "decode_ms", "apply_ms"]:
		profile.record_duration("Numeric/" + String(job.stage) + "/" + metric, job.metrics.get(metric))
	var samples: Array = numeric_samples[String(job.stage)]
	samples.append(job.metrics.to_dictionary())
	if samples.size() > 4096:
		samples.pop_front()
	if not committed:
		fallback_reason = job.error if not job.error.is_empty() else "Numeric result no longer matches the simulation step"
		profile.count_event("Failed/" + String(job.stage))
		return -1 if selected_backend == "gpu" else 0

	job.state = Job.State.APPLIED
	return 1

func execute_numeric_gpu(job: NumericComputeJob) -> PackedByteArray:
	assert(OS.get_thread_caller_id() == owner_thread_id)
	if not _numeric_kernels.has(job.pass_kind):
		_numeric_kernels[job.pass_kind] = {"shader": RID(), "pipeline": RID(), "uniform": RID(),
			"buffers": [RID(), RID(), RID(), RID()], "capacities": PackedInt32Array([0, 0, 0, 0]), "parameters": PackedByteArray()}
	var kernel: Dictionary = _numeric_kernels[job.pass_kind]
	if not kernel.shader.is_valid():
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string("res://Shaders/Simulation/TimerCompute.glsl" if job.pass_kind == NumericComputeJob.Pass.TIMERS else "res://Shaders/Simulation/NumericCompute.glsl").replace("#[compute]", "")
		var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_compute.is_empty():
			job.error = spirv.compile_error_compute
			return PackedByteArray()

		kernel.shader = _rd.shader_create_from_spirv(spirv)
		if not kernel.shader.is_valid():
			job.error = "Numeric shader creation failed"
			return PackedByteArray()

		kernel.pipeline = _rd.compute_pipeline_create(kernel.shader)
		if not kernel.pipeline.is_valid():
			job.error = "Numeric pipeline creation failed"
			return PackedByteArray()

	var started_at := Time.get_ticks_usec()
	var parameters := job.timer_parameters.to_byte_array() if job.pass_kind == NumericComputeJob.Pass.TIMERS else job.parameters.to_byte_array()
	var sizes := PackedInt32Array([maxi(4, job.input_bytes.size()), job.index_bytes.size(), job.metrics.download_bytes, parameters.size()])
	for index in range(4):
		if sizes[index] <= kernel.capacities[index]:
			continue

		if kernel.uniform.is_valid():
			_rd.free_rid(kernel.uniform)
			kernel.uniform = RID()
		if kernel.buffers[index].is_valid():
			_rd.free_rid(kernel.buffers[index])
		kernel.capacities[index] = maxi(sizes[index], kernel.capacities[index] * 2)
		kernel.buffers[index] = _rd.storage_buffer_create(kernel.capacities[index])
		if not kernel.buffers[index].is_valid():
			job.error = "Numeric buffer creation failed"
			return PackedByteArray()
		if index == 3:
			kernel.parameters = PackedByteArray()
	if not kernel.uniform.is_valid():
		var uniforms: Array[RDUniform] = []
		for index in range(4):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = index
			uniform.add_id(kernel.buffers[index])
			uniforms.append(uniform)
		kernel.uniform = _rd.uniform_set_create(uniforms, kernel.shader, 0)
		if not kernel.uniform.is_valid():
			job.error = "Numeric uniform creation failed"
			return PackedByteArray()

	for index in [0, 1, 3]:
		if index == 3 and parameters == kernel.parameters:
			continue

		if index == 3:
			job.metrics.upload_bytes += parameters.size()
		var bytes := parameters if index == 3 else (job.input_bytes if index == 0 else job.index_bytes)
		if not bytes.is_empty() and _rd.buffer_update(kernel.buffers[index], 0, bytes.size(), bytes) != OK:
			job.error = "Numeric upload failed"
			return PackedByteArray()
	kernel.parameters = parameters
	var sequence := job.sequence
	_rd.capture_timestamp("Numeric:%d:begin" % sequence)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, kernel.pipeline)
	_rd.compute_list_bind_uniform_set(list, kernel.uniform, 0)
	_rd.compute_list_dispatch(list, maxi(1, ceili(job.count / 64.0)), 1, 1)
	_rd.compute_list_end()
	_rd.capture_timestamp("Numeric:%d:end" % sequence)
	_rd.submit()
	job.metrics.upload_submit_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	started_at = Time.get_ticks_usec()
	_rd.sync()
	job.metrics.gpu_wait_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	var begin_time: int = -1
	for index in range(_rd.get_captured_timestamps_count()):
		var name := _rd.get_captured_timestamp_name(index)
		if name == "Numeric:%d:begin" % sequence:
			begin_time = _rd.get_captured_timestamp_gpu_time(index)
		elif name == "Numeric:%d:end" % sequence and begin_time >= 0:
			job.metrics.gpu_ms = (_rd.get_captured_timestamp_gpu_time(index) - begin_time) / 1000000.0
	started_at = Time.get_ticks_usec()
	var bytes: PackedByteArray = _rd.buffer_get_data(kernel.buffers[2], 0, sizes[2])
	job.metrics.buffer_read_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	if bytes.size() != sizes[2]:
		job.error = "Numeric readback size mismatch"
	return bytes

func _release_device() -> void:
	if _rd == null:
		return

	for kernel: Dictionary in _numeric_kernels.values():
		if kernel.uniform.is_valid():
			_rd.free_rid(kernel.uniform)
		for buffer: RID in kernel.buffers:
			if buffer.is_valid():
				_rd.free_rid(buffer)
		if kernel.pipeline.is_valid():
			_rd.free_rid(kernel.pipeline)
		if kernel.shader.is_valid():
			_rd.free_rid(kernel.shader)
	_numeric_kernels.clear()
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	for buffer in _buffers:
		if buffer.is_valid():
			_rd.free_rid(buffer)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	_rd.free()
	_rd = null
	_shader = RID()
	_pipeline = RID()
	_uniform_set = RID()
	_buffers = [RID(), RID(), RID()]
	_capacities = PackedInt32Array([0, 0, 0])

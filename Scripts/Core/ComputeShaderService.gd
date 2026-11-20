class_name ComputeShaderService
extends Service

const SHEEP_SHADER: RDShaderFile = preload("res://Shaders/Simulation/SheepCompute.glsl")
const MOVEMENT_SHADER: RDShaderFile = preload("res://Shaders/Simulation/NumericCompute.glsl")

class Resources extends RefCounted:
	var device: RenderingDevice
	var owner_thread_id: int = 0
	var shader := RID()
	var pipeline := RID()
	var uniform := RID()
	var buffers: Array[RID] = []
	var capacities := PackedInt32Array()
	var parameters := PackedByteArray()

	func _init(count: int) -> void:
		buffers.resize(count)
		capacities.resize(count)

var sheep_resources: Resources = Resources.new(3)
var movement_resources: Resources = Resources.new(4)

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

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _wake: Semaphore = Semaphore.new()
var _ready: Semaphore = Semaphore.new()
var _stopping: bool = false
var _failure: String = ""
var _active: SheepComputeJob
var _sequence: int = 0
var _foreground: NumericComputeJob

var _rd: RenderingDevice

func _startup() -> void:
	_failure = ""
	_stopping = false
	_wake = Semaphore.new()
	_ready = Semaphore.new()
	if not _supports_device():
		_failure = "RenderingDevice unavailable with %s / %s" % [DisplayServer.get_name(), RenderingServer.get_current_rendering_method()]
		return

	var error := _thread.start(_thread_main)
	if error != OK:
		_failure = "Compute thread creation failed: %s" % error
	else:
		_ready.wait()

func _supports_device() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() in ["forward_plus", "mobile"]

func available() -> bool:
	return started and _thread.is_started() and failure.is_empty()

func submit(job: SheepComputeJob) -> bool:
	if not available() or job == null or job.state != Job.State.IDLE or job.is_cancelled() or job.snapshot == null or job.grid == null:
		return false

	_mutex.lock()
	if _stopping or _active != null:
		_mutex.unlock()
		return false

	_sequence += 1
	job.resources = sheep_resources
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
	# 1) Create and release the local RenderingDevice on its owning thread.
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
		return

	for resources in [sheep_resources, movement_resources]:
		resources.device = _rd
		resources.owner_thread_id = owner_thread_id

	_failure = _initialize_sheep_pipeline()
	if _failure.is_empty():
		_failure = _initialize_movement_pipeline()

func _initialize_sheep_pipeline() -> String:
	var spirv := SHEEP_SHADER.get_spirv()
	if spirv == null or spirv.bytecode_compute.is_empty():
		return "Imported sheep shader has no compute bytecode"
	if not spirv.compile_error_compute.is_empty():
		return spirv.compile_error_compute

	sheep_resources.shader = _rd.shader_create_from_spirv(spirv)
	if not sheep_resources.shader.is_valid():
		return "Compute shader creation failed"

	sheep_resources.pipeline = _rd.compute_pipeline_create(sheep_resources.shader)
	if not sheep_resources.pipeline.is_valid():
		return "Compute pipeline creation failed"

	return ""

func _initialize_movement_pipeline() -> String:
	var kernel := movement_resources
	if not kernel.shader.is_valid():
		var shader_file := MOVEMENT_SHADER
		var spirv := shader_file.get_spirv()
		if spirv == null or spirv.bytecode_compute.is_empty():
			return "Imported numeric shader has no compute bytecode"
		if not spirv.compile_error_compute.is_empty():
			return spirv.compile_error_compute

		kernel.shader = _rd.shader_create_from_spirv(spirv)
		if not kernel.shader.is_valid():
			return "Numeric shader creation failed"

		kernel.pipeline = _rd.compute_pipeline_create(kernel.shader)
		if not kernel.pipeline.is_valid():
			return "Numeric pipeline creation failed"

	return ""

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

	job.state = Job.State.APPLIED
	job.release_input()

func _reset() -> void:
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

func _release_device() -> void:
	if _rd == null:
		return

	for kernel in [movement_resources]:
		if kernel.uniform.is_valid():
			_rd.free_rid(kernel.uniform)
		for buffer: RID in kernel.buffers:
			if buffer.is_valid():
				_rd.free_rid(buffer)
		if kernel.pipeline.is_valid():
			_rd.free_rid(kernel.pipeline)
		if kernel.shader.is_valid():
			_rd.free_rid(kernel.shader)
	if sheep_resources.uniform.is_valid():
		_rd.free_rid(sheep_resources.uniform)
	for buffer in sheep_resources.buffers:
		if buffer.is_valid():
			_rd.free_rid(buffer)
	if sheep_resources.pipeline.is_valid():
		_rd.free_rid(sheep_resources.pipeline)
	if sheep_resources.shader.is_valid():
		_rd.free_rid(sheep_resources.shader)
	_rd.free()
	_rd = null
	movement_resources = Resources.new(4)
	sheep_resources.device = null
	sheep_resources.shader = RID()
	sheep_resources.pipeline = RID()
	sheep_resources.uniform = RID()
	sheep_resources.buffers = [RID(), RID(), RID()]
	sheep_resources.capacities = PackedInt32Array([0, 0, 0])

func submit_numeric(job: NumericComputeJob) -> bool:
	if not available() or job == null or job.state != Job.State.IDLE:
		return false

	_mutex.lock()
	if _stopping or _foreground != null:
		_mutex.unlock()
		return false

	_sequence += 1
	job.resources = movement_resources
	job.sequence = _sequence
	job.metrics.gpu_sequence = _sequence
	job.metrics.backend = "gpu"
	job.submitted_usec = Time.get_ticks_usec()
	job.state = Job.State.PENDING
	_foreground = job
	_mutex.unlock()
	_wake.post()
	return true

func wait_for(job: NumericComputeJob) -> float:
	var started_at := Time.get_ticks_usec()
	job.completed.wait()
	return (Time.get_ticks_usec() - started_at) / 1000.0

func report_failure(message: String) -> void:
	_mutex.lock()
	_failure = message
	_mutex.unlock()

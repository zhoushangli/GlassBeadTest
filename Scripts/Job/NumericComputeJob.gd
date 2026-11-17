class_name NumericComputeJob
extends Job

enum Pass { MOVEMENT, TIMERS }

var pass_kind: Pass = Pass.MOVEMENT
var compute: ComputeShaderService
var metrics := ComputeShaderService.Metrics.new()
var completed := Semaphore.new()
var error: String = ""
var count: int = 0
var structure_version: int = 0
var step: int = 0
var input_bytes := PackedByteArray()
var index_bytes := PackedByteArray()
var columns: Array = []
var output: Array = []
var parameters := PackedFloat32Array()
var timer_parameters := PackedFloat64Array()

func capture(storage: AnimalData, settings: SimulationConfig, interval: float, kind: Pass) -> void:
	var started_at := Time.get_ticks_usec()
	pass_kind = kind
	stage = &"Movement" if kind == Pass.MOVEMENT else &"Timers"
	delta = interval
	count = storage.active_count
	structure_version = storage.structure_version
	step = g_gameplayEngine.step_count
	version = g_gameplayEngine.job_service.async_version
	timer_parameters = PackedFloat64Array([interval, settings.sheep.panic_duration])
	parameters = PackedFloat32Array([interval, settings.sheep.steering_rate, 12.0, 94.0,
		settings.arena_size.x - 12.0, settings.arena_size.y - 58.0, settings.sheep.panic_duration, 0.0,
		settings.sheep.move_speed, settings.wolf.move_speed, settings.sheepdog.move_speed, 0.0])
	if kind == Pass.MOVEMENT:
		columns = [storage.motion_position.slice(0, count), storage.motion_velocity.slice(0, count),
			storage.motion_facing.slice(0, count), storage.motion_desired_velocity.slice(0, count),
			storage.motion_movement_goal.slice(0, count), storage.motion_separation.slice(0, count),
			storage.motion_speed_limit.slice(0, count), storage.motion_intent.slice(0, count), storage.identity_kind.slice(0, count)]
	else:
		columns = [storage.motion_wander_remaining.slice(0, count), storage.memory_perception_remaining.slice(0, count),
			storage.sheep_panic_strength.slice(0, count), storage.identity_kind.slice(0, count)]
	metrics.prepare_ms = (Time.get_ticks_usec() - started_at) / 1000.0

func execute() -> void:
	var started_at := Time.get_ticks_usec()
	input_bytes = PackedByteArray()
	index_bytes = PackedInt32Array([count, pass_kind]).to_byte_array()
	if pass_kind == Pass.MOVEMENT:
		for index in range(6):
			input_bytes.append_array(columns[index].to_byte_array())
		input_bytes.append_array(PackedFloat32Array(Array(columns[6])).to_byte_array())
		for index in [7, 8]:
			index_bytes.append_array(PackedInt32Array(Array(columns[index])).to_byte_array())
		metrics.download_bytes = maxi(4, count * 32)
	else:
		for index in range(3):
			input_bytes.append_array(columns[index].to_byte_array())
		index_bytes.append_array(PackedInt32Array(Array(columns[3])).to_byte_array())
		metrics.download_bytes = maxi(8, count * 24)
	metrics.upload_bytes = input_bytes.size() + index_bytes.size()
	metrics.pack_ms = (Time.get_ticks_usec() - started_at) / 1000.0
	var bytes := compute.execute_numeric_gpu(self)
	if not error.is_empty():
		return

	started_at = Time.get_ticks_usec()
	output.clear()
	if pass_kind == Pass.MOVEMENT:
		for index in range(4):
			output.append(bytes.slice(index * count * 8, (index + 1) * count * 8).to_vector2_array())
	else:
		for index in range(3):
			output.append(bytes.slice(index * count * 8, (index + 1) * count * 8).to_float64_array())

	for column: Variant in output:
		for value: Variant in column:
			if (value is Vector2 and not value.is_finite()) or (value is float and not is_finite(value)):
				error = "Numeric output contains a non-finite value"
				return
	metrics.decode_ms = (Time.get_ticks_usec() - started_at) / 1000.0

func commit(storage: AnimalData) -> bool:
	if state != State.COMPLETED or not error.is_empty() or version != g_gameplayEngine.job_service.async_version or step != g_gameplayEngine.step_count or count != storage.active_count or structure_version != storage.structure_version:
		return false

	var names := ["motion_position", "motion_velocity", "motion_facing", "motion_desired_velocity"] if pass_kind == Pass.MOVEMENT else ["motion_wander_remaining", "memory_perception_remaining", "sheep_panic_strength"]
	if output.size() != names.size():
		return false
	for index in range(names.size()):
		if output[index].size() != count:
			return false

	for index in range(names.size()):
		var column: Variant = output[index]
		column.append_array(storage.get(names[index]).slice(count))
		storage.set(names[index], column)
	state = State.APPLIED
	return true

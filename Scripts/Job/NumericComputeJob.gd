class_name NumericComputeJob
extends Job

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

func capture(storage: AnimalData, settings: SimulationConfig, interval: float) -> void:
	# 1) Copy fixed-step inputs and record the storage generation required at commit.
	var started_at := Time.get_ticks_usec()
	stage = &"Movement"
	delta = interval
	count = storage.active_count
	structure_version = storage.structure_version
	step = g_gameplayEngine.step_count
	version = g_gameplayEngine.job_service.async_version
	parameters = PackedFloat32Array([interval, settings.sheep.steering_rate, 12.0, 94.0,
		settings.arena_size.x - 12.0, settings.arena_size.y - 58.0, settings.sheep.panic_duration, 0.0,
		settings.sheep.move_speed, settings.wolf.move_speed, settings.sheepdog.move_speed, 0.0])

	columns = [storage.motion_position.slice(0, count), storage.motion_velocity.slice(0, count),
		storage.motion_facing.slice(0, count), storage.motion_desired_velocity.slice(0, count),
		storage.motion_movement_goal.slice(0, count), storage.motion_separation.slice(0, count),
		storage.motion_speed_limit.slice(0, count), storage.motion_intent.slice(0, count), storage.identity_kind.slice(0, count)]

	metrics.prepare_ms = (Time.get_ticks_usec() - started_at) / 1000.0

func execute() -> void:
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

	var bytes := compute.execute_numeric_gpu(self)
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
	if state != State.COMPLETED or not error.is_empty() or version != g_gameplayEngine.job_service.async_version or step != g_gameplayEngine.step_count or count != storage.active_count or structure_version != storage.structure_version:
		return false

	var names := ["motion_position", "motion_velocity", "motion_facing", "motion_desired_velocity"]
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

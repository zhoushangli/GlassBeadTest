extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var storage := AnimalData.new()
	storage.append_slot()
	storage.append_slot()
	storage.index.active_count = 2
	storage.index.retained_count = 2
	var before: Dictionary = {}
	for group_name in ["identity", "motion", "memory", "brain", "sheep", "wolf", "dog"]:
		var group: RefCounted = storage.get(group_name)
		for property in group.get_property_list():
			if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				continue

			var column: Variant = group.get(property.name)
			for row in range(2):
				match typeof(column[row]):
					TYPE_INT, TYPE_FLOAT:
						column[row] = row + 1
					TYPE_VECTOR2:
						column[row] = Vector2(row + 1, row + 3)
					TYPE_VECTOR4:
						column[row] = Vector4(row + 1, row + 2, row + 3, row + 4)
					TYPE_ARRAY:
						column[row] = [row]
					TYPE_PACKED_INT32_ARRAY:
						column[row] = PackedInt32Array([row])
			group.set(property.name, column)
			before[group_name + "." + property.name] = column.duplicate()

	storage.identity.animal_id[0] = AnimalID.make(0, 11)
	storage.identity.animal_id[1] = AnimalID.make(1, 12)
	before["identity.animal_id"] = storage.identity.animal_id.duplicate()
	for row in range(2):
		var handle := AnimalEntity.new()
		handle.row = row
		handle.id = storage.identity.animal_id[row]
		storage.index.handles[row] = handle
	var first := storage.index.handles[0]
	var second := storage.index.handles[1]
	var version := storage.index.structure_version
	var job := Job.new()
	job.data = storage
	job._capture_batch_storage()
	storage.swap_rows(0, 1)
	for key: String in before:
		var parts := key.split(".")
		var group: RefCounted = storage.get(parts[0])
		var column: Variant = group.get(parts[1])
		_check(column[0] == before[key][1] and column[1] == before[key][0], "complete row swap: " + key)
	_check(storage.index.structure_version == version + 1, "row swap increments structure generation")
	_check(first.row == 1 and second.row == 0 and storage.row_of_id(first.id) == 1 and storage.row_of_id(second.id) == 0, "handles and both slot mappings follow complete rows")
	_check(job.batch_input.index.handles[0] != first and job.batch_input.index.handles[0].row == 0 and job.batch_input.identity.animal_id[0] == first.id, "synchronous worker handles retain captured identity and row after live swaps")
	storage.motion.position[0] = Vector2(99, 101)
	_check(job.batch_input.motion.position[1] == before["motion.position"][1], "synchronous worker columns remain isolated from live writes")
	var motion := storage.motion
	storage.reset_row(0)
	_check(storage.motion == motion and storage.motion.position[0] == Vector2.ZERO and storage.motion.position[1] != Vector2.ZERO, "row reset preserves group references and unrelated rows")
	storage.clear()
	_check(storage.motion == motion and motion.position.is_empty() and first.row == -1 and second.row == -1, "clear preserves group references and invalidates handles")
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	_check(spatial.current.cell_size == 30.0 and spatial.current.width == 0, "empty spatial state preserves the default cell size")
	spatial.current.cell_size = 60.0
	g_gameplayEngine.grid_service._reset()
	_check(spatial.current.cell_size == 60.0 and spatial.current.width == 0, "spatial reset retains cell size without publishing old membership")
	print("DATA_HIERARCHY_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

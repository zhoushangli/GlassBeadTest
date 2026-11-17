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
	for slot in [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]:
		for serial in [1, 7, 0x80000000, 0xFFFFFFFF]:
			var id := AnimalID.make(slot, serial)
			_check(AnimalID.is_valid(id) and AnimalID.get_slot(id) == slot and (id & AnimalID.PART_MASK) == serial, "unsigned parts round-trip through signed identity")
	_check(not AnimalID.is_valid(AnimalID.INVALID) and not AnimalID.is_valid(1 << 32), "zero life serial is reserved")
	_check(AnimalID.make(3, 7) == 12884901895 and AnimalID.make(0xFFFFFFFF, 0xFFFFFFFF) == -1, "bit layout and sign bit match contract")
	_check(AnimalID.is_valid(-1), "negative identity is valid")
	var scene: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 0
	root.add_child(scene)
	var engine: Node = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.paused = true
	var service: EntityService = engine.entity_service
	var data := service.data
	var first := service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(300, 300))[0]
	var second := service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(500, 300))[0]
	var first_id := first.id
	var second_id := second.id
	var first_slot := AnimalID.get_slot(first_id)
	var snapshot: AnimalSnapshot = engine.animal_system.decision_snapshot()
	var alias := AnimalEntity.new()
	alias.id = second_id
	_check(data.live(alias) == second and data.row_of_id(second_id) == second.row, "resolver returns the canonical current-row handle")
	_check(data.row_of_id(AnimalID.INVALID) == -1 and data.row_of_id(-1) == -1, "resolver rejects invalid and unallocated slots")
	service.capture(first)
	service.remove_expired()
	_check(second.row == 0 and second.id == second_id and data.row_of_id(second_id) == 0, "row compaction preserves full identity")
	_check(engine.animal_system.snapshot_animal(snapshot, 1) == second and engine.animal_system.snapshot_animal(snapshot, 0) == null, "snapshot resolves moved life and rejects captured life")
	service.remove_expired(10.0)
	var replacement := service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 300))[0]
	_check(AnimalID.get_slot(replacement.id) == first_slot and replacement.id != first_id and data.live(first) == null, "slot reuse changes the full ID without reviving its old handle")
	_check(engine.animal_system.snapshot_animal(snapshot, 0) == null, "old snapshot cannot resolve a replacement life")
	var old := replacement.id
	var previous := replacement
	engine.reset_simulation()
	replacement = service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 300))[0]
	_check(replacement.id != old and data.live(previous) == null, "reset keeps serial allocation monotonic")
	old = replacement.id
	service.clear()
	replacement = service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(600, 300))[0]
	_check(replacement.id != old and data.row_of_id(old) == -1, "clear cannot reuse a prior full ID")
	var allocated := data.row_to_slot.size()
	var active := data.active_count
	var state: int = engine.rng.state
	service._next_uid = AnimalID.PART_MASK - 1
	_check(service.spawn(AnimalEntity.Kind.SHEEP, 2).is_empty() and data.active_count == active and data.row_to_slot.size() == allocated and engine.rng.state == state, "insufficient serial capacity rejects whole batch before mutation")
	var final := service.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(700, 300))[0]
	_check(AnimalID.is_valid(final.id), "last serial remains usable")
	active = data.active_count
	_check(service.spawn(AnimalEntity.Kind.SHEEP, 1).is_empty() and data.active_count == active, "exhausted allocator never wraps")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("ANIMAL_ID_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

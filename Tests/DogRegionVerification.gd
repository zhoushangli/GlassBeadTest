extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _job() -> DogPerceptionJob:
	var job := DogPerceptionJob.new()
	job.snapshot = engine.animal_system.decision_snapshot(PackedInt32Array([2]))
	job.grid = GridService.build_snapshot(job.snapshot)
	job.rows = job.snapshot.dogs
	job.execute()
	return job

func _empty() -> void:
	engine.reset_simulation()
	engine.paused = true

func _aggregates() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data := entities.data
	var points := [Vector2(119, 200), Vector2(120, 200), Vector2(239, 210), Vector2(240, 200), Vector2(1290, 660)]
	for point in points:
		var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, point)[0]
		data.motion_velocity[sheep.row] = Vector2(sheep.row, sheep.row * 2)
	entities.spawn(AnimalEntity.Kind.WOLF, 1, points[0])
	var grid := GridService.build_snapshot(engine.animal_system.decision_snapshot())
	_check(grid.region_width == 11 and grid.region_height == 6, "partial edge regions use ceiling dimensions")
	_check(grid.region_at(points[0]) != grid.region_at(points[1]) and grid.region_at(points[1]) == grid.region_at(points[2]), "120 px boundaries group four fine cells")
	var region := grid.region_at(points[1])
	_check(grid.region_counts[region] == 2, "region counts only sheep")
	_check(grid.region_centers[region].is_equal_approx(Vector2(179.5, 205)), "region center is sheep-weighted")
	_check(grid.region_velocities[region].is_equal_approx(Vector2(1.5, 3)), "region velocity averages sheep")
	var count := 0
	for value in grid.region_counts:
		count += value
	_check(count == points.size(), "every sheep belongs to exactly one region")
	_check(grid.has_region(grid.region_at(points[4])) and not grid.has_region(-1), "edge and invalid region validation")

func _assignments() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data := entities.data
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(500, 300))[0]
	var stray := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(680, 300))[0]
	var dogs := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 2, Vector2(590, 300))
	var first := _job()
	_check(first.region_ids[0] != first.region_ids[1], "coverage penalty spreads nearby dogs across occupied regions")
	_check(first.region_coverage[first.region_ids[0]] == 1 and first.region_coverage[first.region_ids[1]] == 1, "coverage updates during stable assignment")
	var expected := first.region_ids.duplicate()
	var reversed := _job()
	reversed.rows = PackedInt32Array([dogs[1].row, dogs[0].row])
	reversed.execute()
	_check(reversed.region_ids[0] == expected[1] and reversed.region_ids[1] == expected[0], "entity IDs stabilize assignments despite row iteration order")
	engine.dog_system.apply_decision(first)
	var dog := dogs[0]
	var region := data.dog_region[dog.row]
	_check(region >= 0 and data.dog_protected_sheep[dog.row] == null, "region replaces live sheep anchor")
	data.dog_assignment_remaining[dog.row] = 100.0
	data.motion_position[dog.row] = Vector2(1000, 300)
	var held := _job()
	_check(held.region_ids[0] == region and held.returning_flags[0] == 1, "assignment interval holds region and leash requires return")
	var old := _job()
	data.dog_region[dog.row] = -1
	engine.dog_system.apply_decision(old)
	_check(data.dog_region[dog.row] == -1, "stale result cannot replace newer region state")
	data.dog_region[dog.row] = region
	data.motion_position[sheep.row] = Vector2(850, 500)
	data.motion_position[stray.row] = Vector2(850, 500)
	var moved := _job()
	_check(moved.region_ids[0] != region, "empty region reassigns before interval expires")
	var assigned_region := data.dog_region[dogs[1].row]
	entities.capture(sheep)
	entities.remove_expired()
	_check(data.dog_region[dogs[1].row] == assigned_region, "row compaction moves region with its dog")
	entities.capture(stray)
	entities.remove_expired()
	var empty := _job()
	_check(empty.region_ids == PackedInt32Array([-1, -1]), "no sheep yields no responsibilities")
	engine.dog_system.apply_decision(empty)
	engine.dog_system.advance_time(0.1)
	_check(data.dog_region[dog.row] == -1 and data.memory_target[dog.row] == null and data.dog_collected_sheep[dog.row] == null, "empty world clears dog tasks")

func _cross_region() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data := entities.data
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(500, 300))[0]
	var stray := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(680, 300))[0]
	var dog := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(600, 300))[0]
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(650, 300))[0]
	data.motion_facing[dog.row] = Vector2.RIGHT
	var job := _job()
	data.dog_region[dog.row] = job.grid.region_at(data.motion_position[sheep.row])
	data.dog_assignment_remaining[dog.row] = 100.0
	job = _job()
	_check(job.region_ids[0] != job.grid.region_at(data.motion_position[stray.row]) and job.strays.has(stray.row), "stray lookup crosses responsibility boundary")
	_check(job.wolf_rows[0] == wolf.row, "visible wolf across region boundary takes priority")
	engine.dog_system.apply_decision(job)
	_check(data.memory_target[dog.row] == wolf and data.dog_collected_sheep[dog.row] == null, "exclusive drive task suppresses collection")

func _run() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 0
	scene.simulation_config.arena_size = Vector2(1300, 720)
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.paused = true
	_aggregates()
	_assignments()
	_cross_region()
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("DOG_REGION_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

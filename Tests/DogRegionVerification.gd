extends SceneTree

const ReferenceSimulation = preload("res://Tests/ReferenceSimulation.gd")

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
	var job: DogPerceptionJob = DogPerceptionJob.new()
	job.snapshot = GridAggregateJob.capture_snapshot(PackedInt32Array([2]))
	job.grid = ReferenceSimulation.build_snapshot(job.snapshot)
	job.rows = job.snapshot.index.dog_rows
	job.execute()
	return job

func _empty() -> void:
	engine.reset_simulation()
	engine.paused = true

func _aggregates() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var points := [Vector2(119, 200), Vector2(120, 200), Vector2(239, 210), Vector2(240, 200), Vector2(1290, 660)]
	for point in points:
		var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, point)[0]
		data.motion.velocity[sheep.row] = Vector2(sheep.row, sheep.row * 2)
	entities.spawn(AnimalEntity.Kind.WOLF, 1, points[0])
	var grid := ReferenceSimulation.build_snapshot(GridAggregateJob.capture_snapshot())
	_check(grid.regions.width == 11 and grid.regions.height == 6, "partial edge regions use ceiling dimensions")
	_check(grid.region_at(points[0]) != grid.region_at(points[1]) and grid.region_at(points[1]) == grid.region_at(points[2]), "120 px boundaries group four fine cells")
	var region := grid.region_at(points[1])
	_check(grid.regions.counts[region] == 2, "region counts only sheep")
	_check(grid.regions.centers[region].is_equal_approx(Vector2(179.5, 205)), "region center is sheep-weighted")
	_check(grid.regions.velocities[region].is_equal_approx(Vector2(1.5, 3)), "region velocity averages sheep")
	var count := 0
	for value in grid.regions.counts:
		count += value
	_check(count == points.size(), "every sheep belongs to exactly one region")
	_check(grid.has_region(grid.region_at(points[4])) and not grid.has_region(-1), "edge and invalid region validation")

func _assignments() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
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
	first.apply_result()
	var dog := dogs[0]
	var region := data.dog.region[dog.row]
	_check(region >= 0 and data.dog.protected_sheep[dog.row] == null, "region replaces live sheep anchor")
	data.dog.assignment_remaining[dog.row] = 100.0
	data.motion.position[dog.row] = Vector2(1000, 300)
	var held := _job()
	_check(held.region_ids[0] == region and held.returning_flags[0] == 1, "assignment interval holds region and leash requires return")
	var old := _job()
	data.dog.region[dog.row] = -1
	old.apply_result()
	_check(data.dog.region[dog.row] == -1, "stale result cannot replace newer region state")
	data.dog.region[dog.row] = region
	data.motion.position[sheep.row] = Vector2(850, 500)
	data.motion.position[stray.row] = Vector2(850, 500)
	var moved := _job()
	_check(moved.region_ids[0] != region, "empty region reassigns before interval expires")
	var assigned_region := data.dog.region[dogs[1].row]
	entities.capture(sheep)
	entities.remove_expired()
	_check(data.dog.region[dogs[1].row] == assigned_region, "row compaction moves region with its dog")
	entities.capture(stray)
	entities.remove_expired()
	var empty := _job()
	_check(empty.region_ids == PackedInt32Array([-1, -1]), "no sheep yields no responsibilities")
	empty.apply_result()
	engine.dog_system.advance_time(0.1)
	_check(data.dog.region[dog.row] == -1 and data.memory.target[dog.row] == null and data.dog.collected_sheep[dog.row] == null, "empty world clears dog tasks")

func _cross_region() -> void:
	_empty()
	var entities: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var sheep := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(500, 300))[0]
	var stray := entities.spawn(AnimalEntity.Kind.SHEEP, 1, Vector2(680, 300))[0]
	var dog := entities.spawn(AnimalEntity.Kind.SHEEPDOG, 1, Vector2(600, 300))[0]
	var wolf := entities.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(650, 300))[0]
	data.motion.facing[dog.row] = Vector2.RIGHT
	var job := _job()
	data.dog.region[dog.row] = job.grid.region_at(data.motion.position[sheep.row])
	data.dog.assignment_remaining[dog.row] = 100.0
	job = _job()
	_check(job.region_ids[0] != job.grid.region_at(data.motion.position[stray.row]) and job.strays.has(stray.row), "stray lookup crosses responsibility boundary")
	_check(job.wolf_rows[0] == wolf.row, "visible wolf across region boundary takes priority")
	job.apply_result()
	_check(data.memory.target[dog.row] == wolf and data.dog.collected_sheep[dog.row] == null, "exclusive drive task suppresses collection")

func _run() -> void:
	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
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

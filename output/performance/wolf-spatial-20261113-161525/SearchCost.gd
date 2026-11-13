extends "res://Tests/RunBenchmark.gd"

func _initialize() -> void:
	call_deferred("_measure_search")

func _process(_delta: float) -> bool:
	return false

func _collect_full(wolf: WolfController) -> Array[SheepController]:
	var candidates: Array[SheepController] = []
	for sheep in engine.entity_service.sheep:
		if sheep.alive and wolf.global_position.distance_to(sheep.global_position) < wolf.perception_radius:
			candidates.append(sheep)
	return candidates

func _collect_spatial(wolf: WolfController) -> Array[SheepController]:
	var candidates: Array[SheepController] = []
	var service: EntityService = engine.entity_service
	var nearby := service.get_nearby_indices(wolf.global_position, wolf.perception_radius)
	nearby.sort()
	for index in nearby:
		if service.perception_kinds[index] != AnimalController.Kind.SHEEP:
			continue
		var sheep := service.entities[index] as SheepController
		if sheep.alive and wolf.global_position.distance_to(sheep.global_position) < wolf.perception_radius:
			candidates.append(sheep)
	return candidates

func _measure_search() -> void:
	entities_count = 1000
	scenario = "fixed"
	sampling = "off"
	stats_enabled = false
	label = "wolf-search-cost"
	_start()
	engine.set_physics_process(false)
	engine.entity_service.rebuild_spatial_index()
	var results: Array[Dictionary] = []
	for repeat in range(5):
		var full_usec: int = 0
		var spatial_usec: int = 0
		var weight_usec: int = 0
		var matching := true
		var candidate_count: int = 0
		for wolf in engine.entity_service.wolves:
			var started_at := Time.get_ticks_usec()
			var full := _collect_full(wolf)
			full_usec += Time.get_ticks_usec() - started_at
			started_at = Time.get_ticks_usec()
			var nearby := _collect_spatial(wolf)
			spatial_usec += Time.get_ticks_usec() - started_at
			matching = matching and full == nearby
			candidate_count += full.size()
			started_at = Time.get_ticks_usec()
			for prey in full:
				wolf._prey_weight(prey)
			weight_usec += Time.get_ticks_usec() - started_at
		results.append({"full_collect_usec": full_usec, "spatial_collect_usec": spatial_usec,
			"competition_weight_usec": weight_usec, "matching_candidates": matching,
			"queries": engine.entity_service.wolves.size(), "prey_candidates": candidate_count})
	print("SEARCH_COST ", JSON.stringify(results))
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	quit()

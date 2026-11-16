class_name SheepdogSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func accumulate_sheep_pressure() -> void:
	var grid: GridService = g_gameplayEngine.grid_service
	var settings: SheepConfig = g_gameplayEngine.config.sheep
	var radius: float = settings.herding_distance
	var radius_squared := radius * radius
	for source_row in g_gameplayEngine.entity_service.dog_rows:
		var source := grid.perception_positions[source_row]
		for row in grid.get_nearby_indices(source, radius, AnimalEntity.Kind.SHEEP):
			var offset := grid.perception_positions[row] - source
			var distance_squared := offset.length_squared()
			if distance_squared > radius_squared:
				continue
			data.sheep_dog_pressure[row] += offset.normalized() * (1.0 - sqrt(distance_squared) / radius)

func assign_tasks() -> void:
	var identity_entity_id := data.identity_entity_id
	var motion_position := data.motion_position
	var wolves_claimed: Dictionary = {}
	var sheep_claimed: Dictionary = {}
	var assignments: Dictionary = {}
	for dog_row in g_gameplayEngine.entity_service.dog_rows:
		var dog := data.handles[dog_row]
		if data.identity_alive[dog.row]:
			assignments[dog] = [null, null]
	# 1) Resolve nearest wolf proposals, then farthest stray proposals.
	for kind in range(2):
		var claimed: Dictionary = wolves_claimed if kind == 0 else sheep_claimed
		var waiting: Array[AnimalEntity] = []
		for dog: AnimalEntity in assignments:
			if assignments[dog][0] == null and not data.dog_returning[dog.row]:
				waiting.append(dog)
		while not waiting.is_empty():
			var proposals: Dictionary = {}
			for dog in waiting:
				var candidates: Array = data.dog_wolf_candidates[dog.row] if kind == 0 else data.dog_stray_candidates[dog.row]
				var best: AnimalEntity
				var best_score: float = INF
				for animal in candidates:
					if claimed.has(animal):
						continue
					var score := motion_position[dog.row].distance_squared_to(task_point(dog, animal)) if kind == 0 else -data.dog_protection_center[dog.row].distance_squared_to(motion_position[animal.row])
					if score < best_score or (is_equal_approx(score, best_score) and best != null and identity_entity_id[animal.row] < identity_entity_id[best.row]):
						best = animal
						best_score = score
				if best == null:
					continue
				var previous: AnimalEntity = proposals.get(best)
				var distance := motion_position[dog.row].distance_squared_to(task_point(dog, best))
				var previous_distance := motion_position[previous.row].distance_squared_to(task_point(previous, best)) if previous != null else INF
				if distance < previous_distance or (is_equal_approx(distance, previous_distance) and previous != null and identity_entity_id[dog.row] < identity_entity_id[previous.row]):
					proposals[best] = dog
			if proposals.is_empty():
				break
			for animal: AnimalEntity in proposals:
				var dog: AnimalEntity = proposals[animal]
				assignments[dog][kind] = animal
				claimed[animal] = dog
				waiting.erase(dog)
	for dog: AnimalEntity in assignments:
		apply_assignment(dog, assignments[dog][0], assignments[dog][1])

func perceive(animal: AnimalEntity, delta: float) -> void:
	var dog_assignment_remaining := data.dog_assignment_remaining
	var dog_protected_sheep := data.dog_protected_sheep
	var dog_protection_center := data.dog_protection_center
	var dog_returning := data.dog_returning
	var dog_wolf_candidates := data.dog_wolf_candidates
	var memory_target := data.memory_target
	var motion_position := data.motion_position
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	dog_assignment_remaining[row] -= delta
	if not common.is_live(animal, data.live(dog_protected_sheep[row])) or dog_assignment_remaining[row] <= 0.0:
		_choose_protection_anchor(animal)
		dog_assignment_remaining[row] = settings.reassignment_interval
	_update_protection_center(animal)
	data.dog_patrol_angle[row] += settings.patrol_angular_speed * delta * (1.0 if data.identity_entity_id[row] % 2 == 0 else -1.0)
	data.dog_guard_point[row] = common.clamp_to_arena(animal, dog_protection_center[row] + Vector2.from_angle(data.dog_patrol_angle[row]) * settings.guard_distance)
	common.observe_target(animal, delta)
	if not common.is_live(animal, data.live(dog_protected_sheep[row])):
		memory_target[row] = null
		dog_returning[row] = 0
	elif motion_position[row].distance_to(dog_protection_center[row]) > settings.leash_distance:
		dog_returning[row] = 1
	if dog_returning[row] and motion_position[row].distance_to(data.dog_guard_point[row]) <= 24.0:
		dog_returning[row] = 0
	dog_wolf_candidates[row].clear()
	data.dog_stray_candidates[row].clear()
	var anchor := data.live(dog_protected_sheep[row])
	if dog_returning[row] or not common.is_live(animal, anchor):
		return
	var service: GridService = g_gameplayEngine.grid_service
	var flock: Array[Vector2] = []
	for index in service.get_nearby_indices(motion_position[anchor.row], settings.local_flock_radius, AnimalEntity.Kind.SHEEP):
		if service.perception_kinds[index] == AnimalEntity.Kind.SHEEP and motion_position[anchor.row].distance_to(service.perception_positions[index]) <= settings.local_flock_radius:
			flock.append(service.perception_positions[index])
	for wolf_row in service.get_nearby_indices(motion_position[row], settings.perception_radius, AnimalEntity.Kind.WOLF):
		var wolf := data.handles[wolf_row]
		if not data.identity_alive[wolf.row] or not common.can_see(animal, motion_position[wolf.row]):
			continue
		var threatening: bool = data.wolf_hunting[wolf.row]
		for point in flock:
			if motion_position[wolf.row].distance_to(point) < settings.threat_distance:
				threatening = true
				break
		if threatening:
			dog_wolf_candidates[row].append(wolf)
	if common.is_live(animal, data.live(memory_target[row])) and not data.memory_target_visible[row] and data.memory_unseen_elapsed[row] < settings.memory_duration:
		dog_wolf_candidates[row].append(data.live(memory_target[row]))
	var radius: float = settings.local_flock_radius
	for index in service.get_nearby_indices(motion_position[anchor.row], radius * 2.0, AnimalEntity.Kind.SHEEP):
		if service.perception_kinds[index] != AnimalEntity.Kind.SHEEP:
			continue
		var sheep := data.handles[index] as AnimalEntity
		var point := service.perception_positions[index]
		var distance := dog_protection_center[row].distance_to(point)
		var threshold: float = radius * settings.collect_complete_ratio if sheep == data.live(data.dog_collected_sheep[row]) else radius
		if motion_position[anchor.row].distance_to(point) <= radius * 2.0 and distance > threshold:
			data.dog_stray_candidates[row].append(sheep)

func task_point(animal: AnimalEntity, other: AnimalEntity) -> Vector2:
	var row := animal.row
	if other == data.live(data.memory_target[row]) and not data.memory_target_visible[row]:
		return data.memory_last_seen_position[row]
	return data.motion_position[other.row]

func apply_assignment(animal: AnimalEntity, wolf: AnimalEntity, stray: AnimalEntity) -> void:
	var memory_target := data.memory_target
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var lost_wolf: bool = common.is_live(animal, data.live(memory_target[row])) and wolf == null
	if wolf != data.live(memory_target[row]):
		memory_target[row] = wolf
		common.observe_target(animal, 0.0)
	data.dog_collected_sheep[row] = stray as AnimalEntity
	if lost_wolf:
		data.dog_returning[row] = 1

func _anchor_score(animal: AnimalEntity, sheep: AnimalEntity, anchors: PackedVector2Array) -> float:
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var point := data.motion_position[sheep.row]
	var coverage: int = 0
	for anchor in anchors:
		if anchor.distance_to(point) < settings.local_flock_radius:
			coverage += 1
	return data.motion_position[row].distance_to(point) / settings.local_flock_radius + coverage * settings.coverage_weight

func _choose_protection_anchor(animal: AnimalEntity) -> void:
	var dog_protected_sheep := data.dog_protected_sheep
	var row := animal.row
	var settings: SheepdogConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var anchors := PackedVector2Array()
	for dog_row in g_gameplayEngine.entity_service.dog_rows:
		var dog := data.handles[dog_row]
		var anchor: AnimalEntity = data.live(dog_protected_sheep[dog.row])
		if dog != animal and data.identity_alive[dog.row] and anchor != null:
			anchors.append(data.motion_position[anchor.row])
	var best: AnimalEntity = data.live(dog_protected_sheep[row]) if common.is_live(animal, data.live(dog_protected_sheep[row])) else null
	var current_score: float = _anchor_score(animal, best, anchors) if best != null else INF
	var best_score := current_score
	for sheep_row in g_gameplayEngine.entity_service.sheep_rows:
		var sheep := data.handles[sheep_row]
		if not data.identity_alive[sheep.row]:
			continue
		var score: float = _anchor_score(animal, sheep, anchors)
		if score < best_score:
			best = sheep
			best_score = score

	if not common.is_live(animal, data.live(dog_protected_sheep[row])) or best_score <= current_score * (1.0 - settings.reassignment_improvement):
		dog_protected_sheep[row] = best
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("DogAnchor", started)

func _update_protection_center(animal: AnimalEntity) -> void:
	var motion_position := data.motion_position
	var row := animal.row
	var anchor := data.live(data.dog_protected_sheep[row])
	var settings: SheepdogConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	if not common.is_live(animal, anchor):
		data.dog_protection_center[row] = common.get_wander_point(animal, 85.0)
		return

	data.dog_protection_center[row] = g_gameplayEngine.grid_service.sheep_center(motion_position[anchor.row], settings.local_flock_radius)

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	return "Anchor #%d | Stray #%d | Unseen %.1f s" % [data.identity_entity_id[data.live(data.dog_protected_sheep[row]).row] if common.is_live(animal, data.live(data.dog_protected_sheep[row])) else 0, data.identity_entity_id[data.live(data.dog_collected_sheep[row]).row] if common.is_live(animal, data.live(data.dog_collected_sheep[row])) else 0, data.memory_unseen_elapsed[row]]

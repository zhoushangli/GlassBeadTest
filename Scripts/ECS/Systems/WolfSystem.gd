class_name WolfSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func advance_time(delta: float) -> void:
	var animal_memory := data.memory
	var animal_wolf := data.wolf
	var animal_index := data.index
	var settings: WolfConfig = g_gameplayEngine.config.wolf
	for row in g_gameplayEngine.data_service.animals.index.wolf_rows:
		for index in range(4):
			animal_wolf.strategy_failures[row][index] = maxf(0.0, animal_wolf.strategy_failures[row][index] - settings.strategy_decay * delta)
		animal_wolf.howl_elapsed[row] += delta

		if animal_wolf.resting[row]:
			animal_wolf.rest_elapsed[row] += delta
			animal_wolf.resting[row] = int(animal_wolf.rest_elapsed[row] < settings.rest_duration)
			if not animal_wolf.resting[row]:
				g_gameplayEngine.animal_system.decide(animal_index.handles[row], 0.0)

		if animal_wolf.hunting[row]:
			animal_wolf.hunt_elapsed[row] += delta
			if data.live(animal_memory.target[row]) == null or animal_wolf.hunt_elapsed[row] >= settings.hunt_duration or (not animal_memory.target_visible[row] and animal_memory.unseen_elapsed[row] >= settings.memory_duration):
				end_hunt(animal_index.handles[row], false)
				g_gameplayEngine.animal_system.decide(animal_index.handles[row], 0.0)

func find_dog(animal: AnimalEntity, radius: float) -> AnimalEntity:
	var animal_identity := data.identity
	var animal_motion := data.motion
	var animal_index := data.index
	var index_handles := animal_index.handles
	var identity_alive := animal_identity.alive
	var motion_position := animal_motion.position
	var identity_entity_id := animal_identity.entity_id
	var row := animal.row
	var result: AnimalEntity
	var best := radius
	for dog_row in g_gameplayEngine.data_service.animals.index.dog_rows:
		var dog := index_handles[dog_row]
		if not identity_alive[dog.row]:
			continue

		var distance := motion_position[row].distance_to(motion_position[dog.row])
		if distance < best or (is_equal_approx(distance, best) and result != null and identity_entity_id[dog.row] < identity_entity_id[result.row]):
			result = dog
			best = distance
	return result

func perceive(animal: AnimalEntity, delta: float) -> void:
	var wolf_resting := data.wolf.resting
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.perceive(animal, delta)
	for index in range(4):
		data.wolf.strategy_failures[row][index] = maxf(0.0, data.wolf.strategy_failures[row][index] - settings.strategy_decay * delta)
	data.wolf.howl_elapsed[row] += delta
	if wolf_resting[row]:
		data.wolf.rest_elapsed[row] += delta
		wolf_resting[row] = int(data.wolf.rest_elapsed[row] < settings.rest_duration)
	data.wolf.nearest_threat[row] = find_dog(animal, settings.dog_threat_distance * (2.0 if data.wolf.retreating[row] else 1.0))

	if data.wolf.hunting[row]:
		data.wolf.hunt_elapsed[row] += delta
		common.observe_target(animal, delta)
		if not common.is_live(animal, data.live(data.memory.target[row])) or data.wolf.hunt_elapsed[row] >= settings.hunt_duration or (not data.memory.target_visible[row] and data.memory.unseen_elapsed[row] >= settings.memory_duration):
			end_hunt(animal, false)

	if not data.wolf.hunting[row] and not wolf_resting[row] and not common.is_live(animal, data.live(data.wolf.nearest_threat[row])) and not data.wolf.retreating[row]:
		_choose_prey(animal)

func perceive_batch(delta: float) -> void:
	var started_at := Time.get_ticks_usec()
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var input: WolfPerceptionJob = WolfPerceptionJob.new()
	input.capture_batch(delta)
	input.dogs = g_gameplayEngine.data_service.animals.index.dog_rows

	var jobs: JobService = g_gameplayEngine.job_service
	var prepared_at := Time.get_ticks_usec()
	jobs.run_batches(&"Wolf", g_gameplayEngine.data_service.animals.index.wolf_rows, WolfPerceptionJob, input)
	jobs.record_stage(&"Wolf", started_at, prepared_at)

func _choose_prey(animal: AnimalEntity) -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system
	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var best: AnimalEntity
	var distance: float = INF
	var service: GridService = g_gameplayEngine.grid_service
	for index in service.get_nearby_indices(data.motion.position[row], settings.perception_radius, AnimalEntity.Kind.SHEEP):
		if spatial.current.cells.kinds[index] != AnimalEntity.Kind.SHEEP:
			continue

		var point := spatial.current.cells.positions[index]
		if not common.can_see(animal, point):
			continue

		var candidate := data.index.handles[index] as AnimalEntity
		var next_distance := data.motion.position[row].distance_squared_to(point)
		if next_distance < distance or (is_equal_approx(next_distance, distance) and best != null and data.identity.entity_id[candidate.row] < data.identity.entity_id[best.row]):
			best = candidate
			distance = next_distance
	if best != null:
		begin_hunt(animal, best)
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("WolfTarget", started)

func begin_hunt(animal: AnimalEntity, prey: AnimalEntity) -> void:
	var row := animal.row
	var common: AnimalSystem = g_gameplayEngine.animal_system
	data.memory.target[row] = prey
	data.wolf.hunting[row] = 1
	data.wolf.hunt_elapsed[row] = 0.0
	data.wolf.charging[row] = 0
	data.wolf.howled[row] = 0

	# 1) Sample a strategy with lower weight for recent failures.
	var total: float = 0.0
	for index in range(4):
		total += 1.0 / (1.0 + data.wolf.strategy_failures[row][index])
	var choice: float = g_gameplayEngine.rng.randf() * total
	for index in range(4):
		choice -= 1.0 / (1.0 + data.wolf.strategy_failures[row][index])
		if choice <= 0.0 or index == 4 - 1:
			data.wolf.strategy[row] = index
			break

	common.observe_target(animal, 0.0)

func end_hunt(animal: AnimalEntity, success: bool) -> void:
	var row := animal.row
	if not data.wolf.hunting[row]:
		return

	data.wolf.strategy_failures[row][data.wolf.strategy[row]] = maxf(0.0, data.wolf.strategy_failures[row][data.wolf.strategy[row]] + (-1.5 if success else 1.0))
	data.wolf.hunting[row] = 0
	data.wolf.charging[row] = 0
	data.memory.target[row] = null
	data.memory.target_visible[row] = 0
	data.wolf.resting[row] = 1
	data.wolf.rest_elapsed[row] = 0.0

func can_charge(animal: AnimalEntity) -> bool:
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	return data.wolf.hunting[row] and data.memory.target_visible[row] and (data.wolf.charging[row] or data.motion.position[row].distance_to(data.memory.last_seen_position[row]) <= settings.capture_distance * settings.charge_distance_scale)

func resolve_interactions(animal: AnimalEntity, _delta: float) -> void:
	var animal_identity := data.identity
	var animal_motion := data.motion
	var animal_memory := data.memory
	var animal_brain := data.brain
	var animal_index := data.index
	var animal_wolf := data.wolf
	var memory_target := animal_memory.target
	var motion_position := animal_motion.position
	var row := animal.row
	var settings: WolfConfig = data.settings[row]
	var common: AnimalSystem = g_gameplayEngine.animal_system

	# 1) Apply a pending howl at the post-movement positions.
	if animal_wolf.howl_pending[row]:
		animal_wolf.howl_pending[row] = 0
		g_gameplayEngine.debug_service.record_howl(animal)
		for sheep_row in g_gameplayEngine.data_service.animals.index.sheep_rows:
			var sheep := animal_index.handles[sheep_row]
			if animal_identity.alive[sheep.row] and motion_position[row].distance_to(motion_position[sheep.row]) <= settings.howl_radius:
				g_gameplayEngine.sheep_system.receive_howl(sheep, motion_position[row])

	if not animal_wolf.hunting[row] or animal_brain.current_behavior[row] != AnimalEntity.Behavior.CHASE:
		return
	if not common.is_live(animal, data.live(memory_target[row])):
		end_hunt(animal, false)
		return

	# 2) Let a nearby dog interrupt the hunt before checking capture distance.
	animal_wolf.nearest_threat[row] = find_dog(animal, settings.dog_threat_distance)
	if common.is_live(animal, data.live(animal_wolf.nearest_threat[row])):
		end_hunt(animal, false)
		animal_wolf.retreating[row] = 1
		return

	if common.can_see(animal, motion_position[data.live(memory_target[row]).row]) and motion_position[row].distance_to(motion_position[data.live(memory_target[row]).row]) <= settings.capture_distance:
		if g_gameplayEngine.entity_service.capture(data.live(memory_target[row])):
			end_hunt(animal, true)

func prepare_motion_goals() -> void:
	var animal_motion := data.motion
	var animal_memory := data.memory
	var animal_brain := data.brain
	var animal_wolf := data.wolf
	var animal_index := data.index
	var settings: WolfConfig = g_gameplayEngine.config.wolf
	var common: AnimalSystem = g_gameplayEngine.animal_system
	for row in g_gameplayEngine.data_service.animals.index.wolf_rows:
		if animal_motion.intent[row] != AnimalData.MotionIntent.POINT:
			continue

		if animal_brain.current_behavior[row] in [AnimalEntity.Behavior.CHASE, AnimalEntity.Behavior.STALK] and data.live(animal_memory.target[row]) != null:
			common.observe_target(animal_index.handles[row], 0.0)

		match animal_brain.current_behavior[row]:
			AnimalEntity.Behavior.CHASE:
				animal_motion.movement_goal[row] = animal_memory.last_seen_position[row]
			AnimalEntity.Behavior.STALK:
				var point := animal_memory.last_seen_position[row]
				var direction := animal_memory.last_seen_velocity[row].normalized()
				if direction.is_zero_approx():
					direction = Vector2.RIGHT
				match animal_wolf.strategy[row]:
					AnimalEntity.Strategy.SIDE:
						point += direction.orthogonal() * settings.strategy_offset
					AnimalEntity.Strategy.REAR:
						point -= direction * settings.strategy_offset
				animal_motion.movement_goal[row] = common.clamp_to_arena(animal_index.handles[row], point)
			AnimalEntity.Behavior.RETREAT:
				var threat := data.live(animal_wolf.nearest_threat[row])
				if threat != null:
					var away := (animal_motion.position[row] - animal_motion.position[threat.row]).normalized()
					if away.is_zero_approx():
						away = animal_motion.facing[row]
					animal_motion.movement_goal[row] = animal_motion.position[row] + away * 100.0

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	return "%s | Hunt %.1f s | Unseen %.1f s | Failures %s" % [AnimalEntity.STRATEGY_NAMES[data.wolf.strategy[row]], data.wolf.hunt_elapsed[row], data.memory.unseen_elapsed[row], data.wolf.strategy_failures[row]]

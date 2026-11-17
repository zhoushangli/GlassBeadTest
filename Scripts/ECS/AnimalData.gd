class_name AnimalData
extends RefCounted

enum MotionIntent { STOP, POINT, SHEEP }

var identity_entity_id: PackedInt64Array = []
var identity_kind: PackedInt64Array = []
var identity_alive: PackedByteArray = []
var identity_death_remaining: PackedFloat64Array = []

var motion_intent := PackedByteArray()
var motion_position: PackedVector2Array = []
var motion_facing: PackedVector2Array = []
var motion_velocity: PackedVector2Array = []
var motion_desired_velocity: PackedVector2Array = []
var motion_movement_goal: PackedVector2Array = []
var motion_separation: PackedVector2Array = []
var motion_speed_limit: PackedFloat64Array = []
var motion_wander_point: PackedVector2Array = []
var motion_wander_remaining: PackedFloat64Array = []

var memory_last_seen_position: PackedVector2Array = []
var memory_last_seen_velocity: PackedVector2Array = []
var memory_unseen_elapsed: PackedFloat64Array = []
var memory_target_visible: PackedByteArray = []
var memory_nearby: Array[PackedInt32Array] = []
var memory_perception_remaining: PackedFloat64Array = []
var memory_perception_ready: PackedByteArray = []
var memory_vision_radius_squared: PackedFloat64Array = []
var memory_vision_cos: PackedFloat64Array = []
var memory_target: Array[AnimalEntity] = []

var brain_current_behavior: PackedInt64Array = []
var brain_instance: Array[BTInstance] = []

var sheep_local_flock_center: PackedVector2Array = []
var sheep_neighbor_count: PackedInt64Array = []
var sheep_alignment: PackedVector2Array = []
var sheep_threat_direction: PackedVector2Array = []
var sheep_dog_pressure: PackedVector2Array = []
var sheep_threat_strength: PackedFloat64Array = []
var sheep_panic_strength: PackedFloat64Array = []
var sheep_panic_source: PackedVector2Array = []
var sheep_panic_revision := PackedInt64Array()

var wolf_hunting: PackedByteArray = []
var wolf_hunt_elapsed: PackedFloat64Array = []
var wolf_charging: PackedByteArray = []
var wolf_strategy: PackedInt64Array = []
var wolf_strategy_failures: PackedVector4Array = []
var wolf_retreating: PackedByteArray = []
var wolf_resting: PackedByteArray = []
var wolf_rest_elapsed: PackedFloat64Array = []
var wolf_howl_elapsed: PackedFloat64Array = []
var wolf_howled: PackedByteArray = []
var wolf_howl_pending: PackedByteArray = []
var wolf_nearest_threat: Array[AnimalEntity] = []

var dog_region := PackedInt32Array()
var dog_protection_center: PackedVector2Array = []
var dog_guard_point: PackedVector2Array = []
var dog_wolf_candidates: Array[Array] = []
var dog_stray_candidates: Array[Array] = []
var dog_assignment_remaining: PackedFloat64Array = []
var dog_returning: PackedByteArray = []
var dog_patrol_angle: PackedFloat64Array = []
var dog_protected_sheep: Array[AnimalEntity] = []
var dog_collected_sheep: Array[AnimalEntity] = []

var settings: Array[Resource] = []

# Preserve life identity across row swaps; slot reuse receives a new serial.
# e.g. an old handle cannot resolve to the next animal spawned in its slot.
var identity_animal_id := PackedInt64Array()
var row_to_slot := PackedInt32Array()
var slot_to_row := PackedInt32Array()
var handles: Array[AnimalEntity] = []
var structure_version: int = 0

# Partition storage into active, retained corpse and reusable pool ranges.
# e.g. active_count = 3 and retained_count = 5 keeps corpses in rows 3 and 4.
var active_count: int = 0
var retained_count: int = 0

func append_slot() -> int:
	var row := row_to_slot.size()
	row_to_slot.append(row)
	slot_to_row.append(row)
	handles.append(null)
	identity_entity_id.append(0)
	identity_kind.append(AnimalEntity.Kind.SHEEP)
	identity_alive.append(true)
	identity_death_remaining.append(0.0)

	motion_intent.append(MotionIntent.STOP)
	motion_position.append(Vector2.ZERO)
	motion_facing.append(Vector2.RIGHT)
	motion_velocity.append(Vector2.ZERO)
	motion_desired_velocity.append(Vector2.ZERO)
	motion_movement_goal.append(Vector2.ZERO)
	motion_separation.append(Vector2.ZERO)
	motion_speed_limit.append(0.0)
	motion_wander_point.append(Vector2.ZERO)
	motion_wander_remaining.append(0.0)

	memory_last_seen_position.append(Vector2.ZERO)
	memory_last_seen_velocity.append(Vector2.ZERO)
	memory_unseen_elapsed.append(0.0)
	memory_target_visible.append(false)
	memory_nearby.append(PackedInt32Array())
	memory_perception_remaining.append(0.0)
	memory_perception_ready.append(false)
	memory_vision_radius_squared.append(0.0)
	memory_vision_cos.append(-1.0)
	memory_target.append(null)

	brain_current_behavior.append(AnimalEntity.Behavior.FLOCK)
	brain_instance.append(null)

	sheep_local_flock_center.append(Vector2.ZERO)
	sheep_neighbor_count.append(0)
	sheep_alignment.append(Vector2.ZERO)
	sheep_threat_direction.append(Vector2.ZERO)
	sheep_dog_pressure.append(Vector2.ZERO)
	sheep_threat_strength.append(0.0)
	sheep_panic_strength.append(0.0)
	sheep_panic_source.append(Vector2.ZERO)
	sheep_panic_revision.append(0)

	wolf_hunting.append(false)
	wolf_hunt_elapsed.append(0.0)
	wolf_charging.append(false)
	wolf_strategy.append(AnimalEntity.Strategy.FRONTAL)
	wolf_strategy_failures.append(Vector4.ZERO)
	wolf_retreating.append(false)
	wolf_resting.append(false)
	wolf_rest_elapsed.append(0.0)
	wolf_howl_elapsed.append(1000.0)
	wolf_howled.append(false)
	wolf_howl_pending.append(false)
	wolf_nearest_threat.append(null)

	dog_region.append(-1)
	dog_protection_center.append(Vector2.ZERO)
	dog_guard_point.append(Vector2.ZERO)
	dog_wolf_candidates.append([])
	dog_stray_candidates.append([])
	dog_assignment_remaining.append(0.0)
	dog_returning.append(false)
	dog_patrol_angle.append(0.0)
	dog_protected_sheep.append(null)
	dog_collected_sheep.append(null)

	settings.append(null)
	identity_animal_id.append(0)
	return row

func reset_row(row: int) -> void:
	identity_entity_id[row] = 0
	identity_kind[row] = AnimalEntity.Kind.SHEEP
	identity_alive[row] = true
	identity_death_remaining[row] = 0.0

	motion_intent[row] = MotionIntent.STOP
	motion_position[row] = Vector2.ZERO
	motion_facing[row] = Vector2.RIGHT
	motion_velocity[row] = Vector2.ZERO
	motion_desired_velocity[row] = Vector2.ZERO
	motion_movement_goal[row] = Vector2.ZERO
	motion_separation[row] = Vector2.ZERO
	motion_speed_limit[row] = 0.0
	motion_wander_point[row] = Vector2.ZERO
	motion_wander_remaining[row] = 0.0

	memory_last_seen_position[row] = Vector2.ZERO
	memory_last_seen_velocity[row] = Vector2.ZERO
	memory_unseen_elapsed[row] = 0.0
	memory_target_visible[row] = false
	memory_nearby[row] = PackedInt32Array()
	memory_perception_remaining[row] = 0.0
	memory_perception_ready[row] = false
	memory_vision_radius_squared[row] = 0.0
	memory_vision_cos[row] = -1.0
	memory_target[row] = null

	brain_current_behavior[row] = AnimalEntity.Behavior.FLOCK

	sheep_local_flock_center[row] = Vector2.ZERO
	sheep_neighbor_count[row] = 0
	sheep_alignment[row] = Vector2.ZERO
	sheep_threat_direction[row] = Vector2.ZERO
	sheep_dog_pressure[row] = Vector2.ZERO
	sheep_threat_strength[row] = 0.0
	sheep_panic_strength[row] = 0.0
	sheep_panic_source[row] = Vector2.ZERO
	sheep_panic_revision[row] = 0

	wolf_hunting[row] = false
	wolf_hunt_elapsed[row] = 0.0
	wolf_charging[row] = false
	wolf_strategy[row] = AnimalEntity.Strategy.FRONTAL
	wolf_strategy_failures[row] = Vector4.ZERO
	wolf_retreating[row] = false
	wolf_resting[row] = false
	wolf_rest_elapsed[row] = 0.0
	wolf_howl_elapsed[row] = 1000.0
	wolf_howled[row] = false
	wolf_howl_pending[row] = false
	wolf_nearest_threat[row] = null

	dog_region[row] = -1
	dog_protection_center[row] = Vector2.ZERO
	dog_guard_point[row] = Vector2.ZERO
	dog_wolf_candidates[row] = []
	dog_stray_candidates[row] = []
	dog_assignment_remaining[row] = 0.0
	dog_returning[row] = false
	dog_patrol_angle[row] = 0.0
	dog_protected_sheep[row] = null
	dog_collected_sheep[row] = null

	settings[row] = null

func swap_rows(first: int, second: int) -> void:
	if first == second:
		return

	# 1) Swap every column so each row continues to describe one complete animal.
	structure_version += 1
	var intent := motion_intent[first]
	motion_intent[first] = motion_intent[second]
	motion_intent[second] = intent
	var value_0 = identity_entity_id[first]
	identity_entity_id[first] = identity_entity_id[second]
	identity_entity_id[second] = value_0
	var value_1 = identity_kind[first]
	identity_kind[first] = identity_kind[second]
	identity_kind[second] = value_1
	var value_2 = identity_alive[first]
	identity_alive[first] = identity_alive[second]
	identity_alive[second] = value_2
	var value_3 = identity_death_remaining[first]
	identity_death_remaining[first] = identity_death_remaining[second]
	identity_death_remaining[second] = value_3

	var value_4 = motion_position[first]
	motion_position[first] = motion_position[second]
	motion_position[second] = value_4
	var value_5 = motion_facing[first]
	motion_facing[first] = motion_facing[second]
	motion_facing[second] = value_5
	var value_6 = motion_velocity[first]
	motion_velocity[first] = motion_velocity[second]
	motion_velocity[second] = value_6
	var value_7 = motion_desired_velocity[first]
	motion_desired_velocity[first] = motion_desired_velocity[second]
	motion_desired_velocity[second] = value_7
	var value_8 = motion_movement_goal[first]
	motion_movement_goal[first] = motion_movement_goal[second]
	motion_movement_goal[second] = value_8
	var value_9 = motion_separation[first]
	motion_separation[first] = motion_separation[second]
	motion_separation[second] = value_9
	var value_10 = motion_speed_limit[first]
	motion_speed_limit[first] = motion_speed_limit[second]
	motion_speed_limit[second] = value_10
	var value_11 = motion_wander_point[first]
	motion_wander_point[first] = motion_wander_point[second]
	motion_wander_point[second] = value_11
	var value_12 = motion_wander_remaining[first]
	motion_wander_remaining[first] = motion_wander_remaining[second]
	motion_wander_remaining[second] = value_12

	var value_13 = memory_last_seen_position[first]
	memory_last_seen_position[first] = memory_last_seen_position[second]
	memory_last_seen_position[second] = value_13
	var value_14 = memory_last_seen_velocity[first]
	memory_last_seen_velocity[first] = memory_last_seen_velocity[second]
	memory_last_seen_velocity[second] = value_14
	var value_15 = memory_unseen_elapsed[first]
	memory_unseen_elapsed[first] = memory_unseen_elapsed[second]
	memory_unseen_elapsed[second] = value_15
	var value_16 = memory_target_visible[first]
	memory_target_visible[first] = memory_target_visible[second]
	memory_target_visible[second] = value_16
	var value_18 = memory_nearby[first]
	memory_nearby[first] = memory_nearby[second]
	memory_nearby[second] = value_18
	var value_19 = memory_perception_remaining[first]
	memory_perception_remaining[first] = memory_perception_remaining[second]
	memory_perception_remaining[second] = value_19
	var value_20 = memory_perception_ready[first]
	memory_perception_ready[first] = memory_perception_ready[second]
	memory_perception_ready[second] = value_20
	var value_21 = memory_vision_radius_squared[first]
	memory_vision_radius_squared[first] = memory_vision_radius_squared[second]
	memory_vision_radius_squared[second] = value_21
	var value_22 = memory_vision_cos[first]
	memory_vision_cos[first] = memory_vision_cos[second]
	memory_vision_cos[second] = value_22
	var value_23 = memory_target[first]
	memory_target[first] = memory_target[second]
	memory_target[second] = value_23

	var value_24 = brain_current_behavior[first]
	brain_current_behavior[first] = brain_current_behavior[second]
	brain_current_behavior[second] = value_24
	var value_26 = brain_instance[first]
	brain_instance[first] = brain_instance[second]
	brain_instance[second] = value_26

	var value_27 = sheep_local_flock_center[first]
	sheep_local_flock_center[first] = sheep_local_flock_center[second]
	sheep_local_flock_center[second] = value_27
	var value_28 = sheep_neighbor_count[first]
	sheep_neighbor_count[first] = sheep_neighbor_count[second]
	sheep_neighbor_count[second] = value_28
	var value_29 = sheep_alignment[first]
	sheep_alignment[first] = sheep_alignment[second]
	sheep_alignment[second] = value_29
	var value_30 = sheep_threat_direction[first]
	sheep_threat_direction[first] = sheep_threat_direction[second]
	sheep_threat_direction[second] = value_30
	var value_31 = sheep_dog_pressure[first]
	sheep_dog_pressure[first] = sheep_dog_pressure[second]
	sheep_dog_pressure[second] = value_31
	var threat_strength := sheep_threat_strength[first]
	sheep_threat_strength[first] = sheep_threat_strength[second]
	sheep_threat_strength[second] = threat_strength
	var value_33 = sheep_panic_strength[first]
	sheep_panic_strength[first] = sheep_panic_strength[second]
	sheep_panic_strength[second] = value_33
	var value_36 = sheep_panic_source[first]
	sheep_panic_source[first] = sheep_panic_source[second]
	sheep_panic_source[second] = value_36
	var panic_revision := sheep_panic_revision[first]
	sheep_panic_revision[first] = sheep_panic_revision[second]
	sheep_panic_revision[second] = panic_revision

	var value_38 = wolf_hunting[first]
	wolf_hunting[first] = wolf_hunting[second]
	wolf_hunting[second] = value_38
	var value_39 = wolf_hunt_elapsed[first]
	wolf_hunt_elapsed[first] = wolf_hunt_elapsed[second]
	wolf_hunt_elapsed[second] = value_39
	var value_40 = wolf_charging[first]
	wolf_charging[first] = wolf_charging[second]
	wolf_charging[second] = value_40
	var value_41 = wolf_strategy[first]
	wolf_strategy[first] = wolf_strategy[second]
	wolf_strategy[second] = value_41
	var value_42 = wolf_strategy_failures[first]
	wolf_strategy_failures[first] = wolf_strategy_failures[second]
	wolf_strategy_failures[second] = value_42
	var value_43 = wolf_retreating[first]
	wolf_retreating[first] = wolf_retreating[second]
	wolf_retreating[second] = value_43
	var value_44 = wolf_resting[first]
	wolf_resting[first] = wolf_resting[second]
	wolf_resting[second] = value_44
	var value_45 = wolf_rest_elapsed[first]
	wolf_rest_elapsed[first] = wolf_rest_elapsed[second]
	wolf_rest_elapsed[second] = value_45
	var value_46 = wolf_howl_elapsed[first]
	wolf_howl_elapsed[first] = wolf_howl_elapsed[second]
	wolf_howl_elapsed[second] = value_46
	var value_47 = wolf_howled[first]
	wolf_howled[first] = wolf_howled[second]
	wolf_howled[second] = value_47
	var value_48 = wolf_howl_pending[first]
	wolf_howl_pending[first] = wolf_howl_pending[second]
	wolf_howl_pending[second] = value_48
	var value_49 = wolf_nearest_threat[first]
	wolf_nearest_threat[first] = wolf_nearest_threat[second]
	wolf_nearest_threat[second] = value_49

	var region := dog_region[first]
	dog_region[first] = dog_region[second]
	dog_region[second] = region
	var value_50 = dog_protection_center[first]
	dog_protection_center[first] = dog_protection_center[second]
	dog_protection_center[second] = value_50
	var value_51 = dog_guard_point[first]
	dog_guard_point[first] = dog_guard_point[second]
	dog_guard_point[second] = value_51
	var value_52 = dog_wolf_candidates[first]
	dog_wolf_candidates[first] = dog_wolf_candidates[second]
	dog_wolf_candidates[second] = value_52
	var value_53 = dog_stray_candidates[first]
	dog_stray_candidates[first] = dog_stray_candidates[second]
	dog_stray_candidates[second] = value_53
	var value_54 = dog_assignment_remaining[first]
	dog_assignment_remaining[first] = dog_assignment_remaining[second]
	dog_assignment_remaining[second] = value_54
	var value_55 = dog_returning[first]
	dog_returning[first] = dog_returning[second]
	dog_returning[second] = value_55
	var value_56 = dog_patrol_angle[first]
	dog_patrol_angle[first] = dog_patrol_angle[second]
	dog_patrol_angle[second] = value_56
	var value_57 = dog_protected_sheep[first]
	dog_protected_sheep[first] = dog_protected_sheep[second]
	dog_protected_sheep[second] = value_57
	var value_58 = dog_collected_sheep[first]
	dog_collected_sheep[first] = dog_collected_sheep[second]
	dog_collected_sheep[second] = value_58

	# 2) Move identity and handle ownership with the data, then repair cached rows.
	var value_59 = settings[first]
	settings[first] = settings[second]
	settings[second] = value_59
	var value_60 = identity_animal_id[first]
	identity_animal_id[first] = identity_animal_id[second]
	identity_animal_id[second] = value_60
	var handle := handles[first]
	handles[first] = handles[second]
	handles[second] = handle
	if handles[first] != null:
		handles[first].row = first
	if handles[second] != null:
		handles[second].row = second

	# 3) Repair both directions of the stable-slot mapping.
	var slot := row_to_slot[first]
	row_to_slot[first] = row_to_slot[second]
	row_to_slot[second] = slot
	slot_to_row[row_to_slot[first]] = first
	slot_to_row[row_to_slot[second]] = second

# Resolve a full life identity, validating cached rows before using the slot map.
# e.g. row_of_id(old_id) returns -1 after its slot is reused with a new serial.
func row_of_id(id: int, cached_row: int = -1) -> int:
	if cached_row >= 0 and cached_row < identity_animal_id.size() and identity_animal_id[cached_row] == id and id != AnimalID.INVALID:
		return cached_row
	if not AnimalID.is_valid(id):
		return -1

	var slot := AnimalID.get_slot(id)
	if slot >= slot_to_row.size():
		return -1

	var row := slot_to_row[slot]
	return row if row >= 0 and row < identity_animal_id.size() and identity_animal_id[row] == id else -1

func row_of(handle: AnimalEntity) -> int:
	return row_of_id(handle.id, handle.row) if handle != null else -1

func live(handle: AnimalEntity) -> AnimalEntity:
	if handle == null:
		return null

	var row := handle.row
	if row >= 0 and row < active_count and identity_animal_id[row] == handle.id:
		return handles[row] if identity_alive[row] else null

	row = row_of_id(handle.id)
	return handles[row] if row >= 0 and row < active_count and identity_alive[row] else null

func clear() -> void:
	structure_version += 1
	for handle in handles:
		if handle != null:
			handle.row = -1

	identity_entity_id.clear()
	identity_kind.clear()
	identity_alive.clear()
	identity_death_remaining.clear()

	motion_intent.clear()
	motion_position.clear()
	motion_facing.clear()
	motion_velocity.clear()
	motion_desired_velocity.clear()
	motion_movement_goal.clear()
	motion_separation.clear()
	motion_speed_limit.clear()
	motion_wander_point.clear()
	motion_wander_remaining.clear()

	memory_last_seen_position.clear()
	memory_last_seen_velocity.clear()
	memory_unseen_elapsed.clear()
	memory_target_visible.clear()
	memory_nearby.clear()
	memory_perception_remaining.clear()
	memory_perception_ready.clear()
	memory_vision_radius_squared.clear()
	memory_vision_cos.clear()
	memory_target.clear()

	brain_current_behavior.clear()
	brain_instance.clear()

	sheep_local_flock_center.clear()
	sheep_neighbor_count.clear()
	sheep_alignment.clear()
	sheep_threat_direction.clear()
	sheep_dog_pressure.clear()
	sheep_threat_strength.clear()
	sheep_panic_strength.clear()
	sheep_panic_source.clear()
	sheep_panic_revision.clear()

	wolf_hunting.clear()
	wolf_hunt_elapsed.clear()
	wolf_charging.clear()
	wolf_strategy.clear()
	wolf_strategy_failures.clear()
	wolf_retreating.clear()
	wolf_resting.clear()
	wolf_rest_elapsed.clear()
	wolf_howl_elapsed.clear()
	wolf_howled.clear()
	wolf_howl_pending.clear()
	wolf_nearest_threat.clear()

	dog_region.clear()
	dog_protection_center.clear()
	dog_guard_point.clear()
	dog_wolf_candidates.clear()
	dog_stray_candidates.clear()
	dog_assignment_remaining.clear()
	dog_returning.clear()
	dog_patrol_angle.clear()
	dog_protected_sheep.clear()
	dog_collected_sheep.clear()

	settings.clear()
	handles.clear()
	identity_animal_id.clear()
	row_to_slot.clear()
	slot_to_row.clear()
	active_count = 0
	retained_count = 0

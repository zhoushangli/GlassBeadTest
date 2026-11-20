class_name AnimalData
extends RefCounted

enum MotionIntent { STOP, POINT, SHEEP }

class Identity extends RefCounted:
	var entity_id: PackedInt64Array = []
	var kind: PackedInt64Array = []
	var alive: PackedByteArray = []
	var death_remaining: PackedFloat64Array = []
	# Preserve life identity across row swaps; slot reuse receives a new serial.
	# e.g. an old handle cannot resolve to the next animal spawned in its slot.
	var animal_id := PackedInt64Array()

class Motion extends RefCounted:
	var intent := PackedByteArray()
	var position: PackedVector2Array = []
	var facing: PackedVector2Array = []
	var velocity: PackedVector2Array = []
	var desired_velocity: PackedVector2Array = []
	var movement_goal: PackedVector2Array = []
	var separation: PackedVector2Array = []
	var speed_limit: PackedFloat64Array = []
	var wander_point: PackedVector2Array = []
	var wander_remaining: PackedFloat64Array = []

class Memory extends RefCounted:
	var last_seen_position: PackedVector2Array = []
	var last_seen_velocity: PackedVector2Array = []
	var unseen_elapsed: PackedFloat64Array = []
	var target_visible: PackedByteArray = []
	var nearby: Array[PackedInt32Array] = []
	var perception_remaining: PackedFloat64Array = []
	var perception_ready: PackedByteArray = []
	var vision_radius_squared: PackedFloat64Array = []
	var vision_cos: PackedFloat64Array = []
	var target: Array[AnimalEntity] = []

class Brain extends RefCounted:
	var current_behavior: PackedInt64Array = []
	var instance: Array[BTInstance] = []

class Sheep extends RefCounted:
	var local_flock_center: PackedVector2Array = []
	var neighbor_count: PackedInt64Array = []
	var alignment: PackedVector2Array = []
	var threat_direction: PackedVector2Array = []
	var dog_pressure: PackedVector2Array = []
	var threat_strength: PackedFloat64Array = []
	var panic_strength: PackedFloat64Array = []
	var panic_source: PackedVector2Array = []
	var panic_revision := PackedInt64Array()

class Wolf extends RefCounted:
	var hunting: PackedByteArray = []
	var hunt_elapsed: PackedFloat64Array = []
	var charging: PackedByteArray = []
	var strategy: PackedInt64Array = []
	var strategy_failures: PackedVector4Array = []
	var retreating: PackedByteArray = []
	var resting: PackedByteArray = []
	var rest_elapsed: PackedFloat64Array = []
	var howl_elapsed: PackedFloat64Array = []
	var howled: PackedByteArray = []
	var howl_pending: PackedByteArray = []
	var nearest_threat: Array[AnimalEntity] = []

class Dog extends RefCounted:
	var region := PackedInt32Array()
	var protection_center: PackedVector2Array = []
	var guard_point: PackedVector2Array = []
	var wolf_candidates: Array[Array] = []
	var stray_candidates: Array[Array] = []
	var assignment_remaining: PackedFloat64Array = []
	var returning: PackedByteArray = []
	var patrol_angle: PackedFloat64Array = []
	var protected_sheep: Array[AnimalEntity] = []
	var collected_sheep: Array[AnimalEntity] = []

class Index extends RefCounted:
	var row_to_slot := PackedInt32Array()
	var slot_to_row := PackedInt32Array()
	var handles: Array[AnimalEntity] = []
	var structure_version: int = 0
	# Partition storage into active, retained corpse and reusable pool ranges.
	# e.g. active_count = 3 and retained_count = 5 keeps corpses in rows 3 and 4.
	var active_count: int = 0
	var retained_count: int = 0
	var entities: Array[AnimalEntity] = []
	var next_id: int = 1
	var next_uid: int = 0
	var capture_count: int = 0
	var sheep_rows := PackedInt32Array()
	var wolf_rows := PackedInt32Array()
	var dog_rows := PackedInt32Array()

var identity: Identity = Identity.new()
var motion: Motion = Motion.new()
var memory: Memory = Memory.new()
var brain: Brain = Brain.new()
var sheep: Sheep = Sheep.new()
var wolf: Wolf = Wolf.new()
var dog: Dog = Dog.new()
var index: Index = Index.new()
var settings: Array[Resource] = []

func append_slot() -> int:
	var row := index.row_to_slot.size()
	index.row_to_slot.append(row)
	index.slot_to_row.append(row)
	index.handles.append(null)
	identity.entity_id.append(0)
	identity.kind.append(AnimalEntity.Kind.SHEEP)
	identity.alive.append(true)
	identity.death_remaining.append(0.0)

	motion.intent.append(MotionIntent.STOP)
	motion.position.append(Vector2.ZERO)
	motion.facing.append(Vector2.RIGHT)
	motion.velocity.append(Vector2.ZERO)
	motion.desired_velocity.append(Vector2.ZERO)
	motion.movement_goal.append(Vector2.ZERO)
	motion.separation.append(Vector2.ZERO)
	motion.speed_limit.append(0.0)
	motion.wander_point.append(Vector2.ZERO)
	motion.wander_remaining.append(0.0)

	memory.last_seen_position.append(Vector2.ZERO)
	memory.last_seen_velocity.append(Vector2.ZERO)
	memory.unseen_elapsed.append(0.0)
	memory.target_visible.append(false)
	memory.nearby.append(PackedInt32Array())
	memory.perception_remaining.append(0.0)
	memory.perception_ready.append(false)
	memory.vision_radius_squared.append(0.0)
	memory.vision_cos.append(-1.0)
	memory.target.append(null)

	brain.current_behavior.append(AnimalEntity.Behavior.FLOCK)
	brain.instance.append(null)

	sheep.local_flock_center.append(Vector2.ZERO)
	sheep.neighbor_count.append(0)
	sheep.alignment.append(Vector2.ZERO)
	sheep.threat_direction.append(Vector2.ZERO)
	sheep.dog_pressure.append(Vector2.ZERO)
	sheep.threat_strength.append(0.0)
	sheep.panic_strength.append(0.0)
	sheep.panic_source.append(Vector2.ZERO)
	sheep.panic_revision.append(0)

	wolf.hunting.append(false)
	wolf.hunt_elapsed.append(0.0)
	wolf.charging.append(false)
	wolf.strategy.append(AnimalEntity.Strategy.FRONTAL)
	wolf.strategy_failures.append(Vector4.ZERO)
	wolf.retreating.append(false)
	wolf.resting.append(false)
	wolf.rest_elapsed.append(0.0)
	wolf.howl_elapsed.append(1000.0)
	wolf.howled.append(false)
	wolf.howl_pending.append(false)
	wolf.nearest_threat.append(null)

	dog.region.append(-1)
	dog.protection_center.append(Vector2.ZERO)
	dog.guard_point.append(Vector2.ZERO)
	dog.wolf_candidates.append([])
	dog.stray_candidates.append([])
	dog.assignment_remaining.append(0.0)
	dog.returning.append(false)
	dog.patrol_angle.append(0.0)
	dog.protected_sheep.append(null)
	dog.collected_sheep.append(null)

	settings.append(null)
	identity.animal_id.append(0)
	return row

func reset_row(row: int) -> void:
	identity.entity_id[row] = 0
	identity.kind[row] = AnimalEntity.Kind.SHEEP
	identity.alive[row] = true
	identity.death_remaining[row] = 0.0

	motion.intent[row] = MotionIntent.STOP
	motion.position[row] = Vector2.ZERO
	motion.facing[row] = Vector2.RIGHT
	motion.velocity[row] = Vector2.ZERO
	motion.desired_velocity[row] = Vector2.ZERO
	motion.movement_goal[row] = Vector2.ZERO
	motion.separation[row] = Vector2.ZERO
	motion.speed_limit[row] = 0.0
	motion.wander_point[row] = Vector2.ZERO
	motion.wander_remaining[row] = 0.0

	memory.last_seen_position[row] = Vector2.ZERO
	memory.last_seen_velocity[row] = Vector2.ZERO
	memory.unseen_elapsed[row] = 0.0
	memory.target_visible[row] = false
	memory.nearby[row] = PackedInt32Array()
	memory.perception_remaining[row] = 0.0
	memory.perception_ready[row] = false
	memory.vision_radius_squared[row] = 0.0
	memory.vision_cos[row] = -1.0
	memory.target[row] = null

	brain.current_behavior[row] = AnimalEntity.Behavior.FLOCK

	sheep.local_flock_center[row] = Vector2.ZERO
	sheep.neighbor_count[row] = 0
	sheep.alignment[row] = Vector2.ZERO
	sheep.threat_direction[row] = Vector2.ZERO
	sheep.dog_pressure[row] = Vector2.ZERO
	sheep.threat_strength[row] = 0.0
	sheep.panic_strength[row] = 0.0
	sheep.panic_source[row] = Vector2.ZERO
	sheep.panic_revision[row] = 0

	wolf.hunting[row] = false
	wolf.hunt_elapsed[row] = 0.0
	wolf.charging[row] = false
	wolf.strategy[row] = AnimalEntity.Strategy.FRONTAL
	wolf.strategy_failures[row] = Vector4.ZERO
	wolf.retreating[row] = false
	wolf.resting[row] = false
	wolf.rest_elapsed[row] = 0.0
	wolf.howl_elapsed[row] = 1000.0
	wolf.howled[row] = false
	wolf.howl_pending[row] = false
	wolf.nearest_threat[row] = null

	dog.region[row] = -1
	dog.protection_center[row] = Vector2.ZERO
	dog.guard_point[row] = Vector2.ZERO
	dog.wolf_candidates[row] = []
	dog.stray_candidates[row] = []
	dog.assignment_remaining[row] = 0.0
	dog.returning[row] = false
	dog.patrol_angle[row] = 0.0
	dog.protected_sheep[row] = null
	dog.collected_sheep[row] = null

	settings[row] = null

func swap_rows(first: int, second: int) -> void:
	if first == second:
		return

	# 1) Swap every column so each row continues to describe one complete animal.
	index.structure_version += 1
	var intent := motion.intent[first]
	motion.intent[first] = motion.intent[second]
	motion.intent[second] = intent
	var value_0 = identity.entity_id[first]
	identity.entity_id[first] = identity.entity_id[second]
	identity.entity_id[second] = value_0
	var value_1 = identity.kind[first]
	identity.kind[first] = identity.kind[second]
	identity.kind[second] = value_1
	var value_2 = identity.alive[first]
	identity.alive[first] = identity.alive[second]
	identity.alive[second] = value_2
	var value_3 = identity.death_remaining[first]
	identity.death_remaining[first] = identity.death_remaining[second]
	identity.death_remaining[second] = value_3

	var value_4 = motion.position[first]
	motion.position[first] = motion.position[second]
	motion.position[second] = value_4
	var value_5 = motion.facing[first]
	motion.facing[first] = motion.facing[second]
	motion.facing[second] = value_5
	var value_6 = motion.velocity[first]
	motion.velocity[first] = motion.velocity[second]
	motion.velocity[second] = value_6
	var value_7 = motion.desired_velocity[first]
	motion.desired_velocity[first] = motion.desired_velocity[second]
	motion.desired_velocity[second] = value_7
	var value_8 = motion.movement_goal[first]
	motion.movement_goal[first] = motion.movement_goal[second]
	motion.movement_goal[second] = value_8
	var value_9 = motion.separation[first]
	motion.separation[first] = motion.separation[second]
	motion.separation[second] = value_9
	var value_10 = motion.speed_limit[first]
	motion.speed_limit[first] = motion.speed_limit[second]
	motion.speed_limit[second] = value_10
	var value_11 = motion.wander_point[first]
	motion.wander_point[first] = motion.wander_point[second]
	motion.wander_point[second] = value_11
	var value_12 = motion.wander_remaining[first]
	motion.wander_remaining[first] = motion.wander_remaining[second]
	motion.wander_remaining[second] = value_12

	var value_13 = memory.last_seen_position[first]
	memory.last_seen_position[first] = memory.last_seen_position[second]
	memory.last_seen_position[second] = value_13
	var value_14 = memory.last_seen_velocity[first]
	memory.last_seen_velocity[first] = memory.last_seen_velocity[second]
	memory.last_seen_velocity[second] = value_14
	var value_15 = memory.unseen_elapsed[first]
	memory.unseen_elapsed[first] = memory.unseen_elapsed[second]
	memory.unseen_elapsed[second] = value_15
	var value_16 = memory.target_visible[first]
	memory.target_visible[first] = memory.target_visible[second]
	memory.target_visible[second] = value_16
	var value_18 = memory.nearby[first]
	memory.nearby[first] = memory.nearby[second]
	memory.nearby[second] = value_18
	var value_19 = memory.perception_remaining[first]
	memory.perception_remaining[first] = memory.perception_remaining[second]
	memory.perception_remaining[second] = value_19
	var value_20 = memory.perception_ready[first]
	memory.perception_ready[first] = memory.perception_ready[second]
	memory.perception_ready[second] = value_20
	var value_21 = memory.vision_radius_squared[first]
	memory.vision_radius_squared[first] = memory.vision_radius_squared[second]
	memory.vision_radius_squared[second] = value_21
	var value_22 = memory.vision_cos[first]
	memory.vision_cos[first] = memory.vision_cos[second]
	memory.vision_cos[second] = value_22
	var value_23 = memory.target[first]
	memory.target[first] = memory.target[second]
	memory.target[second] = value_23

	var value_24 = brain.current_behavior[first]
	brain.current_behavior[first] = brain.current_behavior[second]
	brain.current_behavior[second] = value_24
	var value_26 = brain.instance[first]
	brain.instance[first] = brain.instance[second]
	brain.instance[second] = value_26

	var value_27 = sheep.local_flock_center[first]
	sheep.local_flock_center[first] = sheep.local_flock_center[second]
	sheep.local_flock_center[second] = value_27
	var value_28 = sheep.neighbor_count[first]
	sheep.neighbor_count[first] = sheep.neighbor_count[second]
	sheep.neighbor_count[second] = value_28
	var value_29 = sheep.alignment[first]
	sheep.alignment[first] = sheep.alignment[second]
	sheep.alignment[second] = value_29
	var value_30 = sheep.threat_direction[first]
	sheep.threat_direction[first] = sheep.threat_direction[second]
	sheep.threat_direction[second] = value_30
	var value_31 = sheep.dog_pressure[first]
	sheep.dog_pressure[first] = sheep.dog_pressure[second]
	sheep.dog_pressure[second] = value_31
	var threat_strength := sheep.threat_strength[first]
	sheep.threat_strength[first] = sheep.threat_strength[second]
	sheep.threat_strength[second] = threat_strength
	var value_33 = sheep.panic_strength[first]
	sheep.panic_strength[first] = sheep.panic_strength[second]
	sheep.panic_strength[second] = value_33
	var value_36 = sheep.panic_source[first]
	sheep.panic_source[first] = sheep.panic_source[second]
	sheep.panic_source[second] = value_36
	var panic_revision := sheep.panic_revision[first]
	sheep.panic_revision[first] = sheep.panic_revision[second]
	sheep.panic_revision[second] = panic_revision

	var value_38 = wolf.hunting[first]
	wolf.hunting[first] = wolf.hunting[second]
	wolf.hunting[second] = value_38
	var value_39 = wolf.hunt_elapsed[first]
	wolf.hunt_elapsed[first] = wolf.hunt_elapsed[second]
	wolf.hunt_elapsed[second] = value_39
	var value_40 = wolf.charging[first]
	wolf.charging[first] = wolf.charging[second]
	wolf.charging[second] = value_40
	var value_41 = wolf.strategy[first]
	wolf.strategy[first] = wolf.strategy[second]
	wolf.strategy[second] = value_41
	var value_42 = wolf.strategy_failures[first]
	wolf.strategy_failures[first] = wolf.strategy_failures[second]
	wolf.strategy_failures[second] = value_42
	var value_43 = wolf.retreating[first]
	wolf.retreating[first] = wolf.retreating[second]
	wolf.retreating[second] = value_43
	var value_44 = wolf.resting[first]
	wolf.resting[first] = wolf.resting[second]
	wolf.resting[second] = value_44
	var value_45 = wolf.rest_elapsed[first]
	wolf.rest_elapsed[first] = wolf.rest_elapsed[second]
	wolf.rest_elapsed[second] = value_45
	var value_46 = wolf.howl_elapsed[first]
	wolf.howl_elapsed[first] = wolf.howl_elapsed[second]
	wolf.howl_elapsed[second] = value_46
	var value_47 = wolf.howled[first]
	wolf.howled[first] = wolf.howled[second]
	wolf.howled[second] = value_47
	var value_48 = wolf.howl_pending[first]
	wolf.howl_pending[first] = wolf.howl_pending[second]
	wolf.howl_pending[second] = value_48
	var value_49 = wolf.nearest_threat[first]
	wolf.nearest_threat[first] = wolf.nearest_threat[second]
	wolf.nearest_threat[second] = value_49

	var region := dog.region[first]
	dog.region[first] = dog.region[second]
	dog.region[second] = region
	var value_50 = dog.protection_center[first]
	dog.protection_center[first] = dog.protection_center[second]
	dog.protection_center[second] = value_50
	var value_51 = dog.guard_point[first]
	dog.guard_point[first] = dog.guard_point[second]
	dog.guard_point[second] = value_51
	var value_52 = dog.wolf_candidates[first]
	dog.wolf_candidates[first] = dog.wolf_candidates[second]
	dog.wolf_candidates[second] = value_52
	var value_53 = dog.stray_candidates[first]
	dog.stray_candidates[first] = dog.stray_candidates[second]
	dog.stray_candidates[second] = value_53
	var value_54 = dog.assignment_remaining[first]
	dog.assignment_remaining[first] = dog.assignment_remaining[second]
	dog.assignment_remaining[second] = value_54
	var value_55 = dog.returning[first]
	dog.returning[first] = dog.returning[second]
	dog.returning[second] = value_55
	var value_56 = dog.patrol_angle[first]
	dog.patrol_angle[first] = dog.patrol_angle[second]
	dog.patrol_angle[second] = value_56
	var value_57 = dog.protected_sheep[first]
	dog.protected_sheep[first] = dog.protected_sheep[second]
	dog.protected_sheep[second] = value_57
	var value_58 = dog.collected_sheep[first]
	dog.collected_sheep[first] = dog.collected_sheep[second]
	dog.collected_sheep[second] = value_58

	# 2) Move identity and handle ownership with the data, then repair cached rows.
	var value_59 = settings[first]
	settings[first] = settings[second]
	settings[second] = value_59
	var value_60 = identity.animal_id[first]
	identity.animal_id[first] = identity.animal_id[second]
	identity.animal_id[second] = value_60
	var handle := index.handles[first]
	index.handles[first] = index.handles[second]
	index.handles[second] = handle
	if index.handles[first] != null:
		index.handles[first].row = first
	if index.handles[second] != null:
		index.handles[second].row = second

	# 3) Repair both directions of the stable-slot mapping.
	var slot := index.row_to_slot[first]
	index.row_to_slot[first] = index.row_to_slot[second]
	index.row_to_slot[second] = slot
	index.slot_to_row[index.row_to_slot[first]] = first
	index.slot_to_row[index.row_to_slot[second]] = second

# Resolve a full life identity, validating cached rows before using the slot map.
# e.g. row_of_id(old_id) returns -1 after its slot is reused with a new serial.
func row_of_id(id: int, cached_row: int = -1) -> int:
	if cached_row >= 0 and cached_row < identity.animal_id.size() and identity.animal_id[cached_row] == id and id != AnimalID.INVALID:
		return cached_row
	if not AnimalID.is_valid(id):
		return -1

	var slot := AnimalID.get_slot(id)
	if slot >= index.slot_to_row.size():
		return -1

	var row := index.slot_to_row[slot]
	return row if row >= 0 and row < identity.animal_id.size() and identity.animal_id[row] == id else -1

func row_of(handle: AnimalEntity) -> int:
	return row_of_id(handle.id, handle.row) if handle != null else -1

func live(handle: AnimalEntity) -> AnimalEntity:
	if handle == null:
		return null

	var row := handle.row
	if row >= 0 and row < index.active_count and identity.animal_id[row] == handle.id:
		return index.handles[row] if identity.alive[row] else null

	row = row_of_id(handle.id)
	return index.handles[row] if row >= 0 and row < index.active_count and identity.alive[row] else null

func clear() -> void:
	index.structure_version += 1
	for handle in index.handles:
		if handle != null:
			handle.row = -1

	identity.entity_id.clear()
	identity.kind.clear()
	identity.alive.clear()
	identity.death_remaining.clear()

	motion.intent.clear()
	motion.position.clear()
	motion.facing.clear()
	motion.velocity.clear()
	motion.desired_velocity.clear()
	motion.movement_goal.clear()
	motion.separation.clear()
	motion.speed_limit.clear()
	motion.wander_point.clear()
	motion.wander_remaining.clear()

	memory.last_seen_position.clear()
	memory.last_seen_velocity.clear()
	memory.unseen_elapsed.clear()
	memory.target_visible.clear()
	memory.nearby.clear()
	memory.perception_remaining.clear()
	memory.perception_ready.clear()
	memory.vision_radius_squared.clear()
	memory.vision_cos.clear()
	memory.target.clear()

	brain.current_behavior.clear()
	brain.instance.clear()

	sheep.local_flock_center.clear()
	sheep.neighbor_count.clear()
	sheep.alignment.clear()
	sheep.threat_direction.clear()
	sheep.dog_pressure.clear()
	sheep.threat_strength.clear()
	sheep.panic_strength.clear()
	sheep.panic_source.clear()
	sheep.panic_revision.clear()

	wolf.hunting.clear()
	wolf.hunt_elapsed.clear()
	wolf.charging.clear()
	wolf.strategy.clear()
	wolf.strategy_failures.clear()
	wolf.retreating.clear()
	wolf.resting.clear()
	wolf.rest_elapsed.clear()
	wolf.howl_elapsed.clear()
	wolf.howled.clear()
	wolf.howl_pending.clear()
	wolf.nearest_threat.clear()

	dog.region.clear()
	dog.protection_center.clear()
	dog.guard_point.clear()
	dog.wolf_candidates.clear()
	dog.stray_candidates.clear()
	dog.assignment_remaining.clear()
	dog.returning.clear()
	dog.patrol_angle.clear()
	dog.protected_sheep.clear()
	dog.collected_sheep.clear()

	settings.clear()
	index.handles.clear()
	identity.animal_id.clear()
	index.row_to_slot.clear()
	index.slot_to_row.clear()
	index.entities.clear()
	index.sheep_rows.clear()
	index.wolf_rows.clear()
	index.dog_rows.clear()
	index.active_count = 0
	index.retained_count = 0

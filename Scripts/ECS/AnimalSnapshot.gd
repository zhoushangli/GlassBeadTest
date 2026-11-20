class_name AnimalSnapshot
extends RefCounted

# Keep simulation time separate from wall-clock profiling timestamps.
# e.g. simulation_time - time ages perception results; captured_usec measures real latency.
var time: float = 0.0
var captured_usec: int = 0
var prepare_ms: float = 0.0
var stats: bool = false
var detailed: bool = false
var distance: float = 0.0
var interval: float = 0.0
var due := PackedInt32Array()
var config: SimulationConfig

class Index extends RefCounted:
	var sheep_rows := PackedInt32Array()
	var wolf_rows := PackedInt32Array()
	var dog_rows := PackedInt32Array()

class Identity extends RefCounted:
	var animal_id := PackedInt64Array()
	var entity_id := PackedInt64Array()
	var kind := PackedInt32Array()

class Motion extends RefCounted:
	var position := PackedVector2Array()
	var velocity := PackedVector2Array()
	var facing := PackedVector2Array()
	var separation := PackedVector2Array()
	var wander_point := PackedVector2Array()

class Memory extends RefCounted:
	var vision_radius_squared := PackedFloat64Array()
	var vision_cos := PackedFloat64Array()
	var target_visible := PackedByteArray()
	var unseen_elapsed := PackedFloat64Array()
	var last_seen_position := PackedVector2Array()
	var last_seen_velocity := PackedVector2Array()
	var perception_ready := PackedByteArray()
	var perception_remaining := PackedFloat64Array()
	# Store snapshot-local target rows; resolve full identities before writing live storage.
	# e.g. target[row] = -1 represents no live target at capture time.
	var target := PackedInt32Array()

class Sheep extends RefCounted:
	var panic_strength := PackedFloat64Array()
	var panic_source := PackedVector2Array()
	var panic_revision := PackedInt64Array()

class Wolf extends RefCounted:
	var hunting := PackedByteArray()
	var resting := PackedByteArray()
	var retreating := PackedByteArray()

class Dog extends RefCounted:
	var returning := PackedByteArray()
	var assignment_remaining := PackedFloat64Array()
	var region := PackedInt32Array()
	var protection_center := PackedVector2Array()
	var collected_sheep := PackedInt32Array()

var index: Index = Index.new()
var identity: Identity = Identity.new()
var motion: Motion = Motion.new()
var memory: Memory = Memory.new()
var sheep: Sheep = Sheep.new()
var wolf: Wolf = Wolf.new()
var dog: Dog = Dog.new()

func rows_for(kind: int) -> PackedInt32Array:
	match kind:
		AnimalEntity.Kind.SHEEP:
			return index.sheep_rows
		AnimalEntity.Kind.WOLF:
			return index.wolf_rows
		_:
			return index.dog_rows

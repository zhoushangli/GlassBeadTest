class_name AnimalSnapshot
extends RefCounted

var time: float = 0.0
var captured_usec: int = 0
var prepare_ms: float = 0.0
var stats: bool = false
var detailed: bool = false
var distance: float = 0.0
var interval: float = 0.0
var due := PackedInt32Array()
var sheep := PackedInt32Array()
var wolves := PackedInt32Array()
var dogs := PackedInt32Array()
var config: SimulationConfig
var gpu: bool = false

var identity_uid := PackedInt64Array()
var identity_entity_id := PackedInt64Array()
var identity_kind := PackedInt32Array()
var row_to_slot := PackedInt32Array()
var motion_position := PackedVector2Array()
var motion_velocity := PackedVector2Array()
var motion_facing := PackedVector2Array()
var memory_vision_radius_squared := PackedFloat64Array()
var memory_vision_cos := PackedFloat64Array()
var memory_target_visible := PackedByteArray()
var memory_unseen_elapsed := PackedFloat64Array()
var memory_last_seen_position := PackedVector2Array()
var memory_last_seen_velocity := PackedVector2Array()
var motion_separation := PackedVector2Array()
var memory_perception_ready := PackedByteArray()
var memory_perception_remaining := PackedFloat64Array()
var wolf_hunting := PackedByteArray()
var wolf_resting := PackedByteArray()
var wolf_retreating := PackedByteArray()
var dog_returning := PackedByteArray()
var dog_assignment_remaining := PackedFloat64Array()
var dog_region := PackedInt32Array()
var dog_protection_center := PackedVector2Array()
var sheep_panic_strength := PackedFloat64Array()
var sheep_panic_source := PackedVector2Array()
var sheep_panic_revision := PackedInt64Array()
var motion_wander_point := PackedVector2Array()
var memory_target := PackedInt32Array()
var dog_collected_sheep := PackedInt32Array()

func rows_for(kind: int) -> PackedInt32Array:
	match kind:
		AnimalEntity.Kind.SHEEP:
			return sheep
		AnimalEntity.Kind.WOLF:
			return wolves
		_:
			return dogs

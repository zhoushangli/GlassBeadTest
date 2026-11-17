class_name GridSnapshot
extends RefCounted

var captured_usec: int = 0
var time: float = 0.0
var slots := PackedInt32Array()
var uids := PackedInt64Array()
var region_width: int = 0
var region_height: int = 0
var region_counts := PackedInt32Array()
var region_centers := PackedVector2Array()
var region_velocities := PackedVector2Array()
var occupied_regions := PackedInt32Array()
var cell_size: float = 0.0
var width: int = 0
var height: int = 0
var pressure_sample_count: int = 0
var nonempty_cells: int = 0
var max_occupancy: int = 0
var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var position_sums := PackedVector2Array()
var velocity_sums := PackedVector2Array()
var flock_sums := PackedVector2Array()
var alignment_sums := PackedVector2Array()
var kinds := PackedInt32Array()
var counts := PackedInt32Array()
var offsets := PackedInt32Array()
var members := PackedInt32Array()
var row_cells := PackedInt32Array()
var flock_counts := PackedInt32Array()
var alignment_counts := PackedInt32Array()
var pressure_nodes := PackedInt32Array()
var populated := PackedInt32Array()
var occupied := PackedInt32Array()
var pressure_needed := PackedByteArray()

class Pressure extends RefCounted:
	var field := PackedVector2Array()
	var sheep_threat_direction := PackedVector2Array()
	var sheep_threat_strength := PackedFloat64Array()
	var sheep_dog_pressure := PackedVector2Array()
	var pairs: int = 0

func region_at(point: Vector2) -> int:
	var size := cell_size * 4.0
	return clampi(floori(point.y / size), 0, region_height - 1) * region_width + clampi(floori(point.x / size), 0, region_width - 1)

func has_region(region: int) -> bool:
	return region >= 0 and region < region_counts.size() and region_counts[region] > 0

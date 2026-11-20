class_name GridSnapshot
extends RefCounted

const PRESSURE_SHARED_MIN_SHEEP := 4

var captured_usec: int = 0
var time: float = 0.0
var animal_ids := PackedInt64Array()
var cell_size: float = 0.0
var width: int = 0
var height: int = 0
var nonempty_cells: int = 0
var max_occupancy: int = 0

class PressureResult extends RefCounted:
	var field := PackedVector2Array()
	var sheep_threat_direction := PackedVector2Array()
	var sheep_threat_strength := PackedFloat64Array()
	var sheep_dog_pressure := PackedVector2Array()
	var pairs: int = 0

class Cells extends RefCounted:
	var positions := PackedVector2Array()
	var velocities := PackedVector2Array()
	var kinds := PackedInt32Array()
	var counts := PackedInt32Array()
	# Index contiguous species buckets with a final sentinel offset.
	# e.g. sheep in cell c occupy members[offsets[c * 3] : offsets[c * 3 + 1]].
	var offsets := PackedInt32Array()
	var members := PackedInt32Array()
	var row_cells := PackedInt32Array()
	var populated := PackedInt32Array()
	var occupied := PackedInt32Array()

class Flock extends RefCounted:
	var position_sums := PackedVector2Array()
	var velocity_sums := PackedVector2Array()
	var sums := PackedVector2Array()
	var alignment_sums := PackedVector2Array()
	var counts := PackedInt32Array()
	var alignment_counts := PackedInt32Array()

class Pressure extends RefCounted:
	var sample_count: int = 0
	var nodes := PackedInt32Array()
	var needed := PackedByteArray()

class Regions extends RefCounted:
	var width: int = 0
	var height: int = 0
	var counts := PackedInt32Array()
	var centers := PackedVector2Array()
	var velocities := PackedVector2Array()
	var occupied := PackedInt32Array()

var cells: Cells = Cells.new()
var flock: Flock = Flock.new()
var pressure: Pressure = Pressure.new()
var regions: Regions = Regions.new()

func region_at(point: Vector2) -> int:
	var size := cell_size * 4.0
	return clampi(floori(point.y / size), 0, regions.height - 1) * regions.width + clampi(floori(point.x / size), 0, regions.width - 1)

func has_region(region: int) -> bool:
	return region >= 0 and region < regions.counts.size() and regions.counts[region] > 0

static func query_snapshot(point: Vector2, radius: float, kind: int, snapshot: GridSnapshot, stats: Dictionary) -> PackedInt32Array:
	var started_at := Time.get_ticks_usec() if stats.detailed else 0
	var nearby := PackedInt32Array()
	var size: float = snapshot.cell_size
	var columns: int = snapshot.width
	var first := Vector2i(((point - Vector2.ONE * radius) / size).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((point + Vector2.ONE * radius) / size).floor()).min(Vector2i(columns - 1, snapshot.height - 1))
	var offsets: PackedInt32Array = snapshot.cells.offsets
	var packed_members: PackedInt32Array = snapshot.cells.members
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var bucket := (y * columns + x) * 3
			var begin := offsets[bucket + kind] if kind >= 0 else offsets[bucket]
			var end := offsets[bucket + kind + 1] if kind >= 0 else offsets[bucket + 3]
			for member in range(begin, end):
				nearby.append(packed_members[member])

	if stats.enabled:
		stats.queries += 1
		stats.candidates += nearby.size()
		stats.max_candidates = maxi(stats.max_candidates, nearby.size())

	if stats.detailed:
		stats.hotspots.NearbyQuery += (Time.get_ticks_usec() - started_at) / 1000.0
		stats.calls.NearbyQuery += 1
	return nearby

static func snapshot_offsets(radius: float, size: float) -> PackedInt32Array:
	var offsets := PackedInt32Array()
	var extent := ceili(radius / size)
	for y in range(-extent, extent + 1):
		for x in range(-extent, extent + 1):
			if Vector2(x, y).length_squared() * size * size <= radius * radius:
				offsets.append(x)
				offsets.append(y)
	return offsets

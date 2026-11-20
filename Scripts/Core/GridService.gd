class_name GridService
extends Service

var spatial_stats_enabled: bool = OS.is_debug_build()
var spatial_query_count: int = 0
var spatial_candidate_count: int = 0
var spatial_max_candidates: int = 0
var spatial_nonempty_cells: int = 0
var spatial_max_occupancy: int = 0

func sample_pressure(point: Vector2, field: PackedVector2Array) -> Vector2:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var coordinate := point / spatial.current.cell_size
	var x := clampi(floori(coordinate.x), 0, spatial.current.width - 1)
	var y := clampi(floori(coordinate.y), 0, spatial.current.height - 1)
	var fraction := (coordinate - Vector2(x, y)).clamp(Vector2.ZERO, Vector2.ONE)
	var node := y * (spatial.current.width + 1) + x
	return field[node].lerp(field[node + 1], fraction.x).lerp(field[node + spatial.current.width + 1].lerp(field[node + spatial.current.width + 2], fraction.x), fraction.y)

func cell_at(point: Vector2) -> int:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var x := clampi(floori(point.x / spatial.current.cell_size), 0, spatial.current.width - 1)
	var y := clampi(floori(point.y / spatial.current.cell_size), 0, spatial.current.height - 1)
	return y * spatial.current.width + x

# Return broad-phase snapshot rows, optionally restricted to one species.
# e.g. get_nearby_indices(Vector2(300, 300), 24.0, AnimalEntity.Kind.SHEEP)
func get_nearby_indices(point: Vector2, radius: float, kind: int = -1) -> PackedInt32Array:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var started_at := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var nearby := PackedInt32Array()
	var first := Vector2i(((point - Vector2.ONE * radius) / spatial.current.cell_size).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((point + Vector2.ONE * radius) / spatial.current.cell_size).floor()).min(Vector2i(spatial.current.width - 1, spatial.current.height - 1))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var bucket := (y * spatial.current.width + x) * 3
			var begin := spatial.current.cells.offsets[bucket + kind] if kind >= 0 else spatial.current.cells.offsets[bucket]
			var end := spatial.current.cells.offsets[bucket + kind + 1] if kind >= 0 else spatial.current.cells.offsets[bucket + 3]
			for member in range(begin, end):
				nearby.append(spatial.current.cells.members[member])

	if spatial_stats_enabled:
		spatial_query_count += 1
		spatial_candidate_count += nearby.size()
		spatial_max_candidates = maxi(spatial_max_candidates, nearby.size())

	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("NearbyQuery", started_at)
	return nearby

func query_context() -> GridSnapshot:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	return spatial.current

# Average sheep positions in cells whose centers lie inside the radius.
# e.g. sheep_center(Vector2(300, 300), 120.0)
func sheep_center(point: Vector2, radius: float) -> Vector2:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	var first := Vector2i(((point - Vector2.ONE * radius) / spatial.current.cell_size).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((point + Vector2.ONE * radius) / spatial.current.cell_size).floor()).min(Vector2i(spatial.current.width - 1, spatial.current.height - 1))
	var sum := Vector2.ZERO
	var count := 0
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if (Vector2(x + 0.5, y + 0.5) * spatial.current.cell_size).distance_squared_to(point) <= radius * radius:
				var cell := y * spatial.current.width + x
				sum += spatial.current.flock.position_sums[cell]
				count += spatial.current.cells.counts[cell * 3 + AnimalEntity.Kind.SHEEP]
	return sum / count if count > 0 else point

func reset_spatial_stats() -> void:
	spatial_query_count = 0
	spatial_candidate_count = 0
	spatial_max_candidates = 0
	spatial_nonempty_cells = 0
	spatial_max_occupancy = 0

func _reset() -> void:
	var spatial: DataService.Spatial = g_gameplayEngine.data_service.spatial
	spatial.version += 1
	var size := spatial.current.cell_size
	spatial.current = GridSnapshot.new()
	spatial.current.cell_size = size
	spatial.debug.dog_snapshot = null
	spatial.debug.dog_region_coverage = PackedInt32Array()
	spatial.debug.dog_region_threats = PackedInt32Array()
	spatial.pressure.wolf = PackedVector2Array()
	spatial.pressure.dog = PackedVector2Array()
	spatial.pressure.source_pairs = 0
	reset_spatial_stats()

func _shutdown() -> void:
	_reset()

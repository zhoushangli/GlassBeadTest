class_name GridService
extends Service

var cell_size: float = 30.0
var width: int = 0
var height: int = 0

var perception_positions := PackedVector2Array()
var perception_velocities := PackedVector2Array()
var perception_kinds := PackedInt32Array()
var row_cells := PackedInt32Array()
var cell_counts := PackedInt32Array()
var cell_offsets := PackedInt32Array()
var members := PackedInt32Array()

var sheep_position_sums := PackedVector2Array()
var sheep_velocity_sums := PackedVector2Array()
var flock_counts := PackedInt32Array()
var flock_position_sums := PackedVector2Array()
var alignment_counts := PackedInt32Array()
var alignment_velocity_sums := PackedVector2Array()

var _cursors := PackedInt32Array()
var _flock_offsets := PackedInt32Array()
var _alignment_offsets := PackedInt32Array()
var _flock_radius: float = -1.0
var _alignment_radius: float = -1.0
var _offset_cell_size: float = -1.0

var spatial_stats_enabled: bool = OS.is_debug_build()
var spatial_query_count: int = 0
var spatial_candidate_count: int = 0
var spatial_max_candidates: int = 0
var spatial_nonempty_cells: int = 0
var spatial_max_occupancy: int = 0

func rebuild() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var config: SimulationConfig = g_gameplayEngine.config
	cell_size = config.grid_cell_size
	width = ceili(config.arena_size.x / cell_size)
	height = ceili(config.arena_size.y / cell_size)
	var cells := width * height
	reset_spatial_stats()
	cell_counts.resize(cells * 3)
	cell_counts.fill(0)
	cell_offsets.resize(cells * 3 + 1)
	_cursors.resize(cells * 3)
	members.resize(data.active_count)
	row_cells.resize(data.active_count)
	perception_positions.resize(data.active_count)
	perception_velocities.resize(data.active_count)
	perception_kinds.resize(data.active_count)
	sheep_position_sums.resize(cells)
	sheep_position_sums.fill(Vector2.ZERO)
	sheep_velocity_sums.resize(cells)
	sheep_velocity_sums.fill(Vector2.ZERO)

	# 1) Count members by cell and species, and accumulate sheep statistics.
	for row in range(data.active_count):
		var point := data.motion_position[row]
		var cell := cell_at(point)
		var kind := data.identity_kind[row]
		row_cells[row] = cell
		perception_positions[row] = point
		perception_velocities[row] = data.motion_velocity[row]
		perception_kinds[row] = kind
		cell_counts[cell * 3 + kind] += 1
		if kind == AnimalEntity.Kind.SHEEP:
			sheep_position_sums[cell] += point
			sheep_velocity_sums[cell] += data.motion_velocity[row]

	# 2) Pack members into contiguous cell/species ranges in row order.
	cell_offsets[0] = 0
	for bucket in range(cells * 3):
		cell_offsets[bucket + 1] = cell_offsets[bucket] + cell_counts[bucket]
		_cursors[bucket] = cell_offsets[bucket]
	for row in range(data.active_count):
		var bucket := row_cells[row] * 3 + perception_kinds[row]
		members[_cursors[bucket]] = row
		_cursors[bucket] += 1
	if spatial_stats_enabled:
		for cell in range(cells):
			var count := cell_counts[cell * 3] + cell_counts[cell * 3 + 1] + cell_counts[cell * 3 + 2]
			if count > 0:
				spatial_nonempty_cells += 1
				spatial_max_occupancy = maxi(spatial_max_occupancy, count)

	# 3) Share flock and alignment sums between sheep in the same cell.
	if _offset_cell_size != cell_size or _flock_radius != config.sheep.flock_radius or _alignment_radius != config.sheep.alignment_radius:
		_flock_offsets = _make_offsets(config.sheep.flock_radius)
		_alignment_offsets = _make_offsets(config.sheep.alignment_radius)
		_offset_cell_size = cell_size
		_flock_radius = config.sheep.flock_radius
		_alignment_radius = config.sheep.alignment_radius
	flock_counts.resize(cells)
	flock_counts.fill(0)
	flock_position_sums.resize(cells)
	flock_position_sums.fill(Vector2.ZERO)
	alignment_counts.resize(cells)
	alignment_counts.fill(0)
	alignment_velocity_sums.resize(cells)
	alignment_velocity_sums.fill(Vector2.ZERO)
	for cell in range(cells):
		if cell_counts[cell * 3 + AnimalEntity.Kind.SHEEP] == 0:
			continue
		var x := cell % width
		var y := cell / width
		for offset in range(0, _flock_offsets.size(), 2):
			var nx := x + _flock_offsets[offset]
			var ny := y + _flock_offsets[offset + 1]
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				var neighbor := ny * width + nx
				flock_counts[cell] += cell_counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
				flock_position_sums[cell] += sheep_position_sums[neighbor]
		for offset in range(0, _alignment_offsets.size(), 2):
			var nx := x + _alignment_offsets[offset]
			var ny := y + _alignment_offsets[offset + 1]
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				var neighbor := ny * width + nx
				alignment_counts[cell] += cell_counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
				alignment_velocity_sums[cell] += sheep_velocity_sums[neighbor]

func cell_at(point: Vector2) -> int:
	var x := clampi(floori(point.x / cell_size), 0, width - 1)
	var y := clampi(floori(point.y / cell_size), 0, height - 1)
	return y * width + x

func _make_offsets(radius: float) -> PackedInt32Array:
	var offsets := PackedInt32Array()
	var extent := ceili(radius / cell_size)
	for y in range(-extent, extent + 1):
		for x in range(-extent, extent + 1):
			if Vector2(x, y).length_squared() * cell_size * cell_size <= radius * radius:
				offsets.append(x)
				offsets.append(y)
	return offsets

# Return broad-phase snapshot rows, optionally restricted to one species.
# e.g. get_nearby_indices(Vector2(300, 300), 24.0, AnimalEntity.Kind.SHEEP)
func get_nearby_indices(point: Vector2, radius: float, kind: int = -1) -> PackedInt32Array:
	var started_at := Time.get_ticks_usec() if g_gameplayEngine.profile_service.detailed_stats_enabled else 0
	var nearby := PackedInt32Array()
	var first := Vector2i(((point - Vector2.ONE * radius) / cell_size).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((point + Vector2.ONE * radius) / cell_size).floor()).min(Vector2i(width - 1, height - 1))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var bucket := (y * width + x) * 3
			var begin := cell_offsets[bucket + kind] if kind >= 0 else cell_offsets[bucket]
			var end := cell_offsets[bucket + kind + 1] if kind >= 0 else cell_offsets[bucket + 3]
			for member in range(begin, end):
				nearby.append(members[member])
	if spatial_stats_enabled:
		spatial_query_count += 1
		spatial_candidate_count += nearby.size()
		spatial_max_candidates = maxi(spatial_max_candidates, nearby.size())
	if g_gameplayEngine.profile_service.detailed_stats_enabled:
		g_gameplayEngine.profile_service.record_hotspot("NearbyQuery", started_at)
	return nearby

# Average sheep positions in cells whose centers lie inside the radius.
# e.g. sheep_center(Vector2(300, 300), 120.0)
func sheep_center(point: Vector2, radius: float) -> Vector2:
	var first := Vector2i(((point - Vector2.ONE * radius) / cell_size).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((point + Vector2.ONE * radius) / cell_size).floor()).min(Vector2i(width - 1, height - 1))
	var sum := Vector2.ZERO
	var count := 0
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if (Vector2(x + 0.5, y + 0.5) * cell_size).distance_squared_to(point) <= radius * radius:
				var cell := y * width + x
				sum += sheep_position_sums[cell]
				count += cell_counts[cell * 3 + AnimalEntity.Kind.SHEEP]
	return sum / count if count > 0 else point

func reset_spatial_stats() -> void:
	spatial_query_count = 0
	spatial_candidate_count = 0
	spatial_max_candidates = 0
	spatial_nonempty_cells = 0
	spatial_max_occupancy = 0

func _reset() -> void:
	width = 0
	height = 0
	perception_positions.clear()
	perception_velocities.clear()
	perception_kinds.clear()
	row_cells.clear()
	cell_counts.clear()
	cell_offsets.clear()
	members.clear()
	_cursors.clear()
	sheep_position_sums.clear()
	sheep_velocity_sums.clear()
	flock_counts.clear()
	flock_position_sums.clear()
	alignment_counts.clear()
	alignment_velocity_sums.clear()
	reset_spatial_stats()

func _shutdown() -> void:
	_reset()

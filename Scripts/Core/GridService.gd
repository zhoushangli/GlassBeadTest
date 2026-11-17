class_name GridService
extends Service

const PRESSURE_SHARED_MIN_SHEEP := 4

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

var wolf_pressure := PackedVector2Array()
var dog_pressure := PackedVector2Array()
var pressure_nodes := PackedInt32Array()
var _pressure_needed := PackedByteArray()
var debug_snapshot: GridSnapshot
var dog_debug_snapshot: GridSnapshot
var dog_region_coverage := PackedInt32Array()
var dog_region_threats := PackedInt32Array()
var snapshot_version: int = 0
var pressure_sample_count: int = 0
var pressure_source_pairs: int = 0

var spatial_stats_enabled: bool = OS.is_debug_build()
var spatial_query_count: int = 0
var spatial_candidate_count: int = 0
var spatial_max_candidates: int = 0
var spatial_nonempty_cells: int = 0
var spatial_max_occupancy: int = 0

func sample_pressure(point: Vector2, field: PackedVector2Array) -> Vector2:
	var coordinate := point / cell_size
	var x := clampi(floori(coordinate.x), 0, width - 1)
	var y := clampi(floori(coordinate.y), 0, height - 1)
	var fraction := (coordinate - Vector2(x, y)).clamp(Vector2.ZERO, Vector2.ONE)
	var node := y * (width + 1) + x
	return field[node].lerp(field[node + 1], fraction.x).lerp(field[node + width + 1].lerp(field[node + width + 2], fraction.x), fraction.y)

func cell_at(point: Vector2) -> int:
	var x := clampi(floori(point.x / cell_size), 0, width - 1)
	var y := clampi(floori(point.y / cell_size), 0, height - 1)
	return y * width + x

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

func query_context() -> GridSnapshot:
	var grid := GridSnapshot.new()
	grid.cell_size = cell_size
	grid.width = width
	grid.height = height
	grid.offsets = cell_offsets
	grid.members = members
	grid.positions = perception_positions
	grid.velocities = perception_velocities
	grid.kinds = perception_kinds
	grid.row_cells = row_cells
	grid.flock_counts = flock_counts
	grid.flock_sums = flock_position_sums
	grid.alignment_counts = alignment_counts
	grid.alignment_sums = alignment_velocity_sums
	return grid

static func query_snapshot(point: Vector2, radius: float, kind: int, snapshot: GridSnapshot, stats: Dictionary) -> PackedInt32Array:
	var started_at := Time.get_ticks_usec() if stats.detailed else 0
	var nearby := PackedInt32Array()
	var size: float = snapshot.cell_size
	var columns: int = snapshot.width
	var first := Vector2i(((point - Vector2.ONE * radius) / size).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((point + Vector2.ONE * radius) / size).floor()).min(Vector2i(columns - 1, snapshot.height - 1))
	var offsets: PackedInt32Array = snapshot.offsets
	var packed_members: PackedInt32Array = snapshot.members
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
	snapshot_version += 1
	debug_snapshot = null
	dog_debug_snapshot = null
	dog_region_coverage = PackedInt32Array()
	dog_region_threats = PackedInt32Array()
	wolf_pressure = PackedVector2Array()
	dog_pressure = PackedVector2Array()
	pressure_nodes = PackedInt32Array()
	_pressure_needed = PackedByteArray()
	pressure_sample_count = 0
	pressure_source_pairs = 0
	width = 0
	height = 0
	perception_positions = PackedVector2Array()
	perception_velocities = PackedVector2Array()
	perception_kinds = PackedInt32Array()
	row_cells = PackedInt32Array()
	cell_counts = PackedInt32Array()
	cell_offsets = PackedInt32Array()
	members = PackedInt32Array()
	sheep_position_sums = PackedVector2Array()
	sheep_velocity_sums = PackedVector2Array()
	flock_counts = PackedInt32Array()
	flock_position_sums = PackedVector2Array()
	alignment_counts = PackedInt32Array()
	alignment_velocity_sums = PackedVector2Array()

	reset_spatial_stats()

func _shutdown() -> void:
	_reset()

static func build_snapshot(snapshot: AnimalSnapshot) -> GridSnapshot:
	var size: float = snapshot.config.grid_cell_size
	var columns := ceili(snapshot.config.arena_size.x / size)
	var height := ceili(snapshot.config.arena_size.y / size)
	var cells := columns * height
	var count: int = snapshot.sheep.size() + snapshot.wolves.size() + snapshot.dogs.size()
	var positions: PackedVector2Array = snapshot.motion_position
	var velocities: PackedVector2Array = snapshot.motion_velocity
	var kinds := snapshot.identity_kind
	var counts := PackedInt32Array()
	var offsets := PackedInt32Array()
	var packed_members := PackedInt32Array()
	var captured_cells := PackedInt32Array()
	var position_sums := PackedVector2Array()
	var velocity_sums := PackedVector2Array()
	counts.resize(cells * 3)
	offsets.resize(cells * 3 + 1)
	packed_members.resize(count)
	captured_cells.resize(count)
	position_sums.resize(cells)
	velocity_sums.resize(cells)

	# 1) Pack spatial membership from the captured active rows.
	for row in range(count):
		var point := positions[row]
		var cell := clampi(floori(point.y / size), 0, height - 1) * columns + clampi(floori(point.x / size), 0, columns - 1)
		captured_cells[row] = cell
		counts[cell * 3 + kinds[row]] += 1
		if kinds[row] == AnimalEntity.Kind.SHEEP:
			position_sums[cell] += point
			velocity_sums[cell] += velocities[row]

	for bucket in range(cells * 3):
		offsets[bucket + 1] = offsets[bucket] + counts[bucket]
	var cursors := offsets.duplicate()
	for row in range(count):
		var bucket := captured_cells[row] * 3 + kinds[row]
		packed_members[cursors[bucket]] = row
		cursors[bucket] += 1

	# 2) Collect occupied cells for GPU aggregation and regional statistics.
	var occupied := PackedInt32Array()
	var populated := PackedInt32Array()
	var nonempty := 0
	var occupancy_max := 0
	for cell in range(cells):
		var occupancy := counts[cell * 3] + counts[cell * 3 + 1] + counts[cell * 3 + 2]
		if occupancy > 0:
			populated.append(cell)
			nonempty += 1
			occupancy_max = maxi(occupancy_max, occupancy)
		if counts[cell * 3] > 0:
			occupied.append(cell)

	var flock_count := PackedInt32Array()
	var flock_sum := PackedVector2Array()
	var aligned_count := PackedInt32Array()
	var aligned_sum := PackedVector2Array()
	flock_count.resize(cells)
	flock_sum.resize(cells)
	aligned_count.resize(cells)
	aligned_sum.resize(cells)

	# 3) Deduplicate pressure sample nodes shared by densely populated sheep cells.
	var needed := PackedByteArray()
	needed.resize((columns + 1) * (height + 1))
	var nodes := PackedInt32Array()
	var requested_nodes := PackedInt32Array()
	for cell in occupied:
		if counts[cell * 3] >= PRESSURE_SHARED_MIN_SHEEP:
			var base: int = (cell / columns) * (columns + 1) + cell % columns
			requested_nodes.append_array(PackedInt32Array([base, base + 1, base + columns + 1, base + columns + 2]))
	for node in requested_nodes:
		if not needed[node]:
			needed[node] = 1
			nodes.append(node)

	# 4) Publish snapshot columns and aggregate occupied 4-by-4-cell dog regions.
	var grid := GridSnapshot.new()
	grid.cell_size = size
	grid.width = columns
	grid.height = height
	grid.positions = positions
	grid.velocities = velocities
	grid.kinds = kinds
	grid.counts = counts
	grid.offsets = offsets
	grid.members = packed_members
	grid.row_cells = captured_cells
	grid.position_sums = position_sums
	grid.velocity_sums = velocity_sums
	grid.flock_counts = flock_count
	grid.flock_sums = flock_sum
	grid.alignment_counts = aligned_count
	grid.alignment_sums = aligned_sum
	grid.pressure_nodes = nodes
	grid.pressure_needed = needed
	grid.pressure_sample_count = nodes.size()
	grid.nonempty_cells = nonempty
	grid.max_occupancy = occupancy_max
	grid.populated = populated
	grid.occupied = occupied
	grid.captured_usec = snapshot.captured_usec
	grid.time = snapshot.time
	grid.animal_ids = snapshot.identity_animal_id
	grid.region_width = ceili(columns / 4.0)
	grid.region_height = ceili(height / 4.0)

	var regions := grid.region_width * grid.region_height
	grid.region_counts.resize(regions)
	grid.region_centers.resize(regions)
	grid.region_velocities.resize(regions)
	for cell in occupied:
		var region := floori(float(cell % columns) / 4.0) + floori(float(cell / columns) / 4.0) * grid.region_width
		grid.region_counts[region] += counts[cell * 3]
		grid.region_centers[region] += position_sums[cell]
		grid.region_velocities[region] += velocity_sums[cell]

	for region in range(regions):
		if grid.region_counts[region] == 0:
			continue

		grid.occupied_regions.append(region)
		grid.region_centers[region] /= grid.region_counts[region]
		grid.region_velocities[region] /= grid.region_counts[region]

	return grid

static func snapshot_offsets(radius: float, size: float) -> PackedInt32Array:
	var offsets := PackedInt32Array()
	var extent := ceili(radius / size)
	for y in range(-extent, extent + 1):
		for x in range(-extent, extent + 1):
			if Vector2(x, y).length_squared() * size * size <= radius * radius:
				offsets.append(x)
				offsets.append(y)
	return offsets

func install_snapshot(grid: GridSnapshot) -> void:
	debug_snapshot = grid
	snapshot_version += 1
	cell_size = grid.cell_size
	width = grid.width
	height = grid.height
	perception_positions = grid.positions
	perception_velocities = grid.velocities
	perception_kinds = grid.kinds
	row_cells = grid.row_cells
	cell_counts = grid.counts
	cell_offsets = grid.offsets
	members = grid.members
	sheep_position_sums = grid.position_sums
	sheep_velocity_sums = grid.velocity_sums
	flock_counts = grid.flock_counts
	flock_position_sums = grid.flock_sums
	alignment_counts = grid.alignment_counts
	alignment_velocity_sums = grid.alignment_sums

	_pressure_needed = grid.pressure_needed
	wolf_pressure.resize((width + 1) * (height + 1))
	wolf_pressure.fill(Vector2.ZERO)
	dog_pressure.resize((width + 1) * (height + 1))
	dog_pressure.fill(Vector2.ZERO)
	pressure_source_pairs = 0
	pressure_nodes = grid.pressure_nodes
	pressure_sample_count = grid.pressure_sample_count

	reset_spatial_stats()
	if spatial_stats_enabled:
		spatial_nonempty_cells = grid.nonempty_cells
		spatial_max_occupancy = grid.max_occupancy

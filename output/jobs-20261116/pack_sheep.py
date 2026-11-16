from pathlib import Path
p=Path("Scripts/ECS/Systems/SheepSystem.gd")
s=p.read_text()
a=s.index("func apply_batch(")
b=s.index("\nfunc _scan_neighbors",a)
replacement="""func apply_batch(output: Dictionary, delta: float) -> void:
	var common: AnimalSystem = g_gameplayEngine.animal_system
	common.submit_stats(output.stats)
	var rows: PackedInt32Array = output.rows
	var remaining: PackedFloat64Array = output.remaining
	var refresh: PackedByteArray = output.refresh
	var nearby: Array[PackedInt32Array] = output.nearby
	var separation: PackedVector2Array = output.separation
	var centers: PackedVector2Array = output.centers
	var counts: PackedInt32Array = output.counts
	var alignment: PackedVector2Array = output.alignment
	var panic: PackedFloat64Array = output.panic
	var perception_remaining := data.memory_perception_remaining
	var perception_ready := data.memory_perception_ready
	var wander_remaining := data.motion_wander_remaining
	var local_centers := data.sheep_local_flock_center
	var neighbor_counts := data.sheep_neighbor_count
	var alignments := data.sheep_alignment
	var panic_strengths := data.sheep_panic_strength
	var intents := data.motion_intent
	var separations := data.motion_separation
	var wander := g_gameplayEngine.config.sheep.wander_weight > 0.0
	for index in range(rows.size()):
		var row := rows[index]
		perception_remaining[row] = remaining[index]
		perception_ready[row] = 1
		wander_remaining[row] -= delta
		if refresh[index]:
			data.memory_nearby[row] = nearby[index]
			separations[row] = separation[index]
		local_centers[row] = centers[index]
		neighbor_counts[row] = counts[index]
		alignments[row] = alignment[index]
		panic_strengths[row] = panic[index]
		intents[row] = AnimalData.MotionIntent.SHEEP
		if wander:
			common.get_wander_point(data.handles[row], 85.0)

func calculate_batch(output: Dictionary, rows: PackedInt32Array, context: Dictionary) -> void:
	var stats := AnimalSystem.batch_stats(context)
	var grid: Dictionary = context.grid
	var positions: PackedVector2Array = grid.positions
	var velocities: PackedVector2Array = grid.velocities
	var kinds: PackedInt32Array = grid.kinds
	var cells: PackedInt32Array = grid.row_cells
	var flock_counts: PackedInt32Array = grid.flock_counts
	var flock_sums: PackedVector2Array = grid.flock_sums
	var alignment_counts: PackedInt32Array = grid.alignment_counts
	var alignment_sums: PackedVector2Array = grid.alignment_sums
	var perception_remaining := data.memory_perception_remaining
	var perception_ready := data.memory_perception_ready
	var ids := data.identity_entity_id
	var separations := data.motion_separation
	var panic_strengths := data.sheep_panic_strength
	var delta: float = context.delta
	var interval: float = context.interval
	var distance_limit: float = context.distance
	var panic_duration: float = context.panic_duration
	var remaining: PackedFloat64Array = output.get("remaining", PackedFloat64Array())
	var refresh: PackedByteArray = output.get("refresh", PackedByteArray())
	var nearby: Array[PackedInt32Array] = []
	var separation: PackedVector2Array = output.get("separation", PackedVector2Array())
	var centers: PackedVector2Array = output.get("centers", PackedVector2Array())
	var counts: PackedInt32Array = output.get("counts", PackedInt32Array())
	var alignment: PackedVector2Array = output.get("alignment", PackedVector2Array())
	var panic: PackedFloat64Array = output.get("panic", PackedFloat64Array())
	remaining.resize(rows.size())
	refresh.resize(rows.size())
	nearby.resize(rows.size())
	separation.resize(rows.size())
	centers.resize(rows.size())
	counts.resize(rows.size())
	alignment.resize(rows.size())
	panic.resize(rows.size())
	for index in range(rows.size()):
		var row := rows[index]
		remaining[index] = perception_remaining[row] - delta
		refresh[index] = int(not perception_ready[row] or remaining[index] <= 0.0)
		nearby[index] = data.memory_nearby[row]
		separation[index] = separations[row]
		if refresh[index]:
			nearby[index] = GridService.query_snapshot(positions[row], distance_limit, AnimalEntity.Kind.SHEEP, grid, stats)
			var started_at := Time.get_ticks_usec() if stats.detailed else 0
			var force := Vector2.ZERO
			if distance_limit > 0.0:
				for other in nearby[index]:
					if other == row or kinds[other] != AnimalEntity.Kind.SHEEP:
						continue
					var offset := positions[row] - positions[other]
					var squared := offset.length_squared()
					if squared >= distance_limit * distance_limit:
						continue
					var distance := sqrt(squared)
					var direction := offset.normalized()
					if distance < 0.001:
						direction = Vector2.RIGHT if ids[row] < ids[other] else Vector2.LEFT
					force += direction * (1.0 - distance / distance_limit)
			separation[index] = force
			if stats.detailed:
				stats.hotspots.Separation += (Time.get_ticks_usec() - started_at) / 1000.0
				stats.calls.Separation += 1
			remaining[index] = interval
			if not perception_ready[row]:
				remaining[index] *= fmod(ids[row] * 0.618034, 1.0)
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		var cell := cells[row]
		var count := flock_counts[cell] - 1
		var aligned := alignment_counts[cell] - 1
		centers[index] = (flock_sums[cell] - positions[row]) / count if count > 0 else positions[row]
		counts[index] = count
		alignment[index] = (alignment_sums[cell] - velocities[row]) / aligned if aligned > 0 else Vector2.ZERO
		panic[index] = maxf(0.0, panic_strengths[row] - delta / panic_duration) if panic_duration > 0.0 else 0.0
		if stats.detailed:
			stats.hotspots.NeighborScan += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.NeighborScan += 1
	output.merge({"rows": rows, "remaining": remaining, "refresh": refresh, "nearby": nearby, "separation": separation,
		"centers": centers, "counts": counts, "alignment": alignment, "panic": panic, "stats": stats}, true)
"""
p.write_text(s[:a]+replacement+s[b:])

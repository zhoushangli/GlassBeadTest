class_name DogAnchorJob
extends Job

var anchors := PackedInt32Array()
var coverage := PackedInt32Array()
var sheep := PackedInt32Array()

var anchor_rows := PackedInt32Array()

func execute() -> void:
	_calculate_anchors()

func apply_result() -> void:
	_apply_anchors()

func copy_input(source: Job) -> void:
	super.copy_input(source)
	var input := source as DogAnchorJob
	anchors = input.anchors
	coverage = input.coverage
	sheep = input.sheep

func release_input() -> void:
	super.release_input()
	anchors = PackedInt32Array()
	coverage = PackedInt32Array()
	sheep = PackedInt32Array()

func _calculate_anchors() -> void:
	anchor_rows.resize(rows.size())
	var stats := Job.batch_stats(spatial_stats, detailed)
	var positions: PackedVector2Array = grid.cells.positions
	var coverage: PackedInt32Array = self.coverage
	var radius: float = config.sheepdog.local_flock_radius
	var weight: float = config.sheepdog.coverage_weight
	for index in range(rows.size()):
		var row := rows[index]
		var current: int = anchors[row]
		var started_at := Time.get_ticks_usec() if stats.detailed else 0
		var own_anchor := positions[current] if current >= 0 else Vector2.INF
		var point := positions[row]
		var best := current
		var current_score := _snapshot_anchor_score(point, positions[current], coverage[current], own_anchor, radius, weight) if current >= 0 else INF
		var best_score := current_score
		for sheep_row in sheep:
			var score := _snapshot_anchor_score(point, positions[sheep_row], coverage[sheep_row], own_anchor, radius, weight)
			if score < best_score:
				best = sheep_row
				best_score = score
		anchor_rows[index] = best if current < 0 or best_score <= current_score * (1.0 - config.sheepdog.reassignment_improvement) else current
		if stats.detailed:
			stats.hotspots.DogAnchor += (Time.get_ticks_usec() - started_at) / 1000.0
			stats.calls.DogAnchor += 1
	self.stats = stats

func _apply_anchors() -> void:
	submit_stats(stats)
	for index in range(rows.size()):
		var row := rows[index]
		data.dog.protected_sheep[row] = data.index.handles[anchor_rows[index]] if anchor_rows[index] >= 0 else null
		data.dog.assignment_remaining[row] = g_gameplayEngine.config.sheepdog.reassignment_interval

static func _snapshot_anchor_score(point: Vector2, sheep_point: Vector2, coverage: int, own_anchor: Vector2, radius: float, weight: float) -> float:
	if own_anchor.distance_to(sheep_point) < radius:
		coverage -= 1
	return point.distance_to(sheep_point) / radius + coverage * weight

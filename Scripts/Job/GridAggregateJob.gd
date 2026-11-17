class_name GridAggregateJob
extends Job

var flock_counts := PackedInt32Array()
var flock_sums := PackedVector2Array()
var alignment_counts := PackedInt32Array()
var alignment_sums := PackedVector2Array()
var nodes := PackedInt32Array()
var flock_offsets := PackedInt32Array()
var alignment_offsets := PackedInt32Array()

func execute() -> void:
	if snapshot != null:
		var started := Time.get_ticks_usec()
		grid = GridService.build_snapshot(snapshot, not snapshot.gpu)
		execute_ms = (Time.get_ticks_usec() - started) / 1000.0
		return

	var cells := rows
	var counts: PackedInt32Array = grid.counts
	var position_sums: PackedVector2Array = grid.position_sums
	var velocity_sums: PackedVector2Array = grid.velocity_sums
	var columns: int = grid.width
	var height: int = grid.height

	flock_counts.resize(cells.size())
	flock_sums.resize(cells.size())
	alignment_counts.resize(cells.size())
	alignment_sums.resize(cells.size())

	nodes.clear()
	for index in range(cells.size()):
		var cell := cells[index]
		var x := cell % columns
		var y := cell / columns
		if counts[cell * 3 + AnimalEntity.Kind.SHEEP] >= GridService.PRESSURE_SHARED_MIN_SHEEP:
			var base := int(y) * (columns + 1) + x
			for node in [base, base + 1, base + columns + 1, base + columns + 2]:
				nodes.append(node)

		var count := 0
		var sum := Vector2.ZERO
		for offset in range(0, flock_offsets.size(), 2):
			var nx := x + flock_offsets[offset]
			var ny := y + flock_offsets[offset + 1]
			if nx >= 0 and nx < columns and ny >= 0 and ny < height:
				var neighbor := ny * columns + nx
				count += counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
				sum += position_sums[neighbor]
		flock_counts[index] = count
		flock_sums[index] = sum

		count = 0
		sum = Vector2.ZERO
		for offset in range(0, alignment_offsets.size(), 2):
			var nx := x + alignment_offsets[offset]
			var ny := y + alignment_offsets[offset + 1]
			if nx >= 0 and nx < columns and ny >= 0 and ny < height:
				var neighbor := ny * columns + nx
				count += counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
				sum += velocity_sums[neighbor]
		alignment_counts[index] = count
		alignment_sums[index] = sum

func apply_result() -> void:
	if snapshot != null:
		target.apply_grid(grid, snapshot, null, execute_ms)
		return

	target.apply_cells(self)

func release_input() -> void:
	super.release_input()
	flock_offsets = PackedInt32Array()
	alignment_offsets = PackedInt32Array()

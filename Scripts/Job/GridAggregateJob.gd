class_name GridAggregateJob
extends Job

var flock_counts := PackedInt32Array()
var flock_sums := PackedVector2Array()
var alignment_counts := PackedInt32Array()
var alignment_sums := PackedVector2Array()
var nodes := PackedInt32Array()
var grid: Dictionary = {}

func execute() -> void:
	if context.has("version"):
		var started := Time.get_ticks_usec()
		grid = GridService.build_snapshot(context, not context.get("gpu", false))
		execute_ms = (Time.get_ticks_usec() - started) / 1000.0
		return

	var cells := rows
	var counts: PackedInt32Array = context.counts
	var position_sums: PackedVector2Array = context.position_sums
	var velocity_sums: PackedVector2Array = context.velocity_sums
	var flock_offsets: PackedInt32Array = context.flock_offsets
	var alignment_offsets: PackedInt32Array = context.alignment_offsets
	var columns: int = context.width
	var height: int = context.height

	flock_counts.resize(cells.size())
	flock_sums.resize(cells.size())
	alignment_counts.resize(cells.size())
	alignment_sums.resize(cells.size())

	nodes.clear()
	for index in range(cells.size()):
		var cell := cells[index]
		var x := cell % columns
		var y := cell / columns
		if counts[cell * 3 + AnimalEntity.Kind.SHEEP] >= context.shared_min_sheep:
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
	if context.has("version"):
		context.grid_ms = execute_ms
		target.apply_grid(grid, context)
		return

	target.apply_cells(self)

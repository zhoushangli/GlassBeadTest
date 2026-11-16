class_name GridAggregateJob
extends Job

func execute() -> void:
	var output := result
	var cells := rows
	var counts: PackedInt32Array = context.counts
	var position_sums: PackedVector2Array = context.position_sums
	var velocity_sums: PackedVector2Array = context.velocity_sums
	var flock_offsets: PackedInt32Array = context.flock_offsets
	var alignment_offsets: PackedInt32Array = context.alignment_offsets
	var columns: int = context.width
	var height: int = context.height
	var local_counts: PackedInt32Array = output.get("flock_counts", PackedInt32Array())
	var local_sums: PackedVector2Array = output.get("flock_sums", PackedVector2Array())
	var aligned_counts: PackedInt32Array = output.get("alignment_counts", PackedInt32Array())
	var aligned_sums: PackedVector2Array = output.get("alignment_sums", PackedVector2Array())
	local_counts.resize(cells.size())
	local_sums.resize(cells.size())
	aligned_counts.resize(cells.size())
	aligned_sums.resize(cells.size())
	var nodes := PackedInt32Array()
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
		local_counts[index] = count
		local_sums[index] = sum
		count = 0
		sum = Vector2.ZERO
		for offset in range(0, alignment_offsets.size(), 2):
			var nx := x + alignment_offsets[offset]
			var ny := y + alignment_offsets[offset + 1]
			if nx >= 0 and nx < columns and ny >= 0 and ny < height:
				var neighbor := ny * columns + nx
				count += counts[neighbor * 3 + AnimalEntity.Kind.SHEEP]
				sum += velocity_sums[neighbor]
		aligned_counts[index] = count
		aligned_sums[index] = sum
	output.merge({"cells": cells, "flock_counts": local_counts, "flock_sums": local_sums,
		"alignment_counts": aligned_counts, "alignment_sums": aligned_sums, "nodes": nodes}, true)

func apply_result() -> void:
	target.apply_cells(result)

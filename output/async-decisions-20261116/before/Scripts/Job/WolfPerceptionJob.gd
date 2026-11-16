class_name WolfPerceptionJob
extends Job

func execute() -> void:
	target.calculate_batch(result, rows, context)

func apply_result() -> void:
	target.apply_batch(result, context.delta)

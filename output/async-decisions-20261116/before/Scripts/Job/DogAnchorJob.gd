class_name DogAnchorJob
extends Job

func execute() -> void:
	target.calculate_anchors(result, rows, context)

func apply_result() -> void:
	target.apply_anchors(result)

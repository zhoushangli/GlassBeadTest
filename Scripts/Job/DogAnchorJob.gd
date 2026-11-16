class_name DogAnchorJob
extends Job

var anchor_rows := PackedInt32Array()

func execute() -> void:
	target.calculate_anchors(self)

func apply_result() -> void:
	target.apply_anchors(self)

class_name DogAnchorJob
extends Job

var anchors := PackedInt32Array()
var coverage := PackedInt32Array()
var sheep := PackedInt32Array()

var anchor_rows := PackedInt32Array()

func execute() -> void:
	target.calculate_anchors(self)

func apply_result() -> void:
	target.apply_anchors(self)

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

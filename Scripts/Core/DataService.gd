class_name DataService
extends Service

class Spatial extends RefCounted:
	var current: GridSnapshot = GridSnapshot.new()
	var pressure: Pressure = Pressure.new()
	var version: int = 0
	var debug: SpatialDebug = SpatialDebug.new()

	func _init() -> void:
		current.cell_size = 30.0

class Pressure extends RefCounted:
	var wolf := PackedVector2Array()
	var dog := PackedVector2Array()
	var source_pairs: int = 0

class SpatialDebug extends RefCounted:
	var dog_snapshot: GridSnapshot
	var dog_region_coverage := PackedInt32Array()
	var dog_region_threats := PackedInt32Array()

class Decisions extends RefCounted:
	var config: SimulationConfig
	var update_elapsed: Dictionary = {}
	var requested: Dictionary = {}
	var applied: Dictionary = {}
	var waiting: Dictionary = {}
	var last_decision: Dictionary = {}

var animals: AnimalData = AnimalData.new()
var spatial: Spatial = Spatial.new()
var decisions: Decisions = Decisions.new()

func _shutdown() -> void:
	animals.clear()

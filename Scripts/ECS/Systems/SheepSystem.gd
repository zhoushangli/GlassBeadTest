class_name SheepSystem
extends RefCounted

var data: AnimalData

func _init(storage: AnimalData) -> void:
	data = storage

func receive_howl(animal: AnimalEntity, source: Vector2) -> void:
	var animal_sheep := data.sheep
	var row := animal.row
	animal_sheep.panic_revision[row] += 1
	animal_sheep.panic_source[row] = source
	animal_sheep.panic_strength[row] = 1.0 if g_gameplayEngine.config.sheep.panic_duration > 0.0 else 0.0

func get_debug_details(animal: AnimalEntity) -> String:
	var row := animal.row
	return "Neighbors %d | Wolf %.2f | Dog %.2f | Panic %.2f | Speed %.1f" % [data.sheep.neighbor_count[row], data.sheep.threat_strength[row], data.sheep.dog_pressure[row].length(), data.sheep.panic_strength[row], data.motion.velocity[row].length()]

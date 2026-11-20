@tool
extends BTCondition

@export var condition: StringName

var data: AnimalData
var animal: AnimalEntity

func _setup() -> void:
	data = g_gameplayEngine.data_service.animals
	animal = blackboard.get_var(&"animal", null)

func _generate_name() -> String:
	return "Check " + str(condition)

func _tick(_delta: float) -> Status:
	if data.live(animal) == null:
		return FAILURE

	var met := false
	match condition:
		&"has_threat":
			met = data.live(data.memory.target[animal.row]) != null
		&"has_nearby_dog":
			met = data.live(data.wolf.nearest_threat[animal.row]) != null
		&"needs_rest":
			met = data.wolf.resting[animal.row] or (data.wolf.retreating[animal.row] and data.live(data.wolf.nearest_threat[animal.row]) == null)
		&"has_lost_prey":
			met = data.wolf.hunting[animal.row] and not data.memory.target_visible[animal.row]
		&"has_prey":
			met = data.wolf.hunting[animal.row]
		&"can_charge":
			met = g_gameplayEngine.wolf_system.can_charge(animal)
		&"must_return":
			met = data.dog.returning[animal.row] != 0
		&"has_stray":
			met = data.live(data.dog.collected_sheep[animal.row]) != null
	return SUCCESS if met else FAILURE

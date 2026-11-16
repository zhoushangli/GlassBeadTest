@tool
extends BTCondition

@export var condition: StringName

var data: AnimalData

func _setup() -> void:
	data = g_gameplayEngine.entity_service.data

func _generate_name() -> String:
	return "Check " + str(condition)

func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE
	var animal := agent.entity as AnimalEntity
	if animal == null or animal.row < 0 or not data.identity_alive[animal.row]:
		return FAILURE
	var met := false
	match condition:
		&"has_threat":
			met = data.live(data.memory_target[animal.row]) != null
		&"has_nearby_dog":
			met = data.live(data.wolf_nearest_threat[animal.row]) != null
		&"needs_rest":
			met = data.wolf_resting[animal.row] or (data.wolf_retreating[animal.row] and data.live(data.wolf_nearest_threat[animal.row]) == null)
		&"has_lost_prey":
			met = data.wolf_hunting[animal.row] and not data.memory_target_visible[animal.row]
		&"has_prey":
			met = data.wolf_hunting[animal.row]
		&"can_charge":
			met = g_gameplayEngine.wolf_system.can_charge(animal)
		&"must_return":
			met = data.dog_returning[animal.row] != 0
		&"has_stray":
			met = data.live(data.dog_collected_sheep[animal.row]) != null
	return SUCCESS if met else FAILURE

@tool
extends BTAction

var behavior: AnimalEntity.Behavior = AnimalEntity.Behavior.FLOCK

var data: AnimalData

func _setup() -> void:
	data = g_gameplayEngine.entity_service.data

func _generate_name() -> String:
	return AnimalEntity.BEHAVIOR_NAMES[behavior]

func _tick(delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE
	var animal := agent.entity as AnimalEntity
	if animal == null or animal.row < 0 or not data.identity_alive[animal.row]:
		return FAILURE
	data.brain_current_behavior[animal.row] = behavior
	_execute(delta)
	return RUNNING

func _execute(_delta: float) -> void:
	pass

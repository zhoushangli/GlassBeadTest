@tool
extends BTAction

var behavior: AnimalEntity.Behavior = AnimalEntity.Behavior.FLOCK

func _generate_name() -> String:
	return AnimalEntity.BEHAVIOR_NAMES[behavior]

func _tick(delta: float) -> Status:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	if not is_instance_valid(agent) or not data.identity_alive[agent.entity.row]:
		return FAILURE
	data.brain_current_behavior[agent.entity.row] = behavior
	_execute(delta)
	return RUNNING

func _execute(_delta: float) -> void:
	pass

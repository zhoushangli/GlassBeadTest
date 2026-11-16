@tool
extends BTAction

var behavior: AnimalController.Behavior = AnimalController.Behavior.FLOCK

func _generate_name() -> String:
	return AnimalController.BEHAVIOR_NAMES[behavior]

func _tick(delta: float) -> Status:
	if not is_instance_valid(agent) or not agent.alive:
		return FAILURE
	agent.set_behavior(behavior)
	_execute(delta)
	return RUNNING

func _execute(_delta: float) -> void:
	pass

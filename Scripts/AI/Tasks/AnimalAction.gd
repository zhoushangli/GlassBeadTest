@tool
extends BTAction

@export var behavior: AnimalController.Behavior = AnimalController.Behavior.FLOCK

func _generate_name() -> String:
	return AnimalController.BEHAVIOR_NAMES[behavior]

func _tick(delta: float) -> Status:
	if not is_instance_valid(agent) or not agent.alive:
		return FAILURE
	agent.perform_behavior(behavior, delta)
	return RUNNING

func _exit() -> void:
	if is_instance_valid(agent):
		agent.finish_behavior(behavior)

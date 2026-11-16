@tool
extends BTCondition

@export var condition: StringName

func _generate_name() -> String:
	return "Check " + str(condition)

func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent) or not agent.alive:
		return FAILURE
	return SUCCESS if agent.call(condition) else FAILURE

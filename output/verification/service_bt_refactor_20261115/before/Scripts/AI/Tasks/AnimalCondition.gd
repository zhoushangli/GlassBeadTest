@tool
extends BTCondition

@export var fact: StringName

func _generate_name() -> String:
	return "Check " + str(fact)

func _tick(_delta: float) -> Status:
	if blackboard.get_var(fact, false):
		return SUCCESS
	return FAILURE

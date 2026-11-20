@tool
extends BTAction

var behavior: AnimalEntity.Behavior = AnimalEntity.Behavior.FLOCK

var data: AnimalData
var animal: AnimalEntity

func _setup() -> void:
	# Bind the per-instance handle rather than the shared EntityService Node used as the BT agent.
	# e.g. pooled-tree initialization reads the new animal from its own blackboard.
	data = g_gameplayEngine.data_service.animals
	animal = blackboard.get_var(&"animal", null)

func _generate_name() -> String:
	return AnimalEntity.BEHAVIOR_NAMES[behavior]

func _tick(delta: float) -> Status:
	if data.live(animal) == null:
		return FAILURE

	data.brain.current_behavior[animal.row] = behavior
	_execute(delta)
	return RUNNING

func _execute(_delta: float) -> void:
	pass

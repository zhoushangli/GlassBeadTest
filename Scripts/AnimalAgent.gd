class_name AnimalAgent
extends Node2D

@onready var bt_player: BTPlayer = $BTPlayer

var entity: AnimalEntity

func reset_tree() -> void:
	if bt_player == null:
		return

	bt_player.restart()
	bt_player.active = false
	var blackboard := bt_player.get_blackboard()
	for key in blackboard.list_vars():
		blackboard.erase_var(key)

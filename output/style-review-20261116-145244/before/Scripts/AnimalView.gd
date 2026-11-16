class_name AnimalView
extends Node2D

@export var base_color := Color("#b8d94b")
@export var behavior_colors: Dictionary = {}
@export var vision_color := Color(0.7, 0.8, 0.7, 0.08)
@export var debug_line_width: float = 1.0
@export_range(0.1, 3.0, 0.1) var howl_visual_duration: float = 0.8
@export var howl_color := Color(1.0, 0.65, 0.2, 0.65)

@onready var sprite: Sprite2D = $Sprite2D
@onready var bt_player: BTPlayer = get_node_or_null("BTPlayer")

var entity: AnimalEntity
var _last_behavior: int = -1
var _last_alive: bool = true

func sync() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	if global_position != data.motion_position[entity.row]:
		global_position = data.motion_position[entity.row]
	var angle := data.motion_facing[entity.row].angle() + PI * 0.5
	if not is_equal_approx(sprite.rotation, angle):
		sprite.rotation = angle
	if data.identity_kind[entity.row] == AnimalEntity.Kind.SHEEP:
		var danger := maxf(data.sheep_threat_strength[entity.row], data.sheep_panic_strength[entity.row])
		var color: Color = behavior_colors.get("Flock", base_color)
		color = color.lerp(behavior_colors.get("Herded", base_color), minf(1.0, data.sheep_dog_pressure[entity.row].length()))
		color = color.lerp(behavior_colors.get("Flee", base_color), danger)
		sprite.self_modulate = color if data.identity_alive[entity.row] else Color("#7b8794")
		return
	var behavior := data.brain_current_behavior[entity.row]
	var alive: bool = data.identity_alive[entity.row] != 0
	if behavior != _last_behavior or alive != _last_alive:
		sprite.self_modulate = behavior_colors.get(AnimalEntity.BEHAVIOR_NAMES[behavior], base_color) if alive else Color("#7b8794")
		_last_behavior = behavior
		_last_alive = alive

func reset_tree() -> void:
	if bt_player == null:
		return
	bt_player.restart()
	bt_player.active = false
	var blackboard := bt_player.get_blackboard()
	for key in blackboard.list_vars():
		blackboard.erase_var(key)

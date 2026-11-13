extends Node2D

@export var simulation_config: SimulationConfig
@onready var world: Node2D = $World
@onready var hud: DebugHUD = $DebugHUD


func _ready() -> void:
	# 1) 场地和 HUD 就绪后再启动服务与模拟
	var size := simulation_config.arena_size
	$World/Ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	$Camera2D.position = size * 0.5
	var texture := preload("res://Art/Placeholder/TEX_WhiteCircle.svg")
	for point in simulation_config.grass_positions:
		var patch := Sprite2D.new()
		patch.texture = texture
		patch.position = point
		patch.scale = Vector2.ONE * (simulation_config.grass_radius / 28.0)
		patch.self_modulate = Color("#294b32")
		$World/Grass.add_child(patch)
	g_gameplayEngine.start_simulation(world, hud, simulation_config)


func _exit_tree() -> void:
	if is_instance_valid(g_gameplayEngine):
		g_gameplayEngine.stop_simulation()

extends Node2D

@export var simulation_config: SimulationConfig
@onready var world: Node2D = $World
@onready var hud: DebugHUD = $DebugHUD

func _ready() -> void:
	# 1) 场地和 HUD 就绪后再启动服务与模拟。
	g_gameplayEngine.configuration_applied.connect(_refresh_world)
	g_gameplayEngine.start_simulation(world, hud, simulation_config)
	_refresh_world(false)

func _refresh_world(_restarted: bool) -> void:
	var size: Vector2 = g_gameplayEngine.config.arena_size
	$World/Ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	$Camera2D.position = size * 0.5

func _exit_tree() -> void:
	if is_instance_valid(g_gameplayEngine):
		g_gameplayEngine.stop_simulation()

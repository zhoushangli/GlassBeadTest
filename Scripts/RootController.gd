extends Node2D

@export var simulation_config: SimulationConfig

@onready var world: Node2D = $World
@onready var hud: DebugHUD = $DebugHUD
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	# 1) 场地和 HUD 就绪后再启动服务与模拟。
	g_gameplayEngine.configuration_applied.connect(_refresh_world)
	g_gameplayEngine.start_simulation(world, hud, simulation_config)
	get_viewport().size_changed.connect(_refresh_camera)
	_refresh_world(false)

func _refresh_world(_restarted: bool) -> void:
	var size: Vector2 = g_gameplayEngine.config.arena_size
	$World/Ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	_refresh_camera()

func _refresh_camera() -> void:
	var size: Vector2 = g_gameplayEngine.config.arena_size
	var viewport_size := get_viewport_rect().size
	camera.position = size * 0.5
	camera.zoom = Vector2.ONE * minf(viewport_size.x / size.x, viewport_size.y / size.y)

func _exit_tree() -> void:
	if is_instance_valid(g_gameplayEngine):
		g_gameplayEngine.stop_simulation()

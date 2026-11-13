extends Node2D

@export var simulation_config: SimulationConfig
@onready var world: Node2D = $World
@onready var hud: DebugHUD = $DebugHUD
var grass_visuals: Array[Polygon2D] = []


func _ready() -> void:
	# 1) 场地和 HUD 就绪后再启动服务与模拟
	g_gameplayEngine.grass_reset.connect(_rebuild_grass)
	g_gameplayEngine.grass_changed.connect(_refresh_grass)
	g_gameplayEngine.start_simulation(world, hud, simulation_config)


func _rebuild_grass() -> void:
	var settings: SimulationConfig = g_gameplayEngine.config
	var size := settings.arena_size
	$World/Ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	$Camera2D.position = size * 0.5

	for child in $World/Grass.get_children():
		$World/Grass.remove_child(child)
		child.queue_free()
	grass_visuals.clear()

	var texture := preload("res://Art/Placeholder/TEX_WhiteCircle.svg")
	for point in settings.grass.positions:
		var patch := Sprite2D.new()
		patch.texture = texture
		patch.position = point
		patch.scale = Vector2.ONE * (settings.grass.patch_radius / 28.0)
		patch.self_modulate = Color("#294b32")
		$World/Grass.add_child(patch)

	for point in g_gameplayEngine.grass_positions:
		var grass := Polygon2D.new()
		grass.polygon = PackedVector2Array([
			Vector2(-6, 5), Vector2(-8, -4), Vector2(-3, -1), Vector2(0, -9),
			Vector2(3, -1), Vector2(8, -4), Vector2(6, 5)])
		grass.position = point
		$World/Grass.add_child(grass)
		grass_visuals.append(grass)
		_refresh_grass(grass_visuals.size() - 1)


func _refresh_grass(index: int) -> void:
	var grass := grass_visuals[index]
	var remaining: int = g_gameplayEngine.grass_bites[index]
	var amount := float(remaining) / g_gameplayEngine.config.grass.bites
	grass.visible = remaining > 0
	grass.color = Color("#5c863d").lerp(Color("#84c95a"), amount)
	grass.scale = Vector2.ONE * lerpf(0.6, 1.0, amount)


func _exit_tree() -> void:
	if is_instance_valid(g_gameplayEngine):
		g_gameplayEngine.stop_simulation()

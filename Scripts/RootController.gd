extends Node2D

const CAMERA_MOVE_SPEED: float = 700.0
const CAMERA_ZOOM_STEP: float = 1.2
const CAMERA_MAX_ZOOM_FACTOR: float = 16.0

@export var simulation_config: SimulationConfig

@onready var world: Node2D = $World
@onready var hud: DebugHUD = $DebugHUD
@onready var camera: Camera2D = $Camera2D

var _camera_fit_zoom: float = 1.0

func _ready() -> void:
	# 1) 场地和 HUD 就绪后再启动服务与模拟。
	g_gameplayEngine.configuration_applied.connect(_refresh_world)
	g_gameplayEngine.start_simulation(world, hud, simulation_config)
	get_viewport().size_changed.connect(_refresh_camera)
	_refresh_world(false)

func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return

	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if direction.is_zero_approx():
		return

	# 1) 按屏幕像素速度平移，避免缩放后移动过快或斜向加速。
	camera.position += direction.normalized() * CAMERA_MOVE_SPEED * delta / camera.zoom.x
	_clamp_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		# 1) 按当前缩放换算拖动距离，让场景跟随鼠标移动。
		camera.position -= event.relative / camera.zoom
		_clamp_camera()
		get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton or not event.pressed:
		return

	var factor: float
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			factor = CAMERA_ZOOM_STEP
		MOUSE_BUTTON_WHEEL_DOWN:
			factor = 1.0 / CAMERA_ZOOM_STEP
		_:
			return

	# 1) 缩放后补偿鼠标世界坐标，让鼠标指向的位置保持稳定。
	camera.force_update_scroll()
	var point := get_global_mouse_position()
	var zoom := clampf(camera.zoom.x * factor, _camera_fit_zoom, _camera_fit_zoom * CAMERA_MAX_ZOOM_FACTOR)
	camera.zoom = Vector2.ONE * zoom
	camera.force_update_scroll()
	camera.position += point - get_global_mouse_position()
	_clamp_camera()
	get_viewport().set_input_as_handled()

func _refresh_world(_restarted: bool) -> void:
	var size: Vector2 = g_gameplayEngine.config.arena_size
	$World/Ground.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	_refresh_camera()

func _refresh_camera() -> void:
	var size: Vector2 = g_gameplayEngine.config.arena_size
	var viewport_size := get_viewport_rect().size
	_camera_fit_zoom = minf(viewport_size.x / size.x, viewport_size.y / size.y)
	camera.position = size * 0.5
	camera.zoom = Vector2.ONE * _camera_fit_zoom

func _clamp_camera() -> void:
	var size: Vector2 = g_gameplayEngine.config.arena_size

	# 视野大于场地的轴保持居中，其余轴限制视野边缘不越出场地。
	# e.g. 全场景缩放时中心为 size * 0.5，放大后才能沿对应轴移动。
	var margin := (get_viewport_rect().size / camera.zoom * 0.5).min(size * 0.5)
	camera.position = camera.position.clamp(margin, size - margin)
	camera.force_update_scroll()

func _exit_tree() -> void:
	if is_instance_valid(g_gameplayEngine):
		g_gameplayEngine.stop_simulation()

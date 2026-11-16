class_name DebugService
extends Service

var hud: DebugHUD
var hud_enabled: bool = true
var overlay_enabled: bool = true
var selected: AnimalController
var show_details: bool = false

func _startup() -> void:
	clear_selection()
	hud.initialize(g_gameplayEngine)

func _reset() -> void:
	clear_selection()

func _shutdown() -> void:
	clear_selection()
	hud = null

func _process(_delta: float) -> void:
	if not started or not g_gameplayEngine.running:
		return
	if overlay_enabled:
		refresh()
	if hud_enabled and is_instance_valid(hud):
		var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.performance_stats_enabled else 0
		hud.refresh()
		if g_gameplayEngine.profile_service.performance_stats_enabled:
			g_gameplayEngine.profile_service.record_debug_time("HUDRefresh", started)

func _unhandled_input(event: InputEvent) -> void:
	if not started or not g_gameplayEngine.running:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return

		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var amount := 10 if event.shift_pressed else 1
		match key:
			KEY_1:
				g_gameplayEngine.request_spawn(AnimalController.Kind.SHEEP, amount)
			KEY_2:
				g_gameplayEngine.request_spawn(AnimalController.Kind.WOLF, amount)
			KEY_3:
				g_gameplayEngine.request_spawn(AnimalController.Kind.SHEEPDOG, amount)
			KEY_SPACE:
				g_gameplayEngine.paused = not g_gameplayEngine.paused
			KEY_N:
				g_gameplayEngine.request_single_step()
			KEY_R:
				g_gameplayEngine.request_reset()
			KEY_F1:
				show_details = not show_details
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()

func select_at(point: Vector2) -> void:
	selected = null
	var nearest_distance: float = 19.0
	for animal in g_gameplayEngine.entity_service.entities:
		if animal.alive:
			var distance := point.distance_to(animal.global_position)
			if distance < nearest_distance:
				selected = animal
				nearest_distance = distance
	queue_redraw()

func clear_selection() -> void:
	selected = null
	queue_redraw()

func clear_invalid_selection() -> void:
	if not is_instance_valid(selected) or not selected.alive:
		selected = null

func refresh() -> void:
	clear_invalid_selection()
	queue_redraw()

func selection_text() -> String:
	if not is_instance_valid(selected):
		return "Click an animal to inspect its behavior and target."
	var target_text := "none"
	if selected.is_live(selected.target):
		target_text = "%s #%d" % [AnimalController.KIND_NAMES[selected.target.kind], selected.target.entity_id]
	var text := "%s #%d  |  %s  |  Target: %s" % [
		AnimalController.KIND_NAMES[selected.kind], selected.entity_id,
		AnimalController.BEHAVIOR_NAMES[selected.current_behavior], target_text]
	var details := selected.get_debug_details()
	if not details.is_empty():
		text += "  |  " + details
	return text

func _draw() -> void:
	if not started or not g_gameplayEngine.running or not overlay_enabled:
		return

	var started := Time.get_ticks_usec() if g_gameplayEngine.profile_service.performance_stats_enabled else 0
	if show_details:
		for animal in g_gameplayEngine.entity_service.entities:
			if animal.alive and animal.is_live(animal.target):
				draw_line(animal.global_position, animal.last_seen_position, Color(animal.base_color, 0.4), 1.0, true)

	if is_instance_valid(selected) and selected.alive:
		draw_arc(selected.global_position, 17.0, 0.0, TAU, 40, Color("#f4f7ed"), 2.0, true)
		if show_details:
			var half_angle := deg_to_rad(selected.movement_config.vision_angle * 0.5)
			var direction := selected.facing.angle()
			var points := PackedVector2Array([selected.global_position])
			for index in range(33):
				points.append(selected.global_position + Vector2.from_angle(direction - half_angle + 2.0 * half_angle * index / 32.0) * selected.perception_radius)
			draw_colored_polygon(points, Color(selected.base_color, 0.08))
			draw_arc(selected.global_position, selected.perception_radius, direction - half_angle, direction + half_angle, 40, Color(selected.base_color, 0.5), 1.0, true)
			draw_line(selected.global_position, points[1], Color(selected.base_color, 0.5))
			draw_line(selected.global_position, points[-1], Color(selected.base_color, 0.5))
			draw_line(selected.global_position, selected.movement_goal, Color("#f4f7ed"), 1.0, true)
			draw_circle(selected.movement_goal, 4.0, Color("#f4f7ed"))
			if selected is SheepdogController:
				var dog := selected as SheepdogController
				draw_arc(dog.protection_center, dog.settings.local_flock_radius, 0.0, TAU, 72, Color("#93c5fd"), 1.0, true)
	if g_gameplayEngine.profile_service.performance_stats_enabled:
		g_gameplayEngine.profile_service.record_debug_time("OverlayDrawCPUTime", started)

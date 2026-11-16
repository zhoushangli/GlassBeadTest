class_name DebugService
extends Service

var hud: DebugHUD
var hud_enabled: bool = true
var overlay_enabled: bool = true

var _selected: AnimalEntity
var selected: AnimalEntity:
	get:
		return g_gameplayEngine.entity_service.data.live(_selected)
	set(value):
		_selected = value

var show_details: bool = false:
	set(value):
		show_details = value
		if not value:
			howl_events.clear()
		queue_redraw()
var selected_only: bool = true
var visual_options: Dictionary[String, bool] = {
	"wolf_vision": true, "dog_vision": true,
	"tracking": true, "memory": true, "movement": true,
	"protection": true, "howl": true,
}

var howl_events: Array[Dictionary] = []

func _startup() -> void:
	clear_selection()
	hud.initialize(g_gameplayEngine)

func _reset() -> void:
	clear_selection()
	howl_events.clear()

func _shutdown() -> void:
	clear_selection()
	howl_events.clear()
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
				g_gameplayEngine.request_spawn(AnimalEntity.Kind.SHEEP, amount)
			KEY_2:
				g_gameplayEngine.request_spawn(AnimalEntity.Kind.WOLF, amount)
			KEY_3:
				g_gameplayEngine.request_spawn(AnimalEntity.Kind.SHEEPDOG, amount)
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
	var data: AnimalData = g_gameplayEngine.entity_service.data
	selected = null
	var nearest_distance: float = 19.0
	for animal in g_gameplayEngine.entity_service.entities:
		if data.identity_alive[animal.row]:
			var distance := point.distance_to(data.motion_position[animal.row])
			if distance < nearest_distance:
				selected = animal
				nearest_distance = distance
	queue_redraw()

func clear_selection() -> void:
	selected = null
	queue_redraw()

func clear_invalid_selection() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	if not is_instance_valid(selected) or not data.identity_alive[selected.row]:
		selected = null

func refresh() -> void:
	clear_invalid_selection()
	queue_redraw()

func selection_text() -> String:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	if not is_instance_valid(selected):
		return "Click an animal to inspect its behavior and target."
	if data.identity_kind[selected.row] == AnimalEntity.Kind.SHEEP:
		return "Sheep #%d | %s" % [data.identity_entity_id[selected.row], g_gameplayEngine.debug_details(selected)]
	var target_text := "none"
	if g_gameplayEngine.animal_system.is_live(selected, data.live(data.memory_target[selected.row])):
		target_text = "%s #%d" % [AnimalEntity.KIND_NAMES[data.identity_kind[data.live(data.memory_target[selected.row]).row]], data.identity_entity_id[data.live(data.memory_target[selected.row]).row]]
	var text := "%s #%d  |  %s  |  Target: %s" % [
		AnimalEntity.KIND_NAMES[data.identity_kind[selected.row]], data.identity_entity_id[selected.row],
		AnimalEntity.BEHAVIOR_NAMES[data.brain_current_behavior[selected.row]], target_text]
	var details: String = g_gameplayEngine.debug_details(selected)
	if not details.is_empty():
		text += "  |  " + details
	return text

func set_visual_option(key: String, value: bool) -> void:
	visual_options[key] = value
	if key == "howl" and not value:
		howl_events.clear()
	queue_redraw()

func record_howl(animal: AnimalEntity) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	if not overlay_enabled or not show_details or not visual_options["howl"]:
		return
	if selected_only and selected != animal:
		return

	var view := data.brain_view[row]
	howl_events.append({
		"position": data.motion_position[row], "radius": data.settings[row].howl_radius,
		"duration": view.howl_visual_duration, "elapsed": 0.0,
		"color": view.howl_color, "id": data.identity_entity_id[row],
		"uid": animal.uid,
	})

func advance_visuals(delta: float) -> void:
	if not overlay_enabled or not show_details or not visual_options["howl"]:
		howl_events.clear()
		return

	for index in range(howl_events.size() - 1, -1, -1):
		howl_events[index]["elapsed"] += delta
		if howl_events[index]["elapsed"] >= howl_events[index]["duration"]:
			howl_events.remove_at(index)

func _draw() -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	if not started or not g_gameplayEngine.running or not overlay_enabled:
		return

	var started_at := Time.get_ticks_usec() if g_gameplayEngine.profile_service.performance_stats_enabled else 0
	if selected != null:
		draw_arc(data.motion_position[selected.row], 17.0, 0.0, TAU, 40, Color("#f4f7ed"), 2.0, true)
	if show_details:
		if selected_only:
			if selected != null:
				_draw_animal(selected)
		else:
			for animal in g_gameplayEngine.entity_service.entities:
				if animal.enabled and data.identity_alive[animal.row]:
					_draw_animal(animal)
		if visual_options["howl"]:
			for event in howl_events:
				if selected_only and (selected == null or selected.uid != event["uid"]):
					continue

				var progress: float = clampf(event["elapsed"] / event["duration"], 0.0, 1.0)
				var color: Color = event["color"]
				color.a *= 1.0 - progress
				draw_circle(event["position"], event["radius"], Color(color, color.a * 0.08))
				draw_arc(event["position"], event["radius"], 0.0, TAU, 48, Color(color, color.a * 0.4), 1.0, true)
				draw_arc(event["position"], event["radius"] * progress, 0.0, TAU, 48, color, 2.0, true)
	if g_gameplayEngine.profile_service.performance_stats_enabled:
		g_gameplayEngine.profile_service.record_debug_time("OverlayDrawCPUTime", started_at)

func _draw_animal(animal: AnimalEntity) -> void:
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var row := animal.row
	var point := data.motion_position[row]
	var view := data.brain_view[row]
	var width := view.debug_line_width
	var vision_key: String = ["", "wolf_vision", "dog_vision"][data.identity_kind[row]]
	if data.identity_kind[row] != AnimalEntity.Kind.SHEEP and visual_options[vision_key]:
		var half_angle: float = deg_to_rad(data.settings[row].vision_angle * 0.5)
		var radius: float = data.settings[row].perception_radius
		var direction := data.motion_facing[row].angle()
		var points := PackedVector2Array([point])
		for index in range(33):
			points.append(point + Vector2.from_angle(direction - half_angle + 2.0 * half_angle * index / 32.0) * radius)
		draw_colored_polygon(points, view.vision_color)
		var edge := Color(view.vision_color, 0.5)
		draw_arc(point, radius, direction - half_angle, direction + half_angle, 32, edge, width, true)
		draw_line(point, points[1], edge, width, true)
		draw_line(point, points[-1], edge, width, true)
	if data.live(data.memory_target[row]) != null:
		if visual_options["tracking"]:
			if data.memory_target_visible[row]:
				draw_line(point, data.memory_last_seen_position[row], Color(view.base_color, 0.5), width, true)
			else:
				draw_dashed_line(point, data.memory_last_seen_position[row], Color(view.base_color, 0.5), width, 6.0)
		if visual_options["memory"] and not data.memory_target_visible[row]:
			var remaining: float = clampf(1.0 - data.memory_unseen_elapsed[row] / maxf(data.settings[row].memory_duration, 0.00001), 0.0, 1.0)
			var color := Color(view.base_color, remaining)
			draw_arc(data.memory_last_seen_position[row], 7.0, 0.0, TAU, 20, color, width, true)
			draw_line(data.memory_last_seen_position[row] - Vector2(4, 0), data.memory_last_seen_position[row] + Vector2(4, 0), color, width)
			draw_line(data.memory_last_seen_position[row] - Vector2(0, 4), data.memory_last_seen_position[row] + Vector2(0, 4), color, width)
	if visual_options["movement"]:
		if not visual_options["tracking"] or data.live(data.memory_target[row]) == null or not data.motion_movement_goal[row].is_equal_approx(data.memory_last_seen_position[row]):
			draw_line(point, data.motion_movement_goal[row], Color("#f4f7ed"), width, true)
		draw_circle(data.motion_movement_goal[row], 3.0, Color("#f4f7ed"))
	if visual_options["protection"] and data.identity_kind[row] == AnimalEntity.Kind.SHEEPDOG:
		draw_arc(data.dog_protection_center[row], data.settings[row].local_flock_radius, 0.0, TAU, 48, Color("#93c5fd"), width, true)
		draw_circle(data.dog_protection_center[row], 4.0, Color("#93c5fd"))
		draw_circle(data.dog_guard_point[row], 4.0, Color("#93c5fd"), false, width, true)
		if data.live(data.dog_collected_sheep[row]) != null:
			draw_dashed_line(point, data.motion_position[data.live(data.dog_collected_sheep[row]).row], Color("#4de6b3"), width, 6.0)

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
	"fine_grid": false, "dog_regions": false,
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

	var visual: Dictionary = g_gameplayEngine.render_service.get_visual_settings(data.identity_kind[row])
	howl_events.append({
		"position": data.motion_position[row], "radius": data.settings[row].howl_radius,
		"duration": visual.howl_visual_duration, "elapsed": 0.0,
		"color": visual.howl_color, "id": data.identity_entity_id[row],
		"animal_id": animal.id,
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
		_draw_grids()
		if selected_only:
			if selected != null:
				_draw_animal(selected)
		else:
			for animal in g_gameplayEngine.entity_service.entities:
				if animal.enabled and data.identity_alive[animal.row]:
					_draw_animal(animal)
		if visual_options["howl"]:
			for event in howl_events:
				if selected_only and (selected == null or selected.id != event["animal_id"]):
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
	var visual: Dictionary = g_gameplayEngine.render_service.get_visual_settings(data.identity_kind[row])
	var width: float = visual.debug_line_width
	var vision_key: String = ["", "wolf_vision", "dog_vision"][data.identity_kind[row]]
	if data.identity_kind[row] != AnimalEntity.Kind.SHEEP and visual_options[vision_key]:
		var half_angle: float = deg_to_rad(data.settings[row].vision_angle * 0.5)
		var radius: float = data.settings[row].perception_radius
		var direction := data.motion_facing[row].angle()
		var points := PackedVector2Array([point])
		for index in range(33):
			points.append(point + Vector2.from_angle(direction - half_angle + 2.0 * half_angle * index / 32.0) * radius)
		draw_colored_polygon(points, visual.vision_color)
		var edge := Color(visual.vision_color, 0.5)
		draw_arc(point, radius, direction - half_angle, direction + half_angle, 32, edge, width, true)
		draw_line(point, points[1], edge, width, true)
		draw_line(point, points[-1], edge, width, true)

	if data.live(data.memory_target[row]) != null:
		if visual_options["tracking"]:
			if data.memory_target_visible[row]:
				draw_line(point, data.memory_last_seen_position[row], Color(visual.base_color, 0.5), width, true)
			else:
				draw_dashed_line(point, data.memory_last_seen_position[row], Color(visual.base_color, 0.5), width, 6.0)
		if visual_options["memory"] and not data.memory_target_visible[row]:
			var remaining: float = clampf(1.0 - data.memory_unseen_elapsed[row] / maxf(data.settings[row].memory_duration, 0.00001), 0.0, 1.0)
			var color := Color(visual.base_color, remaining)
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

func grid_status_text() -> String:
	var service: GridService = g_gameplayEngine.grid_service
	var lines := PackedStringArray()
	for entry in [["Fine", service.debug_snapshot], ["Regions", service.dog_debug_snapshot]]:
		var grid: GridSnapshot = entry[1]
		if grid != null:
			lines.append("%s t=%.2f | age %.0f ms" % [entry[0], grid.time, (Time.get_ticks_usec() - grid.captured_usec) / 1000.0])
	return "\n".join(lines)

func _draw_grid_lines(bounds: Rect2, size: float, color: Color, width: float) -> void:
	for x in range(ceili(bounds.position.x / size), floori(bounds.end.x / size) + 1):
		draw_line(Vector2(x * size, bounds.position.y), Vector2(x * size, bounds.end.y), color, width, true)
	for y in range(ceili(bounds.position.y / size), floori(bounds.end.y / size) + 1):
		draw_line(Vector2(bounds.position.x, y * size), Vector2(bounds.end.x, y * size), color, width, true)

func _draw_grids() -> void:
	if not visual_options["fine_grid"] and not visual_options["dog_regions"]:
		return

	var started_at := Time.get_ticks_usec()
	var service: GridService = g_gameplayEngine.grid_service
	var data: AnimalData = g_gameplayEngine.entity_service.data
	var transform := get_global_transform_with_canvas()
	var zoom := maxf(0.001, transform.get_scale().x)
	var bounds := (transform.affine_inverse() * get_viewport_rect()).intersection(Rect2(Vector2.ZERO, g_gameplayEngine.config.arena_size))
	var grid := service.debug_snapshot
	if visual_options["fine_grid"] and grid != null:
		var size := grid.cell_size
		for cell in grid.populated:
			var rectangle := Rect2(Vector2(cell % grid.width, floori(float(cell) / grid.width)) * size, Vector2.ONE * size)
			if bounds.intersects(rectangle):
				draw_rect(rectangle.intersection(bounds), Color(0.5, 0.8, 0.8, 0.10))
		_draw_grid_lines(bounds, size, Color(0.6, 0.85, 0.85, 0.28), 1.0 / zoom)
		if selected != null:
			var snapshot_row := grid.animal_ids.find(selected.id)
			if snapshot_row >= 0:
				var cell := grid.row_cells[snapshot_row]
				draw_rect(Rect2(Vector2(cell % grid.width, floori(float(cell) / grid.width)) * size, Vector2.ONE * size), Color("#f4f7ed"), false, 1.5 / zoom)

	grid = service.dog_debug_snapshot if service.dog_debug_snapshot != null else service.debug_snapshot
	if visual_options["dog_regions"] and grid != null:
		var size := grid.cell_size * 4.0
		var font := ThemeDB.fallback_font
		var font_size := ceili(9.0 / zoom)
		_draw_grid_lines(bounds, size, Color(0.35, 0.6, 1.0, 0.65), 1.2 / zoom)
		for region in grid.occupied_regions:
			var origin := Vector2(region % grid.region_width, floori(float(region) / grid.region_width)) * size
			var rectangle := Rect2(origin, Vector2.ONE * size).intersection(bounds)
			if not rectangle.has_area():
				continue

			var dogs := service.dog_region_coverage[region] if region < service.dog_region_coverage.size() else 0
			var threats := service.dog_region_threats[region] if region < service.dog_region_threats.size() else 0
			draw_rect(rectangle, Color(1.0, 0.3, 0.2, 0.18) if threats > 0 else Color(0.2, 0.5, 1.0, 0.06))
			draw_circle(grid.region_centers[region], 2.0 / zoom, Color("#93c5fd"))
			draw_string(font, origin + Vector2(2.0 / zoom, 11.0 / zoom), "%d/%d" % [grid.region_counts[region], dogs], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#dbeafe"))
		if selected != null and data.identity_kind[selected.row] == AnimalEntity.Kind.SHEEPDOG:
			var region := data.dog_region[selected.row]
			if region >= 0 and region < grid.region_counts.size():
				var rectangle := Rect2(Vector2(region % grid.region_width, floori(float(region) / grid.region_width)) * size, Vector2.ONE * size)
				draw_rect(rectangle, Color("#facc15"), false, 2.0 / zoom)
				draw_line(data.motion_position[selected.row], grid.region_centers[region], Color("#facc15"), 1.5 / zoom)
				draw_line(grid.region_centers[region], data.dog_protection_center[selected.row], Color("#93c5fd"), 1.0 / zoom)

	if g_gameplayEngine.profile_service.performance_stats_enabled:
		g_gameplayEngine.profile_service.record_duration("Debug/GridDrawCPU", (Time.get_ticks_usec() - started_at) / 1000.0)

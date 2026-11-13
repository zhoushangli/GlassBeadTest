class_name DebugService
extends Node2D

var gameplay_engine: Node
var selected: AnimalController
var show_details: bool = false


func initialize(engine: Node) -> void:
	gameplay_engine = engine
	clear_selection()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(gameplay_engine) or not gameplay_engine.running:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var amount := 10 if event.shift_pressed else 1
		match key:
			KEY_1:
				gameplay_engine.request_spawn(AnimalController.Kind.SHEEP, amount)
			KEY_2:
				gameplay_engine.request_spawn(AnimalController.Kind.WOLF, amount)
			KEY_3:
				gameplay_engine.request_spawn(AnimalController.Kind.SHEEPDOG, amount)
			KEY_SPACE:
				gameplay_engine.paused = not gameplay_engine.paused
			KEY_N:
				gameplay_engine.request_single_step()
			KEY_R:
				gameplay_engine.request_reset()
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
	for animal in gameplay_engine.entity_service.entities:
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
	if selected.supporting_hunt:
		text += "  |  Supporting hunt"
	if selected.current_behavior == AnimalController.Behavior.CAPTURE:
		text += "  |  Capture %.2f / %.2f s" % [selected.capture_progress, gameplay_engine.config.capture_duration]
	return text


func _draw() -> void:
	if not is_instance_valid(gameplay_engine) or not gameplay_engine.running:
		return

	if show_details:
		for animal in gameplay_engine.entity_service.entities:
			if animal.alive and animal.is_live(animal.target):
				draw_line(animal.global_position, animal.target.global_position, Color(animal.base_color, 0.4), 1.0, true)

	if is_instance_valid(selected) and selected.alive:
		draw_arc(selected.global_position, 17.0, 0.0, TAU, 40, Color("#f4f7ed"), 2.0, true)
		if show_details:
			draw_arc(selected.global_position, selected.perception_radius, 0.0, TAU, 72, Color(selected.base_color, 0.5), 1.0, true)
			draw_line(selected.global_position, selected.movement_goal, Color("#f4f7ed"), 1.0, true)
			draw_circle(selected.movement_goal, 4.0, Color("#f4f7ed"))
			if selected.kind == AnimalController.Kind.SHEEPDOG:
				draw_arc(selected.flock_center, gameplay_engine.config.protection_radius, 0.0, TAU, 72, Color("#93c5fd"), 1.0, true)

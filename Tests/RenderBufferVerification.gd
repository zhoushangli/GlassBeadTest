extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _compare(label: String) -> void:
	var data: AnimalData = engine.entity_service.data
	var render: RenderService = engine.render_service
	var expected: Array[PackedFloat32Array] = []
	var counts := Vector3i.ZERO
	for row in range(data.retained_count):
		counts[data.identity_kind[row]] += 1
	for kind in range(3):
		var buffer := render.buffers[kind].duplicate()
		buffer.resize(maxi(buffer.size(), counts[kind] * 12))
		var visual := render.get_visual_settings(kind)
		var colors := PackedColorArray()
		for name in AnimalEntity.BEHAVIOR_NAMES:
			colors.append(visual.behavior_colors.get(name, visual.base_color))
		var scale: Vector2 = visual.scale
		var index := 0
		for row in range(data.retained_count):
			if data.identity_kind[row] != kind:
				continue

			var point := data.motion_position[row]
			var facing := data.motion_facing[row].normalized()
			var color := colors[data.brain_current_behavior[row]]
			if not data.identity_alive[row]:
				color = Color("#7b8794")
			elif kind == AnimalEntity.Kind.SHEEP:
				color = colors[AnimalEntity.Behavior.FLOCK].lerp(colors[AnimalEntity.Behavior.HERDED], minf(1.0, data.sheep_dog_pressure[row].length()))
				color = color.lerp(colors[AnimalEntity.Behavior.FLEE], maxf(data.sheep_threat_strength[row], data.sheep_panic_strength[row]))
			buffer[index] = -facing.y * scale.x
			buffer[index + 1] = -facing.x * scale.y
			buffer[index + 3] = point.x
			buffer[index + 4] = facing.x * scale.x
			buffer[index + 5] = -facing.y * scale.y
			buffer[index + 7] = point.y
			buffer[index + 8] = color.r
			buffer[index + 9] = color.g
			buffer[index + 10] = color.b
			buffer[index + 11] = color.a
			index += 12

		expected.append(buffer)

	var state: int = engine.rng.state
	render.sync()
	for kind in range(3):
		_check(render.buffers[kind] == expected[kind], label + " full buffer matches three-pass reference including unused suffix")
		_check(render.instances[kind].multimesh.visible_instance_count == counts[kind], label + " visible count matches retained species")
		_check(render.buffers[kind].size() == render.instances[kind].multimesh.instance_count * 12, label + " stride and capacity match")
	_check(engine.rng.state == state, label + " rendering consumes no RNG")

func _run() -> void:
	var scene: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 0
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.paused = true
	var service: EntityService = engine.entity_service
	var data := service.data
	_compare("empty")
	for amount in [1, 12, 50]:
		for kind in range(3):
			service.spawn(kind, amount)
		for row in range(data.retained_count):
			data.motion_facing[row] = Vector2.ZERO if row % 4 == 0 else Vector2(3, 4)
			data.sheep_dog_pressure[row] = Vector2(row % 4 * 0.5, 0)
			data.sheep_threat_strength[row] = (row % 5) * 0.2
			data.sheep_panic_strength[row] = (row % 3) * 0.3
		_compare("mixed growth %d" % amount)
	service.capture(data.handles[service.sheep_rows[0]])
	service.remove_expired()
	_compare("compaction and visible corpse")
	service.remove_expired(10.0)
	_compare("expired corpse and hidden suffix")
	service.clear()
	_compare("clear retains capacity")
	service.spawn(AnimalEntity.Kind.SHEEPDOG, 7, Vector2(200, 300))
	_compare("single species after clear")
	engine.reset_simulation()
	_compare("reset hides all instances")
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	print("RENDER_BUFFER_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

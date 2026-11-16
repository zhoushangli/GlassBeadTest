extends SceneTree

var scene: Node
var engine: Node
var directory := "res://output/verification/behavior_v3_preview"

func _initialize() -> void:
	call_deferred("_run")

func _capture(name: String) -> void:
	engine.hud.refresh()
	engine.debug_service.refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(directory + "/" + name + ".png")
	print("PREVIEW ", name, " error=", error)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_physics_process(false)
	engine.paused = true
	for index in range(120):
		engine.simulate_step(1.0 / 60.0)
	engine.debug_service.show_details = true
	engine.debug_service.selected = engine.entity_service.dogs[0]
	await _capture("default_dog")
	engine.debug_service.selected = engine.entity_service.wolves[0]
	await _capture("default_wolf")
	engine.hud.parameters.toggle()
	engine.hud.parameters.tabs.current_tab = 2
	await _capture("wolf_config")
	engine.hud.parameters.close()
	engine.config.initial_sheep = 0
	engine.config.initial_wolves = 0
	engine.config.initial_sheepdogs = 0
	engine.reset_simulation()
	engine.paused = true
	var service: EntityService = engine.entity_service
	for point in [Vector2(480, 320), Vector2(510, 310), Vector2(490, 350), Vector2(700, 330)]:
		service.spawn(AnimalController.Kind.SHEEP, 1, point)
	var dog := service.spawn(AnimalController.Kind.SHEEPDOG, 1, Vector2(775, 330))[0] as SheepdogController
	dog.protected_sheep = service.sheep[0]
	dog._assignment_remaining = 100.0
	for index in range(3):
		for step in range(120):
			engine.simulate_step(1.0 / 60.0)
		engine.debug_service.selected = dog
		await _capture("collect_%d" % index)
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	quit()

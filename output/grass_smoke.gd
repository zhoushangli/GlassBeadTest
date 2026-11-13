extends SceneTree

var engine: Node
var meals: int = 0
var depleted: int = 0
var regrown: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _on_grass_changed(index: int) -> void:
	if engine.grass_bites[index] == engine.config.grass_bites:
		regrown += 1
	else:
		meals += 1
		if engine.grass_bites[index] == 0:
			depleted += 1

func _run() -> void:
	var scene: Node = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_physics_process(false)
	engine.grass_changed.connect(_on_grass_changed)
	for step in range(2400):
		engine.simulate_step(1.0 / 60.0)
		if step % 600 == 599:
			print("NATURAL_GRAZING sim=", engine.simulation_time, " meals=", meals, " depleted=", depleted, " regrown=", regrown)
			await process_frame
	engine.stop_simulation()
	scene.queue_free()
	await process_frame
	quit()

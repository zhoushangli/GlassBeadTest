extends SceneTree
var scene: Node
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	scene = load("res://Levels/Map/SCN_Root.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	root.get_node("g_gameplayEngine").stop_simulation()
	scene.queue_free()
	await process_frame
	await process_frame
	quit()

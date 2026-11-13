extends SceneTree


func _initialize() -> void:
	var settings := load("res://Resources/Gameplay/CFG_Simulation.tres") as SimulationConfig
	if OS.get_cmdline_user_args().has("--copy"):
		settings = settings.copy_config()
	if OS.get_cmdline_user_args().has("--save"):
		ResourceSaver.save(settings.copy_config(), "res://output/lifetime-preset.tres")
		settings = ResourceLoader.load("res://output/lifetime-preset.tres", "", ResourceLoader.CACHE_MODE_REPLACE) as SimulationConfig
	print(settings.sheep.move_speed)
	quit()

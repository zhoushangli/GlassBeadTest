extends SceneTree

class KeyLogger extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			print("KEY physical=", event.physical_keycode, " logical=", event.keycode, " pressed=", event.pressed, " echo=", event.echo)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child(load("res://Levels/Map/SCN_Root.tscn").instantiate())
	root.add_child(KeyLogger.new())
	DisplayServer.window_set_title("GlassBeadTest - Input verification")

extends SceneTree

func _initialize() -> void:
	call_deferred("_load_entry")

func _load_entry() -> void:
	var entry := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--entry="):
			entry = argument.trim_prefix("--entry=")
	if not entry.begins_with("res://") or not entry.ends_with(".gd"):
		push_error("Expected --entry=res://path/to/script.gd")
		quit(1)
		return
	var script := load(entry) as Script
	if script == null or not script.can_instantiate() or script.get_instance_base_type() != &"SceneTree":
		push_error("Entry must be a valid SceneTree script: " + entry)
		quit(1)
		return
	set_script(script)
	call("_initialize")

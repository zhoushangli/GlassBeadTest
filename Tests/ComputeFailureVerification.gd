extends SceneTree

class FailedDevice extends ComputeShaderService:
	var phase: String = "shader"

	func _supports_device() -> bool:
		return true

	func _initialize_device() -> void:
		if DisplayServer.get_name() == "headless":
			if phase in ["shader", "pipeline"]:
				_failure = "Injected %s creation failure" % phase
			return
		super._initialize_device()

	func _initialize_sheep_pipeline() -> String:
		return "Injected shader creation failure" if phase == "shader" else super._initialize_sheep_pipeline()

	func _initialize_movement_pipeline() -> String:
		return "Injected movement pipeline creation failure" if phase == "pipeline" else super._initialize_movement_pipeline()

	func execute_numeric_gpu(job: NumericComputeJob) -> PackedByteArray:
		if phase == "movement":
			job.error = "Injected movement execution failure"
			return PackedByteArray()
		return super.execute_numeric_gpu(job)

	func execute_gpu(job: SheepComputeJob) -> PackedByteArray:
		if phase == "readback":
			job.error = "Injected sheep readback failure"
			return PackedByteArray()
		return super.execute_gpu(job)

var engine: Node
var steps_at_failure: int = 0
var phase: String = "shader"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			phase = argument.trim_prefix("--phase=")
	engine = root.get_node("g_gameplayEngine")
	var device := FailedDevice.new()
	device.phase = phase
	engine.add_child(device)
	engine.compute_service = device
	var scene: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 24
	root.add_child(scene)
	engine.set_process(false)
	if not engine.step_failed:
		if phase == "readback":
			engine.animal_service.schedule_updates(1.0)
			var deadline := Time.get_ticks_msec() + 5000
			while not engine.step_failed and Time.get_ticks_msec() < deadline:
				engine.animal_service.apply_completed()
				OS.delay_msec(1)
		else:
			engine.simulate_step(1.0 / 30.0)

	steps_at_failure = engine.step_count
	var time_at_failure: float = engine.simulation_time
	var positions: PackedVector2Array = engine.entity_service.data.motion_position.duplicate()
	engine.simulate_step(1.0 / 30.0)
	engine.request_reset()
	engine._process(1.0)
	var stopped: bool = engine.step_failed and not engine.running and engine.step_count == steps_at_failure and engine.simulation_time == time_at_failure and engine.entity_service.data.motion_position == positions
	print("FATAL_VERIFICATION phase=%s stopped=%s debug=%s" % [phase, stopped, OS.is_debug_build()])
	if not stopped:
		push_error("FAIL: fatal compute failure must latch and stop simulation")
		quit(2)

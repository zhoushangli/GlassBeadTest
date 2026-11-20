extends SceneTree

var checks: int = 0
var failures: int = 0
var engine: Node
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _bindings(task: BTTask, expected: AnimalEntity) -> void:
	if task.get_script() != null:
		_check(task.get("animal") == expected, "task setup binds the current life handle")
	for index in range(task.get_child_count()):
		_bindings(task.get_child(index), expected)

func _lifecycle() -> void:
	var service: EntityService = engine.entity_service
	var data: AnimalData = engine.data_service.animals
	var sheep := service.spawn(AnimalEntity.Kind.SHEEP, 3, Vector2(500, 300))
	var wolves := service.spawn(AnimalEntity.Kind.WOLF, 2, Vector2(200, 300))
	var dogs := service.spawn(AnimalEntity.Kind.SHEEPDOG, 2, Vector2(700, 400))
	var pooled: Dictionary = {}
	for animal in wolves + dogs:
		var instance := data.brain.instance[animal.row]
		pooled[AnimalID.get_slot(animal.id)] = instance
		_check(instance.get_agent() == service and instance.get_blackboard().get_var(&"animal") == animal, "instances share only their service host")
		_bindings(instance.get_root_task(), animal)
	_check(service.get_child_count() == 0 and scene.get_node("World/Animals").get_child_count() == 3, "animals add no nodes beyond three shared renderers")
	_check(data.brain.instance[sheep[0].row] == null, "sheep retains no tree instance")
	var first := data.brain.instance[wolves[0].row]
	var second := data.brain.instance[wolves[1].row]
	first.get_blackboard().set_var(&"old_life", 123)
	_check(first != second and first.get_root_task() != second.get_root_task() and first.get_blackboard() != second.get_blackboard() and not second.get_blackboard().has_var(&"old_life"), "trees and blackboards are independent")
	var point := data.motion.wander_point[wolves[1].row]
	engine.animal_system.decide(wolves[0], 0.1)
	_check(data.motion.wander_point[wolves[1].row] == point, "one tree writes only its animal's motion intent")
	var dog := dogs[1]
	var instance := data.brain.instance[dog.row]
	service.capture(sheep[0])
	service.remove_expired()
	_check(dog.row == 0 and data.brain.instance[dog.row] == instance and instance.get_blackboard().get_var(&"animal") == dog, "row swaps preserve tree association")
	engine.reset_simulation()
	engine.paused = true
	_check(engine.data_service.animals.live(wolves[0]) == null and not first.get_blackboard().has_var(&"animal"), "reset aborts old context and invalidates handles")
	var replacement := service.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(250, 350))[0]
	var reused := data.brain.instance[replacement.row]
	_check(reused == pooled[AnimalID.get_slot(replacement.id)] and not reused.get_blackboard().has_var(&"old_life"), "pool reuses the instance with a clean blackboard")
	_bindings(reused.get_root_task(), replacement)
	engine.animal_system.decide(replacement, 0.1)
	_check(data.brain.current_behavior[replacement.row] == AnimalEntity.Behavior.PATROL, "reused instance starts a new life in patrol")
	var allocated := data.index.row_to_slot.size()
	service.spawn(AnimalEntity.Kind.WOLF, 100)
	_check(service.get_child_count() == 0 and scene.get_node("World/Animals").get_child_count() == 3 and data.index.row_to_slot.size() > allocated, "growing the brain pool does not grow SceneTree nodes")

func _release() -> void:
	var service: EntityService = engine.entity_service
	service.clear()
	var animal := service.spawn(AnimalEntity.Kind.WOLF, 1, Vector2(200, 300))[0]
	var reference: WeakRef = weakref(engine.data_service.animals.brain.instance[animal.row])
	service.clear()
	_check(reference.get_ref() == null and engine.data_service.animals.brain.instance.is_empty(), "clear breaks tree/task/storage reference cycles")

func _run() -> void:
	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	scene.simulation_config = scene.simulation_config.copy_config()
	scene.simulation_config.initial_total = 0
	root.add_child(scene)
	engine = root.get_node("g_gameplayEngine")
	engine.set_process(false)
	engine.paused = true
	_lifecycle()
	_release()
	engine.stop_simulation()
	_check(engine.data_service.animals.brain.instance.is_empty(), "shutdown releases all tree instances")
	scene.queue_free()
	await process_frame
	print("BRAIN_INSTANCE_VERIFICATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

class_name RenderService
extends Service

@export_group("Sheep")
@export var sheep_visual: Dictionary = {
	"texture": preload("res://Art/Placeholder/TEX_WhiteCircle.svg"), "scale": Vector2(0.4285714, 0.4285714),
	"base_color": Color(0.7215686, 0.8509804, 0.2941176, 1),
	"behavior_colors": {"Flock": Color(0.72, 0.85, 0.29, 1), "Herded": Color(0.4, 0.8, 1, 1), "Flee": Color(0.98, 0.8, 0.08, 1)},
	"vision_color": Color(0.7, 0.8, 0.7, 0.08), "debug_line_width": 1.0,
	"howl_visual_duration": 0.8, "howl_color": Color(1.0, 0.65, 0.2, 0.65),
}

@export_group("Wolf")
@export var wolf_visual: Dictionary = {
	"texture": preload("res://Art/Placeholder/TEX_WhiteTriangle.svg"), "scale": Vector2(0.4285714, 0.4285714),
	"base_color": Color(0.9372549, 0.3254902, 0.3137255, 1),
	"behavior_colors": {"Patrol": Color(0.94, 0.33, 0.31, 1), "Stalk": Color(1, 0.65, 0.2, 1),
		"Chase": Color(1, 0.25, 0.37, 1), "Search": Color(0.8, 0.5, 1, 1), "Retreat": Color(0.99, 0.65, 0.65, 1), "Rest": Color(0.5, 0.5, 0.6, 1)},
	"vision_color": Color(0.94, 0.33, 0.31, 0.08), "debug_line_width": 1.0,
	"howl_visual_duration": 0.8, "howl_color": Color(1.0, 0.65, 0.2, 0.65),
}

@export_group("Sheepdog")
@export var dog_visual: Dictionary = {
	"texture": preload("res://Art/Placeholder/TEX_WhiteSquare.svg"), "scale": Vector2(0.4285714, 0.4285714),
	"base_color": Color(0.2313725, 0.5098039, 0.9647059, 1),
	"behavior_colors": {"Patrol": Color(0.3, 0.6, 1, 1), "Collect": Color(0.3, 1, 0.7, 1), "Drive off": Color(0.8, 0.4, 1, 1), "Return": Color(0.6, 0.8, 1, 1)},
	"vision_color": Color(0.3, 0.6, 1, 0.08), "debug_line_width": 1.0,
	"howl_visual_duration": 0.8, "howl_color": Color(1.0, 0.65, 0.2, 0.65),
}

var container: Node2D
var instances: Array[MultiMeshInstance2D] = []
var buffers: Array[PackedFloat32Array] = []
var dirty: bool = false
var last_fill_ms: float = 0.0
var last_submit_ms: float = 0.0

var _visuals: Array[Dictionary] = []
var _colors: Array[PackedColorArray] = []

func _startup() -> void:
	_visuals = [sheep_visual, wolf_visual, dog_visual]
	for kind in range(3):
		var visual := _visuals[kind]
		var instance: MultiMeshInstance2D = MultiMeshInstance2D.new()
		instance.name = AnimalEntity.KIND_NAMES[kind] + "MultiMesh"
		instance.texture = visual.texture
		var half_size := instance.texture.get_size() * 0.5
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-half_size.x, -half_size.y, 0), Vector3(half_size.x, -half_size.y, 0), Vector3(half_size.x, half_size.y, 0), Vector3(-half_size.x, half_size.y, 0)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		instance.multimesh.use_colors = true
		instance.multimesh.mesh = mesh
		container.add_child(instance)
		instances.append(instance)
		buffers.append(PackedFloat32Array())
		var colors := PackedColorArray()
		for behavior in AnimalEntity.BEHAVIOR_NAMES:
			colors.append(visual.behavior_colors.get(behavior, visual.base_color))
		_colors.append(colors)
	mark_dirty()

func _reset() -> void:
	for instance in instances:
		instance.multimesh.visible_instance_count = 0
	last_fill_ms = 0.0
	last_submit_ms = 0.0
	mark_dirty()

func _shutdown() -> void:
	for instance in instances:
		instance.get_parent().remove_child(instance)
		instance.queue_free()
	instances.clear()
	buffers.clear()
	_visuals.clear()
	_colors.clear()
	container = null
	dirty = false

func mark_dirty() -> void:
	dirty = true

func get_visual_settings(kind: AnimalEntity.Kind) -> Dictionary:
	return _visuals[kind]

func sync() -> void:
	if not started:
		return

	var sync_started := Time.get_ticks_usec()
	var data: AnimalData = g_gameplayEngine.data_service.animals
	var animal_brain := data.brain
	var animal_identity := data.identity
	var animal_motion := data.motion
	var animal_sheep := data.sheep
	var animal_index := data.index
	var counts := Vector3i.ZERO
	for row in range(animal_index.retained_count):
		counts[animal_identity.kind[row]] += 1

	var fill_started := Time.get_ticks_usec()

	# Transfer the outer array reference before mutating reusable species buffers.
	# e.g. buffers = [] releases the service reference until frame_buffers is submitted.
	var frame_buffers: Array[PackedFloat32Array] = buffers
	buffers = []
	var scales := PackedVector2Array()
	for kind in range(3):
		var multimesh := instances[kind].multimesh
		if counts[kind] > multimesh.instance_count:
			multimesh.instance_count = counts[kind]
			frame_buffers[kind].resize(counts[kind] * 12)
		scales.append(_visuals[kind].scale)

	var positions := animal_motion.position
	var facings := animal_motion.facing
	var kinds := animal_identity.kind
	var alive := animal_identity.alive
	var behaviors := animal_brain.current_behavior
	var pressures := animal_sheep.dog_pressure
	var threats := animal_sheep.threat_strength
	var panic := animal_sheep.panic_strength
	var cursors := Vector3i.ZERO

	# 1) Fill all species buffers in one row traversal, preserving per-species order.
	for row in range(animal_index.retained_count):
		var kind := kinds[row]
		var buffer: PackedFloat32Array = frame_buffers[kind]
		var index := cursors[kind]
		var point := positions[row]
		var facing := facings[row].normalized()
		var scale := scales[kind]
		var colors := _colors[kind]
		var color := colors[behaviors[row]]
		if not alive[row]:
			color = Color("#7b8794")
		elif kind == AnimalEntity.Kind.SHEEP:
			color = colors[AnimalEntity.Behavior.FLOCK].lerp(colors[AnimalEntity.Behavior.HERDED], minf(1.0, pressures[row].length()))
			color = color.lerp(colors[AnimalEntity.Behavior.FLEE], maxf(threats[row], panic[row]))

		# Store the 2D transform and color in Godot's 12-float instance layout.
		# e.g. offsets 3 and 7 contain position.x and position.y; offsets 8 to 11 contain RGBA.
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
		cursors[kind] = index + 12

	last_fill_ms = (Time.get_ticks_usec() - fill_started) / 1000.0

	# 2) Submit each contiguous species buffer and retain unused capacity.
	var submit_started := Time.get_ticks_usec()
	for kind in range(3):
		var multimesh := instances[kind].multimesh
		if multimesh.instance_count > 0:
			multimesh.buffer = frame_buffers[kind]
		multimesh.visible_instance_count = counts[kind]

	buffers = frame_buffers
	last_submit_ms = (Time.get_ticks_usec() - submit_started) / 1000.0
	dirty = false

	var profile: ProfileService = g_gameplayEngine.profile_service
	profile.record_duration("Render/Sync", (Time.get_ticks_usec() - sync_started) / 1000.0)
	profile.record_duration("Render/Fill", last_fill_ms)
	profile.record_duration("Render/Submit", last_submit_ms)

class_name SimulationConfig
extends Resource

@export_group("World - restart required")
@export var arena_size := Vector2(1280.0, 720.0)
@export_range(0, 2147483647, 1) var random_seed: int = 1337
@export_range(0, 10000, 1) var initial_sheep: int = 240
@export_range(0, 10000, 1) var initial_wolves: int = 24
@export_range(0, 10000, 1) var initial_sheepdogs: int = 12

@export_group("Shared movement")
@export_range(0.0, 0.25, 0.005) var perception_interval: float = 0.125
@export_range(0.0, 80.0, 1.0) var separation_distance: float = 24.0
@export_range(0.0, 3.0, 0.05) var death_duration: float = 0.3

@export_group("Behavior resources")
@export var sheep: SheepConfig = SheepConfig.new()
@export var wolf: WolfConfig = WolfConfig.new()
@export var sheepdog: SheepdogConfig = SheepdogConfig.new()
@export var grass: GrassConfig = GrassConfig.new()


func copy_config() -> SimulationConfig:
	var result := duplicate(false) as SimulationConfig
	result.sheep = sheep.duplicate() as SheepConfig
	result.wolf = wolf.duplicate() as WolfConfig
	result.sheepdog = sheepdog.duplicate() as SheepdogConfig
	result.grass = grass.duplicate() as GrassConfig
	result.grass.positions = grass.positions.duplicate()
	return result


func get_sections() -> Dictionary:
	return {"World": self, "Sheep": sheep, "Wolves": wolf, "Dogs": sheepdog, "Grass": grass}


func requires_restart(previous: SimulationConfig) -> bool:
	return arena_size != previous.arena_size or random_seed != previous.random_seed \
		or initial_sheep != previous.initial_sheep or initial_wolves != previous.initial_wolves \
		or initial_sheepdogs != previous.initial_sheepdogs or grass.patch_radius != previous.grass.patch_radius \
		or grass.per_patch != previous.grass.per_patch or grass.bites != previous.grass.bites \
		or grass.positions != previous.grass.positions


func validate() -> String:
	if sheep == null or wolf == null or sheepdog == null or grass == null:
		return "The preset must include all four behavior resources."

	for section in get_sections().values():
		for property in section.get_property_list():
			if (property.usage & PROPERTY_USAGE_EDITOR) == 0 or property.hint != PROPERTY_HINT_RANGE:
				continue

			var value: float = float(section.get(property.name))
			var limits: PackedStringArray = property.hint_string.split(",")
			if not is_finite(value) or value < limits[0].to_float() or value > limits[1].to_float():
				return "Out of range: " + str(property.name).replace("_", " ")

	if not arena_size.is_finite() or arena_size.x < 128.0 or arena_size.y < 200.0:
		return "The arena must be at least 128 x 200."
	if sheep.full_threshold >= sheep.hungry_threshold:
		return "Full threshold must be below hungry threshold."
	if sheep.initial_hunger_min > sheep.initial_hunger_max:
		return "Initial hunger minimum must not exceed maximum."
	if sheep.emergency_distance > sheep.perception_radius:
		return "Sheep emergency distance must not exceed perception radius."
	if wolf.rest_duration_min > wolf.rest_duration_max:
		return "Rest duration minimum must not exceed maximum."

	for point in grass.positions:
		if not point.is_finite():
			return "Grass positions must be finite."
	return ""

class_name SimulationConfig
extends Resource

const PRESET_VERSION: int = 2

@export_storage var preset_version: int = 0

@export_group("World - restart required")
## 场地宽高，单位为像素；应用修改需要重启模拟，运行时数值表单不编辑此向量。
## 例如：Vector2(1280, 720) 表示宽 1280、高 720。
@export var arena_size := Vector2(1280.0, 720.0)
## 统一模拟随机种子；相同配置和操作顺序可重现随机结果，应用修改需要重启。
## 例如：1337 表示使用固定种子 1337。
@export_range(0, 2147483647, 1) var random_seed: int = 1337
## 模拟开始时的羊数量；应用修改需要重启模拟并保留暂停状态。
## 例如：240 表示初始生成 240 只羊。
@export_range(0, 10000, 1) var initial_sheep: int = 240
## 模拟开始时的狼数量；应用修改需要重启模拟并保留暂停状态。
## 例如：24 表示初始生成 24 只狼。
@export_range(0, 10000, 1) var initial_wolves: int = 24
## 模拟开始时的牧羊犬数量；应用修改需要重启模拟并保留暂停状态。
## 例如：12 表示初始生成 12 只牧羊犬。
@export_range(0, 10000, 1) var initial_sheepdogs: int = 12

@export_group("Shared movement")
## 动物采样附近实体和软分离的间隔，单位为模拟秒；不是全部 AI 决策的更新间隔。
## 例如：0.125 表示约每 0.125 秒更新一次邻居采样。
@export_range(0.0, 0.25, 0.005) var perception_interval: float = 0.125
## 同物种动物之间软分离的作用距离，单位为像素；不等同于物理碰撞。
## 例如：24 表示同类靠近到 24 像素内时产生分离移动。
@export_range(0.0, 80.0, 1.0) var separation_distance: float = 24.0
## 动物死亡后保留表现多久再移除，单位为模拟秒。
## 例如：0.3 表示死亡表现保留 0.3 秒。
@export_range(0.0, 3.0, 0.05) var death_duration: float = 0.3

@export_group("Behavior resources")
## 羊的移动、饥饿、觅食和避险配置资源。
## 例如：使用 CFG_Sheep.tres 调整羊的行为。
@export var sheep: SheepConfig = SheepConfig.new()
## 狼的搜索、猎捕、捕获和避狗配置资源。
## 例如：使用 CFG_Wolf.tres 调整狗对狼的威慑距离。
@export var wolf: WolfConfig = WolfConfig.new()
## 牧羊犬的移动和局部羊群保护配置资源。
## 例如：使用 CFG_Sheepdog.tres 调整保护范围。
@export var sheepdog: SheepdogConfig = SheepdogConfig.new()
## 草地布局、每点食物口数和恢复时间配置资源。
## 例如：使用 CFG_Grass.tres 调整草的周转速度。
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

	for point in grass.positions:
		if not point.is_finite():
			return "Grass positions must be finite."
	return ""

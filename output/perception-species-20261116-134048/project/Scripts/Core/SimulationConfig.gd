class_name SimulationConfig
extends Resource

const PRESET_VERSION: int = 6

@export_storage var preset_version: int = 0

@export_group("World - restart required")
## 场地宽高，单位为像素；应用修改需要重启模拟，运行时数值表单不编辑此向量。
## e.g. Vector2(1280, 720) 表示宽 1280、高 720。
@export var arena_size := Vector2(1280.0, 720.0)
## 统一模拟随机种子；相同配置和操作顺序可重现随机结果，应用修改需要重启。
## e.g. 1337 表示使用固定种子 1337。
@export_range(0, 2147483647, 1) var random_seed: int = 1337
## 模拟开始时的实体总数；应用修改需要重启模拟并保留暂停状态。
## e.g. 276 配合 20:2:1 比例生成 240 羊、24 狼、12 狗。
@export_range(0, 30000, 1) var initial_total: int = 276
## 羊的相对比例，与狼狗比例自动归一化；修改需要重启。
## e.g. 20:2:1 中羊占 20/23，比例为 0 时不生成羊。
@export_range(0, 100, 0.01) var sheep_ratio: float = 20.0
## 狼的相对比例，不要求各物种比例相加等于 100；修改需要重启。
## e.g. 20:2:1 中狼占 2/23。
@export_range(0, 100, 0.01) var wolf_ratio: float = 2.0
## 牧羊犬的相对比例；修改需要重启。
## e.g. 20:2:1 中牧羊犬占 1/23。
@export_range(0, 100, 0.01) var sheepdog_ratio: float = 1.0

## 空间格边长（px）；应用修改需要重启模拟。
## e.g. grid_cell_size = 30 表示每格 30 x 30 像素。
@export_range(12, 120, 1) var grid_cell_size: int = 30

@export_group("Shared movement")
## 同类软分离的采样间隔（模拟秒）；共享统计、狼狗压力和 AI 决策仍每步更新。
## e.g. 0.125 表示约每 0.125 秒更新一次软分离。
@export_range(0.0, 0.25, 0.005) var perception_interval: float = 0.125
## 同物种动物之间软分离的作用距离，单位为像素；不等同于物理碰撞。
## e.g. 24 表示同类靠近到 24 像素内时产生分离移动。
@export_range(0.0, 80.0, 1.0) var separation_distance: float = 24.0
## 动物死亡后保留尸体表现多久再隐藏并回收，单位为模拟秒。
## e.g. 0.3 表示尸体显示 0.3 秒，死亡立即退出模拟。
@export_range(0.0, 3.0, 0.05) var death_duration: float = 0.3

@export_group("Behavior resources")
## 羊的移动、聚群和避险配置资源。
## e.g. 使用 CFG_Sheep.tres 调整羊的行为。
@export var sheep: SheepConfig = SheepConfig.new()
## 狼的搜索、猎捕、捕获和避狗配置资源。
## e.g. 使用 CFG_Wolf.tres 调整狗对狼的威慑距离。
@export var wolf: WolfConfig = WolfConfig.new()
## 牧羊犬的移动和局部羊群保护配置资源。
## e.g. 使用 CFG_Sheepdog.tres 调整保护范围。
@export var sheepdog: SheepdogConfig = SheepdogConfig.new()

func copy_config() -> SimulationConfig:
	var result := duplicate(false) as SimulationConfig
	result.sheep = sheep.duplicate() as SheepConfig
	result.wolf = wolf.duplicate() as WolfConfig
	result.sheepdog = sheepdog.duplicate() as SheepdogConfig
	return result

func get_sections() -> Dictionary:
	return {"World": self, "Sheep": sheep, "Wolves": wolf, "Dogs": sheepdog}

# 按相对比例分配总数，余数相同时按羊、狼、狗顺序分配。
# e.g. get_initial_counts() 在默认配置下返回 Vector3i(240, 24, 12)。
func get_initial_counts() -> Vector3i:
	var ratios := PackedFloat64Array([sheep_ratio, wolf_ratio, sheepdog_ratio])
	var ratio_sum := sheep_ratio + wolf_ratio + sheepdog_ratio
	var counts := Vector3i.ZERO
	if initial_total == 0 or ratio_sum <= 0.0:
		return counts
	var remainders: Array[float] = []
	for kind in range(3):
		var share := initial_total * ratios[kind] / ratio_sum
		counts[kind] = floori(share)
		remainders.append(share - counts[kind])
	for index in range(initial_total - counts.x - counts.y - counts.z):
		var kind := remainders.find(remainders.max())
		counts[kind] += 1
		remainders[kind] = -1.0
	return counts

func requires_restart(previous: SimulationConfig) -> bool:
	return grid_cell_size != previous.grid_cell_size or arena_size != previous.arena_size or random_seed != previous.random_seed \
		or initial_total != previous.initial_total or sheep_ratio != previous.sheep_ratio \
		or wolf_ratio != previous.wolf_ratio or sheepdog_ratio != previous.sheepdog_ratio

func validate() -> String:
	if sheep == null or wolf == null or sheepdog == null:
		return "The preset must include all three behavior resources."

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
	if initial_total > 0 and sheep_ratio + wolf_ratio + sheepdog_ratio <= 0.0:
		return "At least one species ratio must be positive when the total is nonzero."
	if sheepdog.guard_distance >= sheepdog.leash_distance:
		return "Dog patrol radius must be below leash distance."
	if sheepdog.collect_distance >= sheep.herding_distance:
		return "Dog collecting distance must be below sheep pressure distance."
	return ""

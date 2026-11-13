class_name SheepConfig
extends Resource

@export_group("Movement")
## 羊寻找食物时的移动速度，单位为像素/秒；闲逛速度还会乘以闲逛比例。
## 例如：70 表示每秒最多移动 70 像素。
@export_range(0.0, 300.0, 1.0) var move_speed: float = 70.0
## 羊逃离狼时的速度，单位为像素/秒。
## 例如：110 表示逃跑时每秒最多移动 110 像素。
@export_range(0.0, 400.0, 1.0) var flee_speed: float = 110.0
## 羊识别猎捕中狼的距离，也用于排除危险草点；冒险觅食可忽略普通威胁，但不会忽略紧急距离。
## 例如：190 表示 190 像素内猎捕中的狼会触发避险判断。
@export_range(20.0, 600.0, 1.0) var perception_radius: float = 190.0
## 闲逛速度相对普通移动速度的比例。
## 例如：0.5 表示以普通速度的一半闲逛。
@export_range(0.0, 1.0, 0.05) var idle_speed_scale: float = 0.5
## 计算局部羊群中心时查找同伴的半径，单位为像素。
## 例如：120 表示只参考附近 120 像素内的羊。
@export_range(20.0, 400.0, 1.0) var flock_radius: float = 120.0
## 寻找食物途中靠近局部羊群中心的力度，接近草点后不再叠加。
## 例如：0 表示寻找食物时不向同伴中心靠拢。
@export_range(0.0, 2.0, 0.05) var foraging_cohesion: float = 0.2
## 闲逛时靠近局部羊群中心的力度。
## 例如：数值越大，闲逛时越倾向于靠近附近同伴。
@export_range(0.0, 2.0, 0.05) var idle_cohesion: float = 0.3

@export_group("Appetite")
## 新生成羊的初始整数饥饿下限，范围为 0～100；修改不改变已有羊的饥饿值。
## 例如：20 表示初始饥饿不低于 20。
@export_range(0, 100, 1) var initial_hunger_min: int = 20
## 新生成羊的初始整数饥饿上限，范围为 0～100；不得低于初始下限。
## 例如：70 表示初始饥饿不高于 70。
@export_range(0, 100, 1) var initial_hunger_max: int = 70
## 每模拟秒增加的整数饥饿点数，不足一点的增量累计保留，饥饿最多为 100。
## 例如：1 表示每秒增加 1 点饥饿。
@export_range(0, 100, 1) var hunger_per_second: int = 1
## 饥饿达到此值后开始觅食，必须高于停止觅食阈值。
## 例如：60 表示达到 60 点饥饿后开始找草。
@export_range(1, 100, 1) var hungry_threshold: int = 60
## 已经开始觅食的羊，饥饿降至此值或更低后停止觅食。
## 例如：20 表示吃到饥饿不超过 20 时停止。
@export_range(0, 100, 1) var full_threshold: int = 20
## 每完成一口草降低的整数饥饿点数，最低降至 0。
## 例如：25 表示每口草减少 25 点饥饿。
@export_range(1, 100, 1) var hunger_per_bite: int = 25
## 完成一口草所需的连续模拟时间，单位为秒；离开吃草行为会重置进度。
## 例如：2 表示连续吃草 2 秒才消耗一口。
@export_range(0.1, 20.0, 0.1) var grazing_duration: float = 2.0
## 羊与草点距离不超过此值时可以开始吃草，单位为像素。
## 例如：18 表示进入草点周围 18 像素后可以吃草。
@export_range(4.0, 64.0, 1.0) var grazing_distance: float = 18.0

@export_group("Foraging and safety")
## 觅食时重新评估草目标的间隔，单位为秒；正在吃草时不因定时评估换目标。
## 例如：2 表示每隔 2 秒考虑更好的草点。
@export_range(0.1, 10.0, 0.1) var retarget_interval: float = 2.0
## 已有有效草目标时，新目标评分需要改善的比例；评分越低越好。
## 例如：0.2 表示新目标至少改善 20% 才切换。
@export_range(0.0, 0.9, 0.05) var retarget_improvement: float = 0.2
## 草点评分中其他羊预约数量的惩罚权重。
## 例如：数值越大，越倾向选择预约较少的草点。
@export_range(0.0, 10.0, 0.1) var crowd_weight: float = 2.0
## 羊与任意狼的紧急距离，单位为像素；进入后无论饥饿和冒险结果都逃跑，不得超过感知半径。
## 例如：64 表示狼进入 64 像素内时强制逃跑。
@export_range(8.0, 190.0, 1.0) var emergency_distance: float = 64.0
## 看不见威胁后仍保留本次威胁遭遇的时间，单位为秒；未冒险的羊继续逃跑。
## 例如：1 表示威胁消失后继续保留 1 秒避险记忆。
@export_range(0.0, 10.0, 0.1) var safety_duration: float = 1.0

@export_group("Risk taking")
## 饥饿超过此值才有冒险觅食的概率，概率随饥饿线性增加；下降至此值时取消冒险。修改后下一模拟步重新抽签。
## 例如：70 表示饥饿不超过 70 时不会冒险。
@export_range(0, 99, 1) var risk_hunger_threshold: int = 70
## 饥饿为 100 时冒险觅食的概率，使用整数百分比；每次威胁遭遇只抽一次，紧急距离始终强制逃跑。修改后下一模拟步重新抽签。
## 例如：80 表示饥饿 100 时有 80% 的冒险概率。
@export_range(0, 100, 1) var max_risk_percent: int = 80

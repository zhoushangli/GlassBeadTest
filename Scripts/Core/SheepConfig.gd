class_name SheepConfig
extends Resource

@export_group("Movement")
## 羊寻找食物时的移动速度，单位为像素/秒；闲逛速度还会乘以闲逛比例。
## 例如：70 表示每秒最多移动 70 像素。
@export_range(0.0, 300.0, 1.0) var move_speed: float = 70.0
## 羊逃离狼时的速度，单位为像素/秒。
## 例如：110 表示逃跑时每秒最多移动 110 像素。
@export_range(0.0, 400.0, 1.0) var flee_speed: float = 110.0
## 羊在饥饿为 0 时的基础避险距离，也是扫描狼的最大距离；实际避险距离随饥饿百分比线性缩短，饥饿 100 时降至紧急距离。威胁判断和选草共用此距离。
## 例如：基础 130、紧急 36 时，饥饿 50 对应避险距离 83 像素。
@export_range(20.0, 600.0, 1.0) var perception_radius: float = 130.0
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
## 例如：1 表示每隔 1 秒考虑更好的草点。
@export_range(0.1, 10.0, 0.1) var retarget_interval: float = 1.0
## 已有有效草目标时，新目标评分需要改善的比例；评分越低越好。
## 例如：0.2 表示新目标至少改善 20% 才切换。
@export_range(0.0, 0.9, 0.05) var retarget_improvement: float = 0.2
## 草点评分中其他羊预约数量的惩罚权重。
## 例如：数值越大，越倾向选择预约较少的草点。
@export_range(0.0, 10.0, 0.1) var crowd_weight: float = 2.0
## 羊对任意狼的强制逃跑距离，单位为像素，也是饥饿 100 时的最小避险距离；不得超过基础避险距离。
## 例如：36 表示狼进入 36 像素内时始终逃跑。
@export_range(8.0, 190.0, 1.0) var emergency_distance: float = 36.0
## 狼离开实际避险范围后仍继续逃跑的模拟时间，单位为秒；减少此值可更快恢复觅食。
## 例如：0.5 表示危险解除后继续逃跑半秒。
@export_range(0.0, 10.0, 0.1) var safety_duration: float = 0.5

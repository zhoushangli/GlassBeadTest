class_name SheepConfig
extends Resource

@export_group("Movement")
## 常态移动速度（px/s）。
## e.g. move_speed = 70.0。
@export_range(0, 300, 1) var move_speed: float = 70.0
## 逃跑速度（px/s）。
## e.g. flee_speed = 110.0。
@export_range(0, 400, 1) var flee_speed: float = 110.0
## 游走速度比例。
## e.g. idle_speed_scale = 0.5。
@export_range(0, 1, 0.05) var idle_speed_scale: float = 0.5

@export_group("Threat")
## 狼产生全向压力的距离（px）。
## e.g. wolf_pressure_distance = 130.0。
@export_range(20, 600, 1) var wolf_pressure_distance: float = 130.0
## 危险消失后的警戒时间（秒）。
## e.g. alert_duration = 6.0。
@export_range(0, 30, 0.1) var alert_duration: float = 6.0
## 嚎叫造成的恐慌时间（秒）。
## e.g. panic_duration = 2.0。
@export_range(0, 10, 0.1) var panic_duration: float = 2.0

@export_group("Flocking")
## 局部聚合半径（px）。
## e.g. flock_radius = 55.0。
@export_range(1, 400, 1) var flock_radius: float = 55.0
## 速度对齐半径（px）。
## e.g. alignment_radius = 45.0。
@export_range(1, 400, 1) var alignment_radius: float = 45.0
## 软分离权重。
## e.g. separation_weight = 2.8。
@export_range(0, 10, 0.1) var separation_weight: float = 2.8
## 速度对齐权重。
## e.g. alignment_weight = 0.4。
@export_range(0, 3, 0.05) var alignment_weight: float = 0.4
## 局部聚合权重。
## e.g. cohesion_weight = 0.25。
@export_range(0, 3, 0.05) var cohesion_weight: float = 0.25
## 游走时群体方向的比例。
## e.g. idle_flock_scale = 0.05。
@export_range(0, 2, 0.05) var idle_flock_scale: float = 0.05
## 警戒时群体方向的比例。
## e.g. alert_flock_scale = 1.2。
@export_range(0, 3, 0.1) var alert_flock_scale: float = 1.2

@export_group("Herding")
## 全向避狗压力距离（px）。
## e.g. herding_distance = 90.0。
@export_range(1, 300, 1) var herding_distance: float = 90.0
## 避狗压力权重。
## e.g. dog_pressure_weight = 1.4。
@export_range(0, 5, 0.1) var dog_pressure_weight: float = 1.4
## 远离狼或恐慌源的权重。
## e.g. wolf_pressure_weight = 4.0。
@export_range(0, 10, 0.1) var wolf_pressure_weight: float = 4.0
## 速度趋近目标的响应率（每秒）。
## e.g. steering_rate = 4.0。
@export_range(0.1, 20, 0.1) var steering_rate: float = 4.0

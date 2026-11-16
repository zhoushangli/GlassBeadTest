class_name WolfConfig
extends Resource

@export_group("Movement")
## 常态移动速度（px/s）。
## e.g. move_speed = 70.0。
@export_range(0, 300, 1) var move_speed: float = 70.0
## 冲刺速度（px/s）。
## e.g. chase_speed = 135.0。
@export_range(0, 400, 1) var chase_speed: float = 135.0
## 避狗撤退速度（px/s）。
## e.g. retreat_speed = 160.0。
@export_range(0, 400, 1) var retreat_speed: float = 160.0
## 巡逻速度比例。
## e.g. patrol_speed_scale = 0.6。
@export_range(0, 1, 0.05) var patrol_speed_scale: float = 0.6

@export_group("Vision")
## 视觉距离（px）。
## e.g. perception_radius = 260.0。
@export_range(20, 700, 1) var perception_radius: float = 260.0
## 完整扇形角度（度）。
## e.g. vision_angle = 130.0。
@export_range(1, 360, 1) var vision_angle: float = 130.0
## 最后可见位置的记忆时间（秒）。
## e.g. memory_duration = 3.0。
@export_range(0, 20, 0.1) var memory_duration: float = 3.0
## 狗触发全向撤退的距离（px）。
## e.g. dog_threat_distance = 90.0。
@export_range(0, 400, 1) var dog_threat_distance: float = 90.0

@export_group("Hunting")
## 单次猎捕总时限（秒）。
## e.g. hunt_duration = 10.0。
@export_range(0.1, 60, 0.1) var hunt_duration: float = 10.0
## 猎捕或撤退后的休息时间（秒）。
## e.g. rest_duration = 3.0。
@export_range(0, 30, 0.1) var rest_duration: float = 3.0
## 冲刺即时捕获距离（px）。
## e.g. capture_distance = 22.0。
@export_range(1, 80, 1) var capture_distance: float = 22.0
## 冲刺触发距离相对捕获距离的倍数。
## e.g. charge_distance_scale = 4.0。
@export_range(1, 10, 0.1) var charge_distance_scale: float = 4.0
## 侧面或后方接近偏移（px）。
## e.g. strategy_offset = 40.0。
@export_range(0, 200, 1) var strategy_offset: float = 40.0
## 每秒减少的策略失败计数。
## e.g. strategy_decay = 0.05。
@export_range(0, 2, 0.01) var strategy_decay: float = 0.05

@export_group("Howling")
## 嚎叫刺激半径（px）。
## e.g. howl_radius = 200.0。
@export_range(1, 600, 1) var howl_radius: float = 200.0
## 可见猎物触发嚎叫的距离（px）。
## e.g. howl_trigger_distance = 200.0。
@export_range(1, 600, 1) var howl_trigger_distance: float = 200.0
## 嚎叫冷却时间（秒）。
## e.g. howl_cooldown = 5.0。
@export_range(0, 30, 0.1) var howl_cooldown: float = 5.0

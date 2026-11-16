class_name SheepdogConfig
extends Resource

@export_group("Movement")
## 常态移动速度（px/s）。
## e.g. move_speed = 80.0。
@export_range(0, 300, 1) var move_speed: float = 80.0
## 驱狼速度（px/s）。
## e.g. drive_speed = 185.0。
@export_range(0, 400, 1) var drive_speed: float = 185.0
## 返回速度（px/s）。
## e.g. return_speed = 100.0。
@export_range(0, 300, 1) var return_speed: float = 100.0

@export_group("Vision")
## 视觉距离（px）。
## e.g. perception_radius = 240.0。
@export_range(20, 700, 1) var perception_radius: float = 240.0
## 完整扇形角度（度）。
## e.g. vision_angle = 120.0。
@export_range(1, 360, 1) var vision_angle: float = 120.0
## 最后可见位置的记忆时间（秒）。
## e.g. memory_duration = 3.0。
@export_range(0, 20, 0.1) var memory_duration: float = 3.0

@export_group("Local protection")
## 保护锚点附近的局部羊群半径（px）。
## e.g. local_flock_radius = 120.0。
@export_range(20, 400, 1) var local_flock_radius: float = 120.0
## 狼靠近受保护羊的威胁距离（px）。
## e.g. threat_distance = 180.0。
@export_range(1, 600, 1) var threat_distance: float = 180.0
## 超出局部中心后优先返回的距离（px）。
## e.g. leash_distance = 240.0。
@export_range(20, 700, 1) var leash_distance: float = 240.0
## 巡逻圆半径（px）。
## e.g. guard_distance = 120.0。
@export_range(0, 400, 1) var guard_distance: float = 120.0
## 巡逻角速度（rad/s）。
## e.g. patrol_angular_speed = 0.6。
@export_range(0, 3, 0.05) var patrol_angular_speed: float = 0.6
## 收拢时位于离群羊外侧的距离（px）。
## e.g. collect_distance = 75.0。
@export_range(1, 200, 1) var collect_distance: float = 75.0
## 收拢完成距离相对局部半径的比例。
## e.g. collect_complete_ratio = 0.8。
@export_range(0.1, 0.95, 0.05) var collect_complete_ratio: float = 0.8
## 重新评估保护锚点的间隔（秒）。
## e.g. reassignment_interval = 2.0。
@export_range(0.1, 10, 0.1) var reassignment_interval: float = 2.0
## 更换有效锚点所需的评分改善比例。
## e.g. reassignment_improvement = 0.25。
@export_range(0, 0.9, 0.05) var reassignment_improvement: float = 0.25
## 其他狗已覆盖附近羊时的惩罚权重。
## e.g. coverage_weight = 2.0。
@export_range(0, 10, 0.1) var coverage_weight: float = 2.0

class_name SheepdogConfig
extends Resource

@export_group("Movement")
## 牧羊犬前往局部羊群守护点时的速度，单位为像素/秒。
## 例如：80 表示守护移动时每秒最多移动 80 像素。
@export_range(0.0, 300.0, 1.0) var move_speed: float = 80.0
## 牧羊犬拦截和驱赶狼时的速度，单位为像素/秒。
## 例如：185 表示拦截和驱赶时每秒最多移动 185 像素。
@export_range(0.0, 400.0, 1.0) var drive_speed: float = 185.0
## 牧羊犬返回守护点时的速度，单位为像素/秒。
## 例如：100 表示返回时每秒最多移动 100 像素。
@export_range(0.0, 300.0, 1.0) var return_speed: float = 100.0
## 牧羊犬能发现候选威胁狼的最大距离，单位为像素；实际威慑狼的距离由狼配置的 dog_threat_distance 控制。
## 例如：300 表示狗只处理自己周围 300 像素内的狼。
@export_range(20.0, 700.0, 1.0) var perception_radius: float = 300.0

@export_group("Local protection")
## 围绕保护锚点羊计算局部羊群中心的半径，单位为像素，也参与保护覆盖评分。
## 例如：120 表示以锚点羊附近 120 像素内的羊计算中心。
@export_range(20.0, 400.0, 1.0) var local_flock_radius: float = 120.0
## 猎捕中或持续驱赶的狼距离保护中心不超过此半径时视为羊群威胁，还须在狗的感知范围内。
## 例如：280 表示处理保护中心周围 280 像素内的猎捕威胁。
@export_range(20.0, 600.0, 1.0) var protection_radius: float = 280.0
## 牧羊犬离保护中心超过此距离后优先返回，单位为像素。
## 例如：300 表示追离羊群超过 300 像素后返回。
@export_range(20.0, 700.0, 1.0) var leash_distance: float = 300.0
## 守护点相对局部羊群中心的偏移距离，单位为像素。
## 例如：75 表示在羊群中心外约 75 像素处守护。
@export_range(0.0, 200.0, 1.0) var guard_distance: float = 75.0
## 重新评估保护锚点羊的间隔，单位为模拟秒；锚点死亡时立即重新选择。
## 例如：2 表示每隔 2 秒重新评估保护对象。
@export_range(0.1, 10.0, 0.1) var reassignment_interval: float = 2.0
## 已有保护锚点时，新锚点评分需要改善的比例；评分越低越好。
## 例如：0.25 表示新锚点至少改善 25% 才更换。
@export_range(0.0, 0.9, 0.05) var reassignment_improvement: float = 0.25
## 选择保护锚点时，对其他狗已有覆盖的惩罚权重。
## 例如：数值越大，越倾向保护其他狗较少覆盖的羊群。
@export_range(0.0, 10.0, 0.1) var coverage_weight: float = 2.0

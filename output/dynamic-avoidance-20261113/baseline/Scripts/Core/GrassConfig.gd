class_name GrassConfig
extends Resource

@export_group("Layout - restart required")
## 每片草地的布局半径，单位为像素，也用于草目标距离评分；应用修改需要重启模拟。
## 例如：84 表示草点分布在半径约 84 像素的草地中。
@export_range(12.0, 200.0, 1.0) var patch_radius: float = 84.0
## 每片草地包含的草点数量；应用修改需要重启模拟。
## 例如：24 表示每片草地生成 24 个草点。
@export_range(1, 100, 1) var per_patch: int = 24
## 每个草点可提供的口数，吃空后才开始恢复倒计时；应用修改需要重启模拟。
## 例如：2 表示每个草点可被吃两口。
@export_range(1, 20, 1) var bites: int = 2
## 各片草地中心的场地坐标；应用修改需要重启模拟，运行时数值表单不编辑此数组。
## 例如：Vector2(340, 240) 表示一片草地的中心。
@export var positions := PackedVector2Array([
	Vector2(340.0, 240.0), Vector2(940.0, 240.0),
	Vector2(340.0, 510.0), Vector2(940.0, 510.0),
	Vector2(640.0, 375.0)
])

@export_group("Regrowth")
## 草点吃空后原地恢复全部口数的模拟时间，单位为秒；修改只影响之后吃空的草点。
## 例如：15 表示吃空后等待 15 秒恢复。
@export_range(0.1, 180.0, 0.1) var regrow_duration: float = 15.0

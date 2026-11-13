class_name WolfConfig
extends Resource

@export_group("Movement")
## 狼搜索猎物时的移动速度，单位为像素/秒。
## 例如：70 表示搜索时每秒最多移动 70 像素。
@export_range(0.0, 300.0, 1.0) var move_speed: float = 70.0
## 狼追赶和贴近猎物时的移动速度，单位为像素/秒。
## 例如：135 表示追赶时每秒最多移动 135 像素。
@export_range(0.0, 400.0, 1.0) var chase_speed: float = 135.0
## 狼逃离牧羊犬时的移动速度，单位为像素/秒。
## 例如：160 表示避狗时每秒最多移动 160 像素。
@export_range(0.0, 400.0, 1.0) var retreat_speed: float = 160.0
## 狼寻找羊和维持追赶的感知半径，单位为像素；猎物离开范围后放弃追赶。
## 例如：260 表示只选择 260 像素内的羊。
@export_range(20.0, 700.0, 1.0) var perception_radius: float = 260.0
## 牧羊犬对狼的威慑距离，单位为像素；狼发现狗进入此距离后放弃猎物并逃跑，捕获结算时也会检查。
## 例如：160 表示狗进入狼周围 160 像素内即可打断猎捕。
@export_range(0.0, 400.0, 1.0) var dog_threat_distance: float = 160.0

@export_group("Hunting")
## 没有可用猎物时重新搜索的间隔，单位为模拟秒；已有目标时保持追赶。
## 例如：1 表示没有猎物时每秒搜索一次。
@export_range(0.1, 60.0, 0.1) var search_interval: float = 1.0
## 单次追赶允许持续的最长模拟时间，单位为秒；超时后重新选择，应用配置保留已追赶时间。
## 例如：10 表示一次最多追赶 10 秒。
@export_range(0.1, 60.0, 0.1) var hunt_duration: float = 10.0
## 其他狼已经追踪同一只羊时降低其选择权重，权重除以 1 加其他追踪狼数乘本值。
## 例如：3 表示已有一只狼追踪时，选择权重降为原来的四分之一。
@export_range(0.0, 20.0, 0.5) var competition_weight: float = 3.0

@export_group("Capture")
## 狼可以累计捕获进度的最大距离，单位为像素；超过后进度清零。
## 例如：22 表示必须持续贴近羊到 22 像素内。
@export_range(1.0, 80.0, 1.0) var capture_distance: float = 22.0
## 在捕获距离内连续维持多久才能捕获羊，单位为模拟秒；狗可以打断。
## 例如：0.5 表示持续贴近半秒后捕获。
@export_range(0.1, 5.0, 0.05) var capture_duration: float = 0.5

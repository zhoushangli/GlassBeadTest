class_name SheepConfig
extends Resource

@export_group("Movement")
@export_range(0.0, 300.0, 1.0) var move_speed: float = 70.0
@export_range(0.0, 400.0, 1.0) var flee_speed: float = 110.0
@export_range(20.0, 600.0, 1.0) var perception_radius: float = 190.0
@export_range(0.0, 1.0, 0.05) var idle_speed_scale: float = 0.5
@export_range(20.0, 400.0, 1.0) var flock_radius: float = 120.0
@export_range(0.0, 2.0, 0.05) var foraging_cohesion: float = 0.2
@export_range(0.0, 2.0, 0.05) var idle_cohesion: float = 0.3

@export_group("Appetite")
@export_range(0, 100, 1) var initial_hunger_min: int = 20
@export_range(0, 100, 1) var initial_hunger_max: int = 70
@export_range(0, 100, 1) var hunger_per_second: int = 1
@export_range(1, 100, 1) var hungry_threshold: int = 60
@export_range(0, 100, 1) var full_threshold: int = 20
@export_range(1, 100, 1) var hunger_per_bite: int = 25
@export_range(0.1, 20.0, 0.1) var grazing_duration: float = 2.0
@export_range(4.0, 64.0, 1.0) var grazing_distance: float = 18.0

@export_group("Foraging and safety")
@export_range(0.1, 10.0, 0.1) var retarget_interval: float = 2.0
@export_range(0.0, 0.9, 0.05) var retarget_improvement: float = 0.2
@export_range(0.0, 10.0, 0.1) var crowd_weight: float = 2.0
@export_range(8.0, 190.0, 1.0) var emergency_distance: float = 64.0
@export_range(0.0, 10.0, 0.1) var safety_duration: float = 1.0

@export_group("Risk taking")
@export_range(0, 99, 1) var risk_hunger_threshold: int = 70
@export_range(0, 100, 1) var max_risk_percent: int = 80

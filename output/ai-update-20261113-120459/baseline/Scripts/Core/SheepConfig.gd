class_name SheepConfig
extends Resource

@export_group("Movement")
@export_range(0.0, 300.0, 1.0) var move_speed: float = 55.0
@export_range(0.0, 400.0, 1.0) var flee_speed: float = 110.0
@export_range(20.0, 600.0, 1.0) var perception_radius: float = 190.0
@export_range(0.0, 1.0, 0.05) var idle_speed_scale: float = 0.5
@export_range(20.0, 400.0, 1.0) var flock_radius: float = 120.0
@export_range(0.0, 2.0, 0.05) var foraging_cohesion: float = 0.2
@export_range(0.0, 2.0, 0.05) var idle_cohesion: float = 0.3

@export_group("Appetite")
@export_range(0.0, 1.0, 0.01) var initial_hunger_min: float = 0.2
@export_range(0.0, 1.0, 0.01) var initial_hunger_max: float = 0.7
@export_range(0.0, 0.1, 0.001) var hunger_per_second: float = 0.01
@export_range(0.01, 1.0, 0.01) var hungry_threshold: float = 0.6
@export_range(0.0, 0.99, 0.01) var full_threshold: float = 0.2
@export_range(0.01, 1.0, 0.01) var hunger_per_bite: float = 0.25
@export_range(0.1, 20.0, 0.1) var grazing_duration: float = 3.0
@export_range(4.0, 64.0, 1.0) var grazing_distance: float = 18.0

@export_group("Foraging and safety")
@export_range(0.1, 10.0, 0.1) var retarget_interval: float = 2.0
@export_range(0.0, 0.9, 0.05) var retarget_improvement: float = 0.2
@export_range(0.0, 10.0, 0.1) var crowd_weight: float = 2.0
@export_range(8.0, 190.0, 1.0) var emergency_distance: float = 64.0
@export_range(0.0, 10.0, 0.1) var safety_duration: float = 1.0

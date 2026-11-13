class_name SheepdogConfig
extends Resource

@export_group("Movement")
@export_range(0.0, 300.0, 1.0) var move_speed: float = 80.0
@export_range(0.0, 400.0, 1.0) var drive_speed: float = 185.0
@export_range(0.0, 300.0, 1.0) var return_speed: float = 100.0
@export_range(20.0, 700.0, 1.0) var perception_radius: float = 300.0

@export_group("Local protection")
@export_range(20.0, 400.0, 1.0) var local_flock_radius: float = 120.0
@export_range(20.0, 600.0, 1.0) var protection_radius: float = 280.0
@export_range(20.0, 700.0, 1.0) var leash_distance: float = 300.0
@export_range(0.0, 200.0, 1.0) var guard_distance: float = 75.0
@export_range(0.1, 10.0, 0.1) var reassignment_interval: float = 2.0
@export_range(0.0, 0.9, 0.05) var reassignment_improvement: float = 0.25
@export_range(0.0, 10.0, 0.1) var coverage_weight: float = 2.0

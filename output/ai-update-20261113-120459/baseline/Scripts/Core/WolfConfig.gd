class_name WolfConfig
extends Resource

@export_group("Movement")
@export_range(0.0, 300.0, 1.0) var move_speed: float = 70.0
@export_range(0.0, 400.0, 1.0) var chase_speed: float = 135.0
@export_range(0.0, 400.0, 1.0) var retreat_speed: float = 160.0
@export_range(20.0, 700.0, 1.0) var perception_radius: float = 260.0
@export_range(0.0, 400.0, 1.0) var dog_threat_distance: float = 160.0
@export_range(20.0, 400.0, 1.0) var retreat_distance: float = 210.0

@export_group("Hunt rounds")
@export_range(1, 24, 1) var max_hunters: int = 3
@export_range(0.0, 120.0, 0.5) var rest_duration_min: float = 15.0
@export_range(0.0, 120.0, 0.5) var rest_duration_max: float = 25.0
@export_range(0.1, 60.0, 0.5) var hunt_duration: float = 10.0
@export_range(0.0, 600.0, 1.0) var cooperation_radius: float = 160.0
@export_range(0.0, 100.0, 1.0) var flank_offset: float = 32.0

@export_group("Capture")
@export_range(1.0, 80.0, 1.0) var capture_distance: float = 22.0
@export_range(0.1, 5.0, 0.05) var capture_duration: float = 0.5

class_name SimulationConfig
extends Resource

@export_group("World")
@export var arena_size := Vector2(1280.0, 720.0)
@export var random_seed: int = 1337
@export_range(0, 10000) var initial_sheep: int = 240
@export_range(0, 10000) var initial_wolves: int = 24
@export_range(0, 10000) var initial_sheepdogs: int = 12

@export_group("Flock and movement")
@export_range(0.0, 0.25) var perception_interval: float = 0.125
@export var separation_distance: float = 24.0
@export var flock_radius: float = 120.0
@export var cooperation_radius: float = 160.0
@export var flank_offset: float = 32.0
@export var protection_radius: float = 280.0
@export var dog_leash: float = 300.0

@export_group("Interaction")
@export var capture_distance: float = 22.0
@export var capture_duration: float = 0.5
@export var dog_threat_distance: float = 160.0
@export var safety_duration: float = 1.0
@export var grazing_duration: float = 3.0
@export var satiated_duration := Vector2(4.0, 8.0)
@export var death_duration: float = 0.3

@export_group("Grass")
@export var grass_radius: float = 84.0
@export_range(1, 100) var grass_per_patch: int = 24
@export_range(1, 20) var grass_bites: int = 3
@export var grass_regrow_duration: float = 8.0
@export var grazing_distance: float = 18.0
@export var grass_positions := PackedVector2Array([
	Vector2(340.0, 240.0), Vector2(940.0, 240.0),
	Vector2(340.0, 510.0), Vector2(940.0, 510.0),
	Vector2(640.0, 375.0)
])

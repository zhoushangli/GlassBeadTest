class_name GrassConfig
extends Resource

@export_group("Layout - restart required")
@export_range(12.0, 200.0, 1.0) var patch_radius: float = 84.0
@export_range(1, 100, 1) var per_patch: int = 24
@export_range(1, 20, 1) var bites: int = 2
@export var positions := PackedVector2Array([
	Vector2(340.0, 240.0), Vector2(940.0, 240.0),
	Vector2(340.0, 510.0), Vector2(940.0, 510.0),
	Vector2(640.0, 375.0)
])

@export_group("Regrowth")
@export_range(0.1, 180.0, 0.1) var regrow_duration: float = 15.0

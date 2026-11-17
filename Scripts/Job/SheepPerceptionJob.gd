class_name SheepPerceptionJob
extends Job

var separations := PackedVector2Array()
var refresh_flags := PackedByteArray()
var remaining := PackedFloat64Array()

var centers := PackedVector2Array()
var alignments := PackedVector2Array()
var threat_directions := PackedVector2Array()
var threat_strengths := PackedFloat64Array()
var dog_pressures := PackedVector2Array()
var desired_velocities := PackedVector2Array()
var speed_limits := PackedFloat64Array()
var neighbor_counts := PackedInt32Array()
var panic_strengths := PackedFloat64Array()

var wolf_pressure := PackedVector2Array()
var dog_pressure := PackedVector2Array()
var pressure_source_pairs: int = 0

var nearby_offsets := PackedInt32Array()
var nearby_members := PackedInt32Array()

func execute() -> void:
	if snapshot != null:
		var started := Time.get_ticks_usec()
		SheepSystem.calculate_snapshot(self)
		execute_ms = (Time.get_ticks_usec() - started) / 1000.0
		return

	target.calculate_batch(self)

func apply_result() -> void:
	if snapshot != null:
		target.apply_decision(self)
		return

	target.apply_batch(self)

func resize_output() -> void:
	separations.resize(rows.size())
	refresh_flags.resize(rows.size())
	remaining.resize(rows.size())
	centers.resize(rows.size())
	alignments.resize(rows.size())
	threat_directions.resize(rows.size())
	threat_strengths.resize(rows.size())
	dog_pressures.resize(rows.size())
	desired_velocities.resize(rows.size())
	speed_limits.resize(rows.size())
	neighbor_counts.resize(rows.size())
	panic_strengths.resize(rows.size())
	nearby_offsets.resize(rows.size() + 1)
	nearby_offsets.fill(0)
	nearby_members.clear()

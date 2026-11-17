class_name GridAggregateJob
extends Job

func execute() -> void:
	var started := Time.get_ticks_usec()
	grid = GridService.build_snapshot(snapshot)
	execute_ms = (Time.get_ticks_usec() - started) / 1000.0

func apply_result() -> void:
	target.apply_grid(grid, snapshot, null, execute_ms)

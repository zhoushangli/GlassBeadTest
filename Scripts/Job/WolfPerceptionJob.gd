class_name WolfPerceptionJob
extends Job

func execute() -> void:
	if context.has("version"):
		var started := Time.get_ticks_usec()
		var stats := AnimalSystem.batch_stats(context)
		var entries: Array[Dictionary] = []
		for row in rows:
			var entry := AnimalSystem.snapshot_perception(row, context, stats)
			var best := -1
			var distance: float = context.settings.dog_threat_distance * (2.0 if context.wolf_retreating[row] else 1.0)
			for other in context.dogs:
				var next: float = context.motion_position[row].distance_to(context.motion_position[other])
				if next < distance or (is_equal_approx(next, distance) and best >= 0 and context.identity_entity_id[other] < context.identity_entity_id[best]):
					best = other
					distance = next
			entry.threat = best
			entry.prey = -1
			if not context.wolf_hunting[row] and not context.wolf_resting[row] and not context.wolf_retreating[row] and best < 0:
				distance = INF
				for other in GridService.query_snapshot(context.motion_position[row], context.settings.perception_radius, AnimalEntity.Kind.SHEEP, context.grid, stats):
					if not AnimalSystem.snapshot_can_see(row, context.motion_position[other], context):
						continue

					var next: float = context.motion_position[row].distance_squared_to(context.motion_position[other])
					if next < distance or (is_equal_approx(next, distance) and entry.prey >= 0 and context.identity_entity_id[other] < context.identity_entity_id[entry.prey]):
						entry.prey = other
						distance = next
			entries.append(entry)
		result = {"entries": entries, "stats": stats, "execute_ms": (Time.get_ticks_usec() - started) / 1000.0}
		return

	target.calculate_batch(result, rows, context)

func apply_result() -> void:
	if context.has("version"):
		target.apply_decision(result, context)
		return

	target.apply_batch(result, context.delta)

class_name JobService
extends Service

var parallel_enabled: bool = true
# Limit submitted tasks; WorkerThreadPool owns the actual threads.
# e.g. max_workers = 4 allows four outstanding tasks from this service.
var max_workers: int = 4
var minimum_parallel_items: int = 32
# Select parallel stages for the synchronous batch entrypoint; asynchronous decisions always use workers.
# e.g. --job-stages=all enables synchronous Wolf and Dog batches in comparison tests.
var parallel_stages: Dictionary = {"Sheep": true, "Wolf": false, "DogAnchor": true, "Dog": false, "Grid": true}

var pending: Array[Job] = []
var working: Dictionary = {}
var completed: Array[Job] = []
var last_timings: Dictionary = {}

var _records: Dictionary = {}
var _stage: StringName

var async_jobs: Dictionary = {}
var retired_jobs: Array[Job] = []
var async_version: int = 0
var async_sequence: int = 0
var async_timings: Dictionary = {}

func submit_async(job: Job) -> bool:
	if not started or job == null or job.stage not in [&"Grid", &"Sheep", &"Wolf", &"Dog"] or job.state != Job.State.IDLE or async_jobs.has(job.stage):
		return false

	async_sequence += 1
	job.version = async_version
	job.sequence = async_sequence
	job.submitted_usec = Time.get_ticks_usec()
	job.state = Job.State.PENDING
	async_jobs[job.stage] = job
	_dispatch_async()
	return true

func _dispatch_async() -> void:
	var count := working.size()
	for job: Job in async_jobs.values() + retired_jobs:
		if job.state == Job.State.WORKING and not WorkerThreadPool.is_task_completed(job.task_id):
			count += 1

	for job: Job in async_jobs.values():
		if count >= maxi(1, max_workers):
			break
		if job.state == Job.State.PENDING and job.can_start():
			job.state = Job.State.WORKING
			job.task_id = WorkerThreadPool.add_task(job.run_profiled, false, String(job.stage))
			count += 1

func flush() -> void:
	# 1) Collect finished work only; simulation steps do not wait for running async jobs.
	_reap_retired()
	for stage in [&"Grid", &"Sheep", &"Wolf", &"Dog"]:
		var job: Job = async_jobs.get(stage)
		if job == null or job.state != Job.State.WORKING or not WorkerThreadPool.is_task_completed(job.task_id):
			continue

		WorkerThreadPool.wait_for_task_completion(job.task_id)
		job.task_id = -1
		job.state = Job.State.COMPLETED
		async_jobs.erase(stage)

		if job.version == async_version and not job.is_cancelled():
			var apply_started := Time.get_ticks_usec()
			var profile: ProfileService = g_gameplayEngine.profile_service
			job.apply_result()
			var applied_at := Time.get_ticks_usec()
			job.state = Job.State.APPLIED

			profile.record_duration("Async/" + String(stage) + "/Queue", (job.execution_started_usec - job.submitted_usec) / 1000.0)
			profile.record_duration("Async/" + String(stage) + "/AwaitApply", (apply_started - job.execution_finished_usec) / 1000.0)
			var work_metric := "Execute"
			profile.record_duration("Async/" + String(stage) + "/" + work_metric, (job.execution_finished_usec - job.execution_started_usec) / 1000.0)
			profile.record_duration("Async/" + String(stage) + "/Apply", (applied_at - apply_started) / 1000.0)
			profile.record_duration("Async/" + String(stage) + "/Latency", (applied_at - (job.snapshot.captured_usec if job.snapshot != null else job.submitted_usec)) / 1000.0)
			profile.count_event("Applied/" + String(stage))
			async_timings[stage] = {"latency_ms": (applied_at - job.submitted_usec) / 1000.0,
				"snapshot_latency_ms": (applied_at - (job.snapshot.captured_usec if job.snapshot != null else job.submitted_usec)) / 1000.0,
				"execute_ms": job.execute_ms, "sequence": job.sequence,
				"prepare_ms": (job.snapshot.prepare_ms if job.snapshot != null else 0.0), "submit_ms": (applied_at - apply_started) / 1000.0}
		else:
			job.state = Job.State.DISCARDED
			g_gameplayEngine.profile_service.count_event("Discarded/" + String(stage))

		job.release_input()

	# 2) Fill available worker slots after result application may have submitted new jobs.
	_dispatch_async()

func invalidate_async() -> void:
	# 1) Retire running jobs until workers finish; reject their results by generation.
	async_version += 1
	for job: Job in async_jobs.values():
		job.cancel()
		if job.state == Job.State.WORKING:
			retired_jobs.append(job)
		else:
			job.state = Job.State.DISCARDED
			g_gameplayEngine.profile_service.count_event("Discarded/" + String(job.stage))
			job.release_input()

	async_jobs.clear()
	async_timings.clear()
	_reap_retired()

func _reap_retired() -> void:
	for index in range(retired_jobs.size() - 1, -1, -1):
		var job := retired_jobs[index]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue

		WorkerThreadPool.wait_for_task_completion(job.task_id)
		job.task_id = -1
		job.state = Job.State.DISCARDED
		g_gameplayEngine.profile_service.count_event("Discarded/" + String(job.stage))
		job.release_input()
		retired_jobs.remove_at(index)

func add_job(job: Job) -> bool:
	if not started or job == null or job.stage == &"" or job.state in [Job.State.PENDING, Job.State.WORKING, Job.State.COMPLETED]:
		return false
	if _stage != &"" and job.stage != _stage:
		return false

	_stage = job.stage
	job.state = Job.State.PENDING
	pending.append(job)
	return true

func _process(_delta: float) -> void:
	if started:
		_reap_retired()
		collect_completed()
		dispatch_pending()
		_dispatch_async()

func dispatch_pending() -> void:
	var async_count := 0
	for job: Job in async_jobs.values() + retired_jobs:
		if job.state == Job.State.WORKING and not WorkerThreadPool.is_task_completed(job.task_id):
			async_count += 1

	while not pending.is_empty() and working.size() + async_count < maxi(1, max_workers):
		var job: Job = pending.pop_front()
		job.state = Job.State.WORKING
		job.task_id = WorkerThreadPool.add_task(job.execute, false, String(job.stage))
		working[job.task_id] = job

	if not pending.is_empty() and working.is_empty() and async_count >= maxi(1, max_workers):
		var job: Job = pending.pop_front()
		job.execute()
		job.state = Job.State.COMPLETED
		completed.append(job)

func collect_completed() -> void:
	for task_id: int in working.keys():
		if WorkerThreadPool.is_task_completed(task_id):
			_retrieve(task_id)

func _retrieve(task_id: int) -> void:
	WorkerThreadPool.wait_for_task_completion(task_id)
	var job: Job = working[task_id]
	working.erase(task_id)
	job.task_id = -1
	job.state = Job.State.COMPLETED
	completed.append(job)

func finish_stage() -> void:
	while not pending.is_empty() or not working.is_empty():
		dispatch_pending()
		collect_completed()
		if not working.is_empty():
			_retrieve(working.keys()[0])

	completed.sort_custom(_batch_before)
	for job in completed:
		job.apply_result()
		job.state = Job.State.APPLIED
		job.release_input()

	completed.clear()
	_stage = &""

func run_batches(stage: StringName, rows: PackedInt32Array, job_script: Script, input: Job, batch_size: int = 100) -> void:
	assert(started and stage != &"" and _stage == &"" and pending.is_empty() and working.is_empty() and completed.is_empty())
	var started_at := Time.get_ticks_usec()
	var size := mini(maxi(1, batch_size), maxi(1, ceili(rows.size() / float(maxi(1, max_workers)))))
	for first in range(0, rows.size(), size):
		var batch := first / size
		var key := "%s:%d" % [stage, batch]
		var job: Job = _records.get(key)
		if job == null or job.get_script() != job_script:
			job = job_script.new()
			_records[key] = job
		job.stage = stage
		job.batch = batch
		job.rows = rows.slice(first, mini(first + size, rows.size()))
		job.copy_input(input)
		var accepted := add_job(job)
		assert(accepted)

	var prepared_at := Time.get_ticks_usec()
	var parallel: bool = parallel_enabled and parallel_stages.get(String(stage), false) and rows.size() >= minimum_parallel_items
	var dispatch_ms := 0.0
	var wait_ms := 0.0
	var execute_ms := 0.0
	if not parallel:
		for job in pending:
			job.execute()
			job.state = Job.State.COMPLETED
			completed.append(job)
		pending.clear()
		execute_ms = (Time.get_ticks_usec() - prepared_at) / 1000.0
	else:
		while not pending.is_empty() or not working.is_empty():
			var dispatch_started := Time.get_ticks_usec()
			dispatch_pending()
			dispatch_ms += (Time.get_ticks_usec() - dispatch_started) / 1000.0
			var wait_started := Time.get_ticks_usec()
			collect_completed()
			if not working.is_empty():
				_retrieve(working.keys()[0])
			wait_ms += (Time.get_ticks_usec() - wait_started) / 1000.0

	var finished_at := Time.get_ticks_usec()
	finish_stage()
	last_timings[stage] = {"prepare_ms": (prepared_at - started_at) / 1000.0, "dispatch_ms": dispatch_ms,
		"wait_ms": wait_ms, "execute_ms": execute_ms, "submit_ms": (Time.get_ticks_usec() - finished_at) / 1000.0,
		"total_ms": (Time.get_ticks_usec() - started_at) / 1000.0, "parallel": parallel, "batches": ceili(rows.size() / float(size))}

func record_stage(stage: StringName, started_at: int, prepared_at: int) -> void:
	var timing: Dictionary = last_timings[stage]
	timing.prepare_ms += (prepared_at - started_at) / 1000.0
	timing.total_ms = (Time.get_ticks_usec() - started_at) / 1000.0

func drain() -> void:
	invalidate_async()
	for job in retired_jobs:
		job.cancel()
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		job.task_id = -1
		job.state = Job.State.DISCARDED
		job.release_input()

	retired_jobs.clear()
	for job in pending:
		job.state = Job.State.DISCARDED
		job.release_input()

	pending.clear()

	for task_id: int in working.keys():
		_retrieve(task_id)

	for job in completed:
		job.state = Job.State.DISCARDED
		job.release_input()

	completed.clear()
	_records.clear()
	_stage = &""

func _batch_before(first: Job, second: Job) -> bool:
	return first.batch < second.batch

func _reset() -> void:
	invalidate_async()
	for job in pending:
		job.state = Job.State.DISCARDED
		job.release_input()

	pending.clear()
	for task_id: int in working.keys():
		_retrieve(task_id)

	for job in completed:
		job.state = Job.State.DISCARDED
		job.release_input()

	completed.clear()
	_stage = &""
	_records.clear()
	last_timings.clear()

func _shutdown() -> void:
	drain()
	last_timings.clear()

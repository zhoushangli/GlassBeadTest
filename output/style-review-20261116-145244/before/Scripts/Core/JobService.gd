class_name JobService
extends Service

var parallel_enabled: bool = true
# Limit submitted tasks; WorkerThreadPool owns the actual threads.
# e.g. max_workers = 4 allows four outstanding tasks from this service.
var max_workers: int = 4
var minimum_parallel_items: int = 32
var parallel_stages: Dictionary = {"Sheep": true, "Wolf": true, "DogAnchor": true, "Dog": true, "Grid": true}
var pending: Array[Job] = []
var working: Dictionary = {}
var completed: Array[Job] = []
var last_timings: Dictionary = {}

var _records: Dictionary = {}
var _stage: StringName

func add_job(job: Job) -> bool:
	if not started or job == null or job.state in [Job.State.PENDING, Job.State.WORKING, Job.State.COMPLETED]:
		return false
	if _stage != &"" and job.stage != _stage:
		return false
	_stage = job.stage
	job.state = Job.State.PENDING
	pending.append(job)
	return true

func _process(_delta: float) -> void:
	if started:
		collect_completed()
		dispatch_pending()

func dispatch_pending() -> void:
	while not pending.is_empty() and working.size() < maxi(1, max_workers):
		var job: Job = pending.pop_front()
		job.state = Job.State.WORKING
		job.task_id = WorkerThreadPool.add_task(job.execute, false, String(job.stage))
		working[job.task_id] = job

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

func run_batches(stage: StringName, rows: PackedInt32Array, job_script: Script, context: Dictionary, target: Object, batch_size: int = 100) -> void:
	assert(started and _stage == &"" and pending.is_empty() and working.is_empty() and completed.is_empty())
	var started_at := Time.get_ticks_usec()
	var size := mini(maxi(1, batch_size), maxi(1, ceili(rows.size() / float(maxi(1, max_workers)))))
	for first in range(0, rows.size(), size):
		var batch := first / size
		var key := "%s:%d" % [stage, batch]
		var job: Job = _records.get(key)
		if job == null:
			job = job_script.new()
			_records[key] = job
		job.stage = stage
		job.batch = batch
		job.rows = rows.slice(first, mini(first + size, rows.size()))
		job.context = context
		job.target = target
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
	drain()
	last_timings.clear()

func _shutdown() -> void:
	_reset()

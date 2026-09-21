## TestPerformanceDiagnosis.gd
## Automated diagnosis and stress-test benchmark for Spire.
## Profiles the running ECS simulation across multiple multi-tier ticking cycles,
## captures per-system microsecond timings, monitors frame times and memory,
## and outputs a detailed diagnostic performance report to console and disk.
extends Node2D

const _PerformanceDiagnostics = preload("res://modules/diagnostics/PerformanceDiagnostics.gd")
const _TileTypes              = preload("res://modules/terrain/data/TileTypes.gd")
const _BurningComponent       = preload("res://modules/matter/components/BurningComponent.gd")

var _diag = null

func _ready() -> void:
	print("\n=================================================================")
	print("       STARTING RUNTIME SYSTEM PERFORMANCE DIAGNOSIS BENCHMARK    ")
	print("=================================================================")

	# Wait for World to complete initial generation & module registrations
	await get_tree().process_frame
	await get_tree().process_frame

	_diag = _PerformanceDiagnostics.new()
	add_child(_diag)
	_diag.start_profiling()

	await _run_diagnostic_benchmark()

func _run_diagnostic_benchmark() -> void:
	var world = World
	assert(world != null, "World singleton must be available!")

	# Pause background accumulator to prevent double-ticking during the benchmark
	world.paused = true

	print("[Diagnosis] Running Phase 1: Calm Baseline (10 ticks)...")
	for i in range(10):
		world._run_tick()
		await get_tree().process_frame

	print("[Diagnosis] Running Phase 2: Weather & Precipitation Active (10 ticks)...")
	world.wind_strength = 0.8
	world.wind_condition = 3  # RAIN
	world.rain_allowed = true
	for i in range(10):
		world._run_tick()
		await get_tree().process_frame

	print("[Diagnosis] Running Phase 3: Active Combustion & Dynamic Invalidation (10 ticks)...")
	var reg = world.get_registry()
	var test_eid: int = world.get_entity_at(Vector2i(64, 64))
	if test_eid != -1 and not reg.has(test_eid, &"BurningComponent"):
		var burn = _BurningComponent.new()
		burn.intensity = 0.8
		burn.fuel = 5.0
		burn.heat_output = 35.0
		reg.add(test_eid, burn)
		world.mark_render_dirty()

	for i in range(10):
		world._run_tick()
		await get_tree().process_frame

	print("[Diagnosis] Running Phase 4: Multi-Tier Cadence (Rare & Long Ticks, 25 ticks)...")
	for i in range(25):
		world._run_tick()
		await get_tree().process_frame

	# Stop profiling and generate report
	_diag.stop_profiling()

	var log_path: String = "res://logs/performance_diagnosis.log"
	var report: String = _diag.save_report_to_file(log_path)

	# Print the complete report to stdout
	print("\n" + report + "\n")

	# --- Assertions ---
	var sys_perf: Dictionary = world.get_system_performance_data()
	var avg_tick_ms: float = (sys_perf.get("average_tick_usec", 0.0) as float) / 1000.0

	if not sys_perf.has("systems") or sys_perf["systems"].is_empty():
		printerr("ERROR: System metrics must be recorded!")
		get_tree().quit(1)
		return

	if avg_tick_ms > 20.0:
		printerr("ERROR: Average tick duration (%.2f ms) exceeded 20ms threshold!" % avg_tick_ms)
		get_tree().quit(1)
		return

	if not FileAccess.file_exists(log_path):
		printerr("ERROR: Performance diagnosis log file was not found on disk!")
		get_tree().quit(1)
		return

	print(">>> PERFORMANCE DIAGNOSIS COMPLETE & LOG CREATED: %s <<<\n" % log_path)
	world.paused = false
	get_tree().quit(0)

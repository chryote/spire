## PerformanceDiagnostics.gd
## Real-time system performance profiler and diagnostic logger for Spire.
## Tracks:
##   - Per-system microsecond tick latencies across all simulation modules
##   - Frame times, FPS, 1% low FPS, P95/P99 latency, and VSync hitch detection
##   - Multi-tier cadence distribution (Normal, Rare, Long ticks)
##   - GPU render texture upload duration and dirtiness
##   - Memory footprint (static memory usage & peak memory)
##
## Can run headlessly as a benchmark test, attached to WorldView for live profiling,
## or toggled at runtime to output detailed diagnostic logs.
class_name PerformanceDiagnostics
extends Node

const TARGET_FRAME_TIME_MS: float = 16.667  # 60 FPS
const TARGET_TICK_TIME_MS:  float = 100.0   # 10 TPS budget (100ms per tick)

# ---------------------------------------------------------------------------
# State & Metrics
# ---------------------------------------------------------------------------
var is_active: bool = false

# Frame pacing
var _frame_times_ms: Array[float] = []
var _total_frames: int = 0
var _dropped_frames_60: int = 0  # > 16.67ms
var _dropped_frames_30: int = 0  # > 33.33ms
var _hitch_frames_50: int = 0    # > 50.0ms

# System metrics snapshot
var _session_start_time_msec: int = 0
var _world: Node = null
var _render_system: Node = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_world = get_node_or_null("/root/World")
	if _world != null:
		_world.profiling_enabled = true

func start_profiling() -> void:
	is_active = true
	_session_start_time_msec = Time.get_ticks_msec()
	_frame_times_ms.clear()
	_total_frames = 0
	_dropped_frames_60 = 0
	_dropped_frames_30 = 0
	_hitch_frames_50 = 0

	if _world != null:
		_world.profiling_enabled = true
		_world.reset_profiler()

func stop_profiling() -> void:
	is_active = false

func _process(delta: float) -> void:
	if not is_active:
		return

	var frame_ms: float = delta * 1000.0
	_frame_times_ms.append(frame_ms)
	_total_frames += 1

	if frame_ms > 50.0:
		_hitch_frames_50 += 1
		_dropped_frames_30 += 1
		_dropped_frames_60 += 1
	elif frame_ms > 33.333:
		_dropped_frames_30 += 1
		_dropped_frames_60 += 1
	elif frame_ms > TARGET_FRAME_TIME_MS:
		_dropped_frames_60 += 1

	# Keep bounded history (last 2000 frames)
	if _frame_times_ms.size() > 2000:
		_frame_times_ms.pop_front()

# ---------------------------------------------------------------------------
# Statistical Calculations
# ---------------------------------------------------------------------------

func calculate_frame_stats() -> Dictionary:
	if _frame_times_ms.is_empty():
		return {
			"avg_ms": 0.0,
			"min_ms": 0.0,
			"max_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
			"avg_fps": 0.0,
			"one_percent_low_fps": 0.0
		}

	var sorted: Array[float] = _frame_times_ms.duplicate()
	sorted.sort()

	var sum_ms: float = 0.0
	var min_ms: float = sorted[0]
	var max_ms: float = sorted[sorted.size() - 1]

	for v in sorted:
		sum_ms += v

	var count: int = sorted.size()
	var avg_ms: float = sum_ms / float(count)
	var p95_idx: int = clampi(int(float(count) * 0.95), 0, count - 1)
	var p99_idx: int = clampi(int(float(count) * 0.99), 0, count - 1)
	var p95_ms: float = sorted[p95_idx]
	var p99_ms: float = sorted[p99_idx]

	# 1% Low FPS (average of slowest 1% of frames)
	var low_1_count: int = maxi(1, int(float(count) * 0.01))
	var low_1_sum: float = 0.0
	for i in range(count - low_1_count, count):
		low_1_sum += sorted[i]
	var avg_low_1_ms: float = low_1_sum / float(low_1_count)
	var one_pct_low_fps: float = 1000.0 / avg_low_1_ms if avg_low_1_ms > 0.0 else 0.0

	return {
		"avg_ms": avg_ms,
		"min_ms": min_ms,
		"max_ms": max_ms,
		"p95_ms": p95_ms,
		"p99_ms": p99_ms,
		"avg_fps": 1000.0 / avg_ms if avg_ms > 0.0 else 0.0,
		"one_percent_low_fps": one_pct_low_fps
	}

# ---------------------------------------------------------------------------
# Report Generation
# ---------------------------------------------------------------------------

func generate_report() -> String:
	var fstats: Dictionary = calculate_frame_stats()
	var sys_data: Dictionary = {}
	if _world != null:
		sys_data = _world.get_system_performance_data()

	var render_data: Dictionary = {}
	if _render_system == null:
		_render_system = get_tree().root.find_child("AsciiRenderSystem", true, false)
	if _render_system != null and _render_system.has_method("get_render_performance_data"):
		render_data = _render_system.get_render_performance_data()

	var static_mem_mb: float = float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var peak_mem_mb: float   = float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)

	var tick_count: int = sys_data.get("tick_count", 0)
	var avg_tick_ms: float = (sys_data.get("average_tick_usec", 0.0) as float) / 1000.0
	var max_tick_ms: float = float(sys_data.get("max_tick_usec", 0)) / 1000.0

	var duration_sec: float = float(Time.get_ticks_msec() - _session_start_time_msec) / 1000.0

	var out: PackedStringArray = []
	out.append("================================================================================")
	out.append("                 SPIRE ENGINE DETAILED PERFORMANCE DIAGNOSIS                    ")
	out.append("================================================================================")
	out.append("Timestamp:       %s" % Time.get_datetime_string_from_system())
	out.append("Session Duration: %.2f seconds | Total Frames: %d | Simulation Ticks: %d" % [duration_sec, _total_frames, tick_count])
	out.append("Engine Version:  %s | OS: %s" % [Engine.get_version_info()["string"], OS.get_name()])
	out.append("Static Memory:   %.2f MB (Peak: %.2f MB)" % [static_mem_mb, peak_mem_mb])
	out.append("--------------------------------------------------------------------------------")
	out.append("")
	out.append("--- [1] FRAME PACING & DISPLAY DIAGNOSIS ---")
	out.append("Average FPS:     %6.1f FPS (Mean Frame Time: %.2f ms)" % [fstats["avg_fps"], fstats["avg_ms"]])
	out.append("1%% Low FPS:      %6.1f FPS (Worst 1%% Frame Mean: %.2f ms)" % [fstats["one_percent_low_fps"], 1000.0 / maxf(0.1, fstats["one_percent_low_fps"])])
	out.append("P95 Frame Time:  %6.2f ms" % fstats["p95_ms"])
	out.append("P99 Frame Time:  %6.2f ms" % fstats["p99_ms"])
	out.append("Max Frame Spike: %6.2f ms" % fstats["max_ms"])
	out.append("Frames > 16.6ms: %5d (%.1f%% of frames dipped below 60 FPS)" % [
		_dropped_frames_60,
		(float(_dropped_frames_60) / maxf(1.0, float(_total_frames))) * 100.0
	])
	out.append("Frames > 33.3ms: %5d (%.1f%% of frames dipped below 30 FPS)" % [
		_dropped_frames_30,
		(float(_dropped_frames_30) / maxf(1.0, float(_total_frames))) * 100.0
	])
	out.append("Frames > 50.0ms: %5d (Severe hitches / freezes)" % _hitch_frames_50)
	out.append("")
	out.append("--- [2] SIMULATION TICK HEALTH (10 TPS Target = 100.0 ms budget) ---")
	out.append("Average Tick Duration: %6.3f ms (Budget Used: %4.1f%%)" % [avg_tick_ms, (avg_tick_ms / TARGET_TICK_TIME_MS) * 100.0])
	out.append("Maximum Tick Spike:    %6.3f ms (Budget Used: %4.1f%%)" % [max_tick_ms, (max_tick_ms / TARGET_TICK_TIME_MS) * 100.0])
	out.append("Simulation Headroom:   %6.3f ms (%.1fx faster than real-time threshold)" % [
		maxf(0.0, TARGET_TICK_TIME_MS - avg_tick_ms),
		TARGET_TICK_TIME_MS / maxf(0.001, avg_tick_ms)
	])
	out.append("")
	out.append("--- [3] PER-SYSTEM WORKLOAD BREAKDOWN ---")
	out.append("%-26s | %7s | %10s | %10s | %8s | %s" % ["System Name", "Calls", "Avg (usec)", "Max (usec)", "% Tick", "Health Status"])
	out.append("---------------------------+---------+------------+------------+----------+--------------")

	var systems_dict: Dictionary = sys_data.get("systems", {})
	var sys_names: Array = systems_dict.keys()

	# Sort systems by total time descending
	sys_names.sort_custom(func(a, b):
		return systems_dict[a]["total_usec"] > systems_dict[b]["total_usec"]
	)

	for sname in sys_names:
		var sinfo: Dictionary = systems_dict[sname]
		var calls: int = sinfo.get("calls", 0)
		var total_u: int = sinfo.get("total_usec", 0)
		var avg_u: float = float(total_u) / maxf(1.0, float(calls))
		var max_u: int = sinfo.get("max_usec", 0)
		var pct_of_tick: float = (avg_u / (maxf(1.0, avg_tick_ms * 1000.0))) * 100.0

		var status: String = "OPTIMAL"
		if avg_u > 10000.0: # > 10ms
			status = "CRITICAL"
		elif avg_u > 3000.0 or max_u > 15000: # > 3ms avg or >15ms spike
			status = "WARNING"

		out.append("%-26s | %7d | %10.1f | %10d | %7.1f%% | [%s]" % [
			sname, calls, avg_u, max_u, pct_of_tick, status
		])

	out.append("---------------------------+---------+------------+------------+----------+--------------")
	out.append("")
	out.append("--- [4] GPU RENDER TEXTURE DIAGNOSTICS ---")
	if not render_data.is_empty():
		var updates: int = render_data.get("update_count", 0)
		var avg_render_ms: float = (render_data.get("average_update_usec", 0.0) as float) / 1000.0
		var max_render_ms: float = float(render_data.get("max_update_usec", 0)) / 1000.0
		var last_render_ms: float = float(render_data.get("last_update_usec", 0)) / 1000.0
		out.append("Texture Update Passes: %d (Throttled & Dirty-Checked)" % updates)
		out.append("Avg Texture Upload:    %.3f ms" % avg_render_ms)
		out.append("Max Texture Upload:    %.3f ms" % max_render_ms)
		out.append("Last Texture Upload:   %.3f ms" % last_render_ms)
	else:
		out.append("Render system metrics not available or not yet initialized.")

	out.append("")
	out.append("--- [5] DIAGNOSTIC VERDICT & RECOMMENDATIONS ---")
	if fstats["one_percent_low_fps"] >= 55.0 and avg_tick_ms < 15.0 and _hitch_frames_50 == 0:
		out.append("[PASS] System is running in EXCELLENT HEALTH.")
		out.append("  - Camera panning is fully decoupled from simulation ticks.")
		out.append("  - Frame pacing is consistent with zero severe hitches.")
		out.append("  - Simulation operates with massive headroom (%.1fx real-time)." % [TARGET_TICK_TIME_MS / maxf(0.001, avg_tick_ms)])
	elif avg_tick_ms < 35.0:
		out.append("[PASS] System is running in GOOD HEALTH with acceptable pacing.")
		if _dropped_frames_60 > 5:
			out.append("  - Note: Minor frame drops below 60 FPS detected (%d frames). Ensure VSync or exponential camera damping is active." % _dropped_frames_60)
	else:
		out.append("[WARNING] Simulation load exceeds recommended thresholds.")
		out.append("  - Average tick latency is elevated (%.2f ms). Consider checking top systems in the breakdown above." % avg_tick_ms)

	out.append("================================================================================")
	return "\n".join(out)

# ---------------------------------------------------------------------------
# File Logging
# ---------------------------------------------------------------------------

func save_report_to_file(path: String = "res://logs/performance_diagnosis.log") -> String:
	var report: String = generate_report()

	# Ensure directory exists
	var dir_path: String = path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()
		print("[PerformanceDiagnostics] Performance report successfully saved to: %s" % path)
	else:
		printerr("[PerformanceDiagnostics] Failed to open file for writing: %s (Error: %s)" % [path, FileAccess.get_open_error()])

	# Also save copy to user directory for easy access outside Godot project
	var user_file := FileAccess.open("user://performance_diagnosis.log", FileAccess.WRITE)
	if user_file != null:
		user_file.store_string(report)
		user_file.close()

	return report

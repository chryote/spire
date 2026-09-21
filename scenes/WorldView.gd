## WorldView.gd
## Root node for the main scene.  Handles global simulation controls.
##
## Keyboard shortcuts:
##   Space         — pause / unpause simulation
##   +  /  =       — double tick speed  (max 200 tps)
##   -             — halve tick speed   (min 1 tps)
##   F3  /  ~      — toggle simulation & item monitor HUD
##   F11           — generate and save performance diagnosis log
##   F12           — reset performance diagnosis metrics
extends Node2D

const _PerformanceDiagnostics = preload("res://modules/diagnostics/PerformanceDiagnostics.gd")

var _diag: _PerformanceDiagnostics = null

func _ready() -> void:
	_diag = _PerformanceDiagnostics.new()
	add_child(_diag)
	_diag.start_profiling()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key: InputEventKey = event as InputEventKey

	match key.keycode:
		KEY_SPACE:
			World.paused = not World.paused
			_print_status()

		KEY_EQUAL, KEY_KP_ADD:
			World.set_speed(World.ticks_per_second * 2.0)
			_print_status()

		KEY_MINUS, KEY_KP_SUBTRACT:
			World.set_speed(World.ticks_per_second / 2.0)
			_print_status()

		KEY_F11:
			if _diag != null:
				var log_path: String = "res://logs/performance_diagnosis.log"
				var report: String = _diag.save_report_to_file(log_path)
				print("\n[Spire Performance Diagnosis]\n" + report + "\n")
				print("[Spire] New performance diagnosis written to: %s" % log_path)

		KEY_F12:
			if _diag != null:
				_diag.start_profiling()
				print("[Spire] Performance diagnostic metrics have been reset.")

func _print_status() -> void:
	var state: String = "PAUSED" if World.paused else "%.0f tps" % World.ticks_per_second
	print("[Spire] tick=%d  speed=%s" % [World.tick_count, state])


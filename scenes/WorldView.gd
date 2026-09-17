## WorldView.gd
## Root node for the main scene.  Handles global simulation controls.
##
## Keyboard shortcuts:
##   Space         — pause / unpause simulation
##   +  /  =       — double tick speed  (max 200 tps)
##   -             — halve tick speed   (min 1 tps)
##   R             — re-seed world (restarts with new noise seed)
extends Node2D

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

func _print_status() -> void:
	var state: String = "PAUSED" if World.paused else "%.0f tps" % World.ticks_per_second
	print("[Spire] tick=%d  speed=%s" % [World.tick_count, state])

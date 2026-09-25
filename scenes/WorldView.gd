## WorldView.gd
## Root node for the main scene.  Handles global simulation controls.
##
## Controls & shortcuts:
##   Left Click    — inspect tile / creature on clicked tile
##   I / Esc       — toggle / close Inspector HUD
##   Space         — pause / unpause simulation
##   +  /  =       — double tick speed  (max 200 tps)
##   -             — halve tick speed   (min 1 tps)
##   F3  /  ~      — toggle simulation & item monitor HUD
##   F11           — generate and save performance diagnosis log
##   F12           — reset performance diagnosis metrics
extends Node2D

const _PerformanceDiagnostics = preload("res://modules/diagnostics/PerformanceDiagnostics.gd")
const _CreatureFactory        = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes          = preload("res://modules/creature/data/CreatureTypes.gd")
const _TileAffordance         = preload("res://modules/signal/data/TileAffordance.gd")
const _CreatureSpawner        = preload("res://modules/creature/systems/CreatureSpawner.gd")

var _diag: _PerformanceDiagnostics = null

## Optional configuration list for starter creatures.
## When empty, defaults to _CreatureSpawner.DEFAULT_STARTER_CONFIGS (Male & Female Grazer).
var starter_creature_configs: Array[Dictionary] = []

func _ready() -> void:
	_diag = _PerformanceDiagnostics.new()
	add_child(_diag)
	_diag.start_profiling()
	_spawn_starter_creatures.call_deferred()

# ---------------------------------------------------------------------------
# Extensible Creature Spawning Helpers
# ---------------------------------------------------------------------------

## Spawns starter creatures into the simulation using the extensible CreatureSpawner helper.
## Defaults to a male and female Grazer pair if no custom configs are provided.
func spawn_starter_creatures(configs: Array = []) -> Array[int]:
	var active_configs: Array = configs
	if active_configs.is_empty():
		active_configs = starter_creature_configs if not starter_creature_configs.is_empty() else _CreatureSpawner.DEFAULT_STARTER_CONFIGS
	return _CreatureSpawner.spawn_starter_creatures(World, active_configs)

## Backward-compatibility helper for legacy single-creature starter invocation.
func _spawn_starter_creature() -> void:
	spawn_starter_creatures()

func _spawn_starter_creatures() -> void:
	spawn_starter_creatures()

## Extensible helper to spawn a single creature from configuration.
func spawn_creature(config: Dictionary, excluded_positions: Array[Vector2i] = []) -> int:
	return _CreatureSpawner.spawn_creature(World, config, excluded_positions)

## Extensible helper to search and return a valid spawn position in the world.
func find_spawn_position(criteria: Dictionary = {}, excluded_positions: Array[Vector2i] = []) -> Vector2i:
	return _CreatureSpawner.find_spawn_position(World, criteria, excluded_positions)

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


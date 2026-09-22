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

var _diag: _PerformanceDiagnostics = null

func _ready() -> void:
	_diag = _PerformanceDiagnostics.new()
	add_child(_diag)
	_diag.start_profiling()
	_spawn_starter_creature.call_deferred()

func _spawn_starter_creature() -> void:
	var reg = World.get_registry()
	if reg == null:
		return
	var veg_store: Dictionary  = reg.get_store(&"VegetationComponent")
	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	var spawn_pos := Vector2i(-1, -1)
	for eid: int in veg_store:
		var tile = tile_store.get(eid, null)
		if tile != null and tile.position.y >= 65 and tile.position.y <= 95:
			if World.signals != null and World.signals.has_affordance(tile.position, _TileAffordance.WALKABLE):
				if not World.signals.has_affordance(tile.position, _TileAffordance.HAZARD_LETHAL):
					spawn_pos = tile.position
					break
	if spawn_pos == Vector2i(-1, -1):
		spawn_pos = Vector2i(64, 80)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "Grazer")
	print("[Spire] Spawned starter grazer creature (eid=%d) at %s." % [creature_eid, spawn_pos])

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


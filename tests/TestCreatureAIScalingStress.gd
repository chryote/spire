## TestCreatureAIScalingStress.gd
## High-volume stress benchmark for CreatureAISystem and SocialSystem.
## Validates performance scaling under 10, 50, and 80 Grazers on the map.
## Measures microsecond tick timings to ensure cognitive layer stays well within
## the 100ms budget (< 5ms per tick under heavy herd load).
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureAISystem    = preload("res://modules/creature/systems/CreatureAISystem.gd")
const _SocialSystem        = preload("res://modules/creature/systems/SocialSystem.gd")
const _CreatureLocomotion  = preload("res://modules/creature/systems/CreatureLocomotionSystem.gd")

var _log_lines: Array[String] = []

func _log(msg: String) -> void:
	print(msg)
	_log_lines.append(msg)

func _ready() -> void:
	_log("=================================================================")
	_log("       STARTING CREATURE AI SCALING STRESS BENCHMARK (50+ GRAZERS)")
	_log("=================================================================")

	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	# Enable profiling on World singleton
	World.profiling_enabled = true
	World.reset_profiler()

	_benchmark_stage("Stage 1: 10 Starter Grazers", 10, 20)
	_benchmark_stage("Stage 2: 50 Grazers (Target Scale Problem)", 50, 30)
	_benchmark_stage("Stage 3: 80 Grazers (Heavy Stress Scale)", 80, 25)

	_log("\n=================================================================")
	_log(">>> ALL CREATURE AI SCALING STRESS BENCHMARKS PASSED! <<<")
	_log("=================================================================")

	_save_log()
	World.paused = false
	get_tree().quit(0)

func _benchmark_stage(stage_name: String, target_count: int, ticks_to_run: int) -> void:
	_log("\n--- %s (Running %d ticks) ---" % [stage_name, ticks_to_run])

	var reg = World.get_registry()
	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")

	# Spawn up to target_count
	var current_count: int = creature_store.size()
	var needed: int = target_count - current_count

	for i in range(needed):
		var spawn_x: int = 30 + (i % 20) * 2
		var spawn_y: int = 30 + (i / 20) * 2
		var p := Vector2i(spawn_x, spawn_y)
		var g_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "Grazer_%d" % (current_count + i), [])
		assert(g_eid != -1, "Grazer spawn failed")

	_log("  Spawned total: %d creatures active on map." % creature_store.size())

	# Warmup 2 ticks
	for _w in range(2):
		World._run_tick()

	# Reset system profiler for this stage
	World.reset_profiler()

	var stage_start_usec: int = Time.get_ticks_usec()

	for t in range(ticks_to_run):
		World._run_tick()

	var stage_total_usec: int = Time.get_ticks_usec() - stage_start_usec
	var stage_avg_ms: float = float(stage_total_usec) / float(ticks_to_run) / 1000.0

	var metrics: Dictionary = World.get_system_performance_data()
	var sys_data: Dictionary = metrics.get("systems", {})

	var ai_stats: Dictionary = sys_data.get("CreatureAISystem", {})
	var soc_stats: Dictionary = sys_data.get("SocialSystem", {})
	var loco_stats: Dictionary = sys_data.get("CreatureLocomotionSystem", {})

	var ai_avg_usec: float = float(ai_stats.get("total_usec", 0)) / maxf(1.0, float(ai_stats.get("calls", 1)))
	var soc_avg_usec: float = float(soc_stats.get("total_usec", 0)) / maxf(1.0, float(soc_stats.get("calls", 1)))
	var loco_avg_usec: float = float(loco_stats.get("total_usec", 0)) / maxf(1.0, float(loco_stats.get("calls", 1)))

	_log("  Stage Results:")
	_log("    Total Tick Mean Duration:     %.2f ms" % stage_avg_ms)
	_log("    CreatureAISystem Mean:        %.1f usec (%.3f ms) [Max: %d usec]" % [ai_avg_usec, ai_avg_usec / 1000.0, ai_stats.get("max_usec", 0)])
	_log("    SocialSystem Mean:            %.1f usec (%.3f ms) [Max: %d usec]" % [soc_avg_usec, soc_avg_usec / 1000.0, soc_stats.get("max_usec", 0)])
	_log("    CreatureLocomotionSystem:     %.1f usec (%.3f ms) [Max: %d usec]" % [loco_avg_usec, loco_avg_usec / 1000.0, loco_stats.get("max_usec", 0)])

	# Assertions: CreatureAISystem MUST remain under 5.0ms even under 80 creatures
	# (Previously it spiked to 30ms-70ms at 50 creatures!)
	var ai_max_ms: float = float(ai_stats.get("max_usec", 0)) / 1000.0
	assert(ai_avg_usec / 1000.0 < 5.0, "CreatureAISystem mean must be < 5.0ms (got %.3f ms)" % [ai_avg_usec / 1000.0])
	assert(ai_max_ms < 15.0, "CreatureAISystem max spike must be < 15.0ms (got %.3f ms)" % ai_max_ms)

func _save_log() -> void:
	var path: String = "res://logs/creature_ai_scaling_stress.log"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log_lines))
		file.close()
		_log("Report saved to %s" % path)

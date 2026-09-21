## TestItemScalingStress.gd
## High-volume stress test and benchmark for Spire's item scaling architecture.
## Validates item stacking, O(1) global count tracking, sparse decay/signal performance,
## and burnout efficiency under thousands of simulated items.
extends Node2D

const _ItemTypes          = preload("res://modules/item/data/ItemTypes.gd")
const _MaterialTypes      = preload("res://modules/matter/data/MaterialTypes.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemComponent      = preload("res://modules/item/components/ItemComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _MatterComponent     = preload("res://modules/matter/components/MatterComponent.gd")
const _VegetationYieldSystem = preload("res://modules/vegetation/systems/VegetationYieldSystem.gd")
const _SignalSystem        = preload("res://modules/signal/systems/SignalSystem.gd")
const _DecaySystem         = preload("res://modules/matter/systems/DecaySystem.gd")
const _PhaseChangeSystem   = preload("res://modules/matter/systems/PhaseChangeSystem.gd")
const _CombustionSystem    = preload("res://modules/matter/systems/CombustionSystem.gd")

var _log_lines: Array[String] = []

func _log(msg: String) -> void:
	print(msg)
	_log_lines.append(msg)

func _ready() -> void:
	_log("=================================================================")
	_log("       STARTING HIGH-VOLUME ITEM SCALING STRESS BENCHMARK        ")
	_log("=================================================================")

	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_test_stacking_and_mass_scaling()
	_test_o1_global_count_tracking()
	await _test_high_volume_system_timings()
	_test_tile_burnout_cleanup()

	_log("\n=================================================================")
	_log(">>> ALL ITEM SCALING BENCHMARKS & STRESS TESTS PASSED! <<<")
	_log("=================================================================")

	_save_log()
	World.paused = false
	get_tree().quit(0)

func _test_stacking_and_mass_scaling() -> void:
	_log("\n[Test 1] Stacking and Mass Scaling...")
	var reg = World.get_registry()
	var test_pos := Vector2i(10, 10)
	var tile_eid: int = World.get_entity_at(test_pos)
	assert(tile_eid != -1, "Test tile must exist")

	var inv: _InventoryComponent = World.get_component(tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		World.add_component(tile_eid, inv)
	inv.clear_items()

	# Deposit 50 units of grass one by one
	var first_id: int = -1
	for i in range(50):
		var id: int = _ItemFactory.create_and_deposit(World, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, tile_eid, 1)
		if i == 0:
			first_id = id
		else:
			assert(id == first_id, "Subsequent deposits must reuse the same stack entity ID")

	assert(inv.items.size() == 1, "Tile should have exactly 1 item stack, got: %d" % inv.items.size())
	var stack_comp: _ItemComponent = World.get_component(first_id, &"ItemComponent")
	assert(stack_comp.quantity == 50, "Stack quantity should be 50, got: %d" % stack_comp.quantity)
	_log("  -> PASSED: 50 items collapsed into 1 entity stack with quantity 50.")

	# Deposit 30 more units (Grass max_stack is 64: fills to 64, overflows 16 into a new stack)
	var second_id: int = _ItemFactory.create_and_deposit(World, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, tile_eid, 30)
	assert(inv.items.size() == 2, "Tile should have 2 stacks after exceeding max_stack 64, got: %d" % inv.items.size())
	var first_comp: _ItemComponent = World.get_component(first_id, &"ItemComponent")
	var second_comp: _ItemComponent = World.get_component(second_id, &"ItemComponent")
	assert(first_comp.quantity == 64, "First stack should be capped at 64, got: %d" % first_comp.quantity)
	assert(second_comp.quantity == 16, "Second stack should hold overflow 16, got: %d" % second_comp.quantity)
	_log("  -> PASSED: Stack overflow (64 cap) properly created a second stack (16 qty).")

func _test_o1_global_count_tracking() -> void:
	_log("\n[Test 2] O(1) Global Count Tracking...")
	var initial_log: int = _ItemFactory.get_global_count(_ItemTypes.Type.LOG)

	var test_pos := Vector2i(12, 12)
	var tile_eid: int = World.get_entity_at(test_pos)
	var inv: _InventoryComponent = World.get_component(tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		World.add_component(tile_eid, inv)

	# Deposit 25 wood logs
	var log_id: int = _ItemFactory.create_and_deposit(World, _ItemTypes.Type.LOG, _MaterialTypes.Type.WOOD_HARD, tile_eid, 25)
	var after_create: int = _ItemFactory.get_global_count(_ItemTypes.Type.LOG)
	assert(after_create == initial_log + 25, "Global log count should increase by 25, got: %d" % after_create)

	# Destroy entity and verify global count decreases
	World.destroy_entity(log_id)
	var after_destroy: int = _ItemFactory.get_global_count(_ItemTypes.Type.LOG)
	assert(after_destroy == initial_log, "Global log count should restore to initial value after destruction")
	_log("  -> PASSED: Global counts incremented on creation and decremented on entity destruction in O(1).")

func _test_high_volume_system_timings() -> void:
	_log("\n[Test 3] High-Volume Simulation Timings (10,000+ Items)...")
	var reg = World.get_registry()

	# Spawn 10,000 items distributed across tiles
	_log("  Spawning 10,000 items across 100 map tiles...")
	for t in range(100):
		var tile_pos := Vector2i(20 + (t % 10), 20 + (t / 10))
		var tile_eid: int = World.get_entity_at(tile_pos)
		var inv: _InventoryComponent = World.get_component(tile_eid, &"InventoryComponent")
		if inv == null:
			inv = _InventoryComponent.new()
			World.add_component(tile_eid, inv)
		# Deposit 100 grass items per tile (collapses to 2 stacks: 64 + 36)
		_ItemFactory.create_and_deposit(World, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, tile_eid, 100)

	# Also add raw meat items to 5 tiles to test carnivore scent and decay
	for m in range(5):
		var m_pos := Vector2i(50 + m, 50)
		var m_eid: int = World.get_entity_at(m_pos)
		var inv: _InventoryComponent = World.get_component(m_eid, &"InventoryComponent")
		if inv == null:
			inv = _InventoryComponent.new()
			World.add_component(m_eid, inv)
		_ItemFactory.create_and_deposit(World, _ItemTypes.Type.STICK, _MaterialTypes.Type.RAW_MEAT, m_eid, 20)

	_log("  Total items currently tracked in world: %d" % (
		_ItemFactory.get_global_count(_ItemTypes.Type.GRASS) + _ItemFactory.get_global_count(_ItemTypes.Type.STICK)
	))

	# Benchmark 20 ticks
	_log("  Benchmarking 20 ticks across simulation systems...")
	var start_usec: int = Time.get_ticks_usec()
	for i in range(20):
		World._run_tick()
		await get_tree().process_frame

	var total_usec: int = Time.get_ticks_usec() - start_usec
	var avg_ms: float = (float(total_usec) / 20.0) / 1000.0
	_log("  -> Completed 20 ticks in %.2f ms (Average tick: %.3f ms)" % [float(total_usec) / 1000.0, avg_ms])
	assert(avg_ms < 35.0, "Average tick must be under 35ms, got: %.2f ms" % avg_ms)

	# Verify system health
	var sys_perf = World.get_system_performance_data()
	var systems: Dictionary = sys_perf.get("systems", {})
	if systems.has("VegetationYieldSystem"):
		var y_avg = (systems["VegetationYieldSystem"]["total_usec"] / systems["VegetationYieldSystem"]["calls"]) / 1000.0
		_log("  VegetationYieldSystem avg: %.3f ms" % y_avg)
		assert(y_avg < 2.0, "VegetationYieldSystem must run in under 2ms")

	if systems.has("DecaySystem"):
		var d_avg = (systems["DecaySystem"]["total_usec"] / systems["DecaySystem"]["calls"]) / 1000.0
		_log("  DecaySystem avg: %.3f ms" % d_avg)
		assert(d_avg < 2.0, "DecaySystem must run in under 2ms")

	_log("  -> PASSED: High-volume simulation operates well within 100ms real-time budget.")

func _test_tile_burnout_cleanup() -> void:
	_log("\n[Test 4] Tile Burnout Cleanup Under Stacked Items...")
	var test_pos := Vector2i(35, 35)
	var tile_eid: int = World.get_entity_at(test_pos)
	var inv: _InventoryComponent = World.get_component(tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		World.add_component(tile_eid, inv)
	inv.clear_items()

	# Deposit 200 flammable kindling items
	_ItemFactory.create_and_deposit(World, _ItemTypes.Type.STICK, _MaterialTypes.Type.KINDLING, tile_eid, 100)
	_ItemFactory.create_and_deposit(World, _ItemTypes.Type.STICK, _MaterialTypes.Type.KINDLING, tile_eid, 100)
	assert(inv.items.size() > 0, "Should hold stacks of kindling")

	var combustion_sys = null
	for sys in World._sim_systems:
		if sys is _CombustionSystem:
			combustion_sys = sys
			break
	assert(combustion_sys != null, "CombustionSystem must be registered")

	var matter = World.get_component(tile_eid, &"MatterComponent")
	combustion_sys._burnout(tile_eid, matter, World.get_registry())

	assert(inv.items.is_empty(), "Flammable items must be completely consumed on burnout")
	_log("  -> PASSED: Single-pass burnout cleanly consumed stacked items without errors.")

func _save_log() -> void:
	var path: String = "res://logs/item_scaling_stress.log"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_log_lines))
		file.close()
		_log("Report saved to %s" % path)

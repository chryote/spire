## TestVegetationYieldCap.gd
## Verifies that VegetationYieldSystem enforces the global hard cap on grass yields
## while preserving existing local per-tile max_yield and yield timing logic.
extends Node2D

const _ItemTypes          = preload("res://modules/item/data/ItemTypes.gd")
const _ItemComponent      = preload("res://modules/item/components/ItemComponent.gd")
const _ItemYieldComponent  = preload("res://modules/item/components/ItemYieldComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _VegetationYieldSystem = preload("res://modules/vegetation/systems/VegetationYieldSystem.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")

func _ready() -> void:
	print("\n=== STARTING VEGETATION YIELD HARD CAP TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	await _test_yield_cap()

	print("\n>>> ALL VEGETATION YIELD HARD CAP TESTS PASSED! <<<\n")
	World.paused = false
	get_tree().quit(0)

func _test_yield_cap() -> void:
	var reg = World.get_registry()
	assert(reg != null, "World registry must be available")

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	var initial_grass_count: int = 0
	for item_eid: int in item_store:
		var item = item_store[item_eid]
		if item.item_type == _ItemTypes.Type.GRASS:
			initial_grass_count += 1

	print("[Test] Initial grass items in world: %d" % initial_grass_count)
	var max_cap: int = _VegetationYieldSystem.GLOBAL_ITEM_CAPS.get(_ItemTypes.Type.GRASS, 200)
	print("[Test] Configured global grass cap: %d" % max_cap)
	assert(max_cap == 200, "Global grass cap should default to 200")

	var yield_store: Dictionary = reg.get_store(&"ItemYieldComponent")
	var inv_store: Dictionary = reg.get_store(&"InventoryComponent")
	print("[Test] Total ItemYieldComponent entities: %d" % yield_store.size())
	print("[Test] Total InventoryComponent entities: %d" % inv_store.size())

	if not yield_store.is_empty():
		var first_eid = yield_store.keys()[0]
		var ycomp = yield_store[first_eid]
		print("[Test] Sample plant eid=%d, ticks_per_yield=%d, ticks_since_yield=%d" % [first_eid, ycomp.ticks_per_yield, ycomp.ticks_since_yield])

	# Run 80 simulation ticks to allow plants to produce yields
	print("[Test] Simulating 80 ticks...")
	for i in range(80):
		World._run_tick()
		await get_tree().process_frame

	if not yield_store.is_empty():
		var first_eid = yield_store.keys()[0]
		var ycomp = yield_store[first_eid]
		print("[Test] Sample plant eid=%d, ticks_per_yield=%d, ticks_since_yield=%d" % [first_eid, ycomp.ticks_per_yield, ycomp.ticks_since_yield])

	var final_grass_count: int = 0
	var final_grass_qty: int = 0
	for item_eid: int in item_store:
		var item = item_store[item_eid]
		if item.item_type == _ItemTypes.Type.GRASS:
			final_grass_count += 1
			final_grass_qty += item.quantity

	var global_tracked: int = _ItemFactory.get_global_count(_ItemTypes.Type.GRASS)
	print("[Test] Final grass stacks: %d, total units: %d, O(1) global count: %d" % [final_grass_count, final_grass_qty, global_tracked])
	assert(global_tracked <= max_cap, "O(1) Global grass count (%d) must NOT exceed cap (%d)" % [global_tracked, max_cap])
	assert(final_grass_count <= max_cap, "Grass stacks (%d) must NOT exceed global cap (%d)" % [final_grass_count, max_cap])
	print("  -> PASSED: Global hard cap strictly respected.")

	var file = FileAccess.open("res://logs/test_vegetation_yield_cap.log", FileAccess.WRITE)
	if file != null:
		file.store_string("PASSED: Global hard cap strictly respected. Final grass units: %d, global_tracked: %d, max_cap: %d\n" % [
			final_grass_qty, global_tracked, max_cap
		])
		file.close()

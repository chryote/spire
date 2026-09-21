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
	var max_cap: int = _VegetationYieldSystem.GLOBAL_ITEM_CAPS.get(_ItemTypes.Type.GRASS, 16384)
	print("[Test] Configured global grass cap: %d" % max_cap)
	assert(max_cap > 0, "Global grass cap should be positive")

	# Verify MAX_YIELD_PER_TILE dictionary and TILE_ITEM_CAPS alias
	assert(_VegetationYieldSystem.MAX_YIELD_PER_TILE is Dictionary, "MAX_YIELD_PER_TILE must be a Dictionary")
	assert(_VegetationYieldSystem.TILE_ITEM_CAPS is Dictionary, "TILE_ITEM_CAPS alias must be a Dictionary")
	var tile_cap: int = _VegetationYieldSystem.get_max_yield_per_tile(_ItemTypes.Type.GRASS)
	print("[Test] Configured per-tile grass cap: %d" % tile_cap)
	assert(tile_cap == 5, "Per-tile grass cap should be 5")
	assert(_VegetationYieldSystem.MAX_YIELD_PER_TILE[_ItemTypes.Type.STICK] == 8, "Per-tile stick cap should be 8")
	assert(_VegetationYieldSystem.MAX_YIELD_PER_TILE[_ItemTypes.Type.LOG] == 2, "Per-tile log cap should be 2")

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

	# Verify per-tile yield cap across all plants
	for eid: int in yield_store:
		var inv: _InventoryComponent = inv_store.get(eid, null)
		if inv != null:
			var tile_grass_qty: int = inv.get_total_quantity_of_type(reg, _ItemTypes.Type.GRASS)
			assert(tile_grass_qty <= tile_cap, "Tile grass qty (%d) must not exceed per-tile cap (%d)" % [tile_grass_qty, tile_cap])
	print("  -> PASSED: Per-tile yield cap strictly respected across all tiles.")

	var file = FileAccess.open("res://logs/test_vegetation_yield_cap.log", FileAccess.WRITE)
	if file != null:
		file.store_string("PASSED: Global hard cap and per-tile cap strictly respected. Final grass units: %d, global_tracked: %d, max_cap: %d, per_tile_cap: %d\n" % [
			final_grass_qty, global_tracked, max_cap, tile_cap
		])
		file.close()

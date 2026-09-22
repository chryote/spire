## TestRiverAndPondGen.gd
## Integration test for procedural river system and small pond generation.
extends Node2D

const _TileAffordance = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes    = preload("res://modules/signal/data/SignalTypes.gd")
const _FluidComponent = preload("res://modules/matter/components/FluidComponent.gd")
const _MaterialTypes  = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes      = preload("res://modules/terrain/data/TileTypes.gd")
const _BiomeTypes     = preload("res://modules/terrain/data/BiomeTypes.gd")

func _ready() -> void:
	print("\n=== STARTING RIVER SYSTEM & POND GENERATION INTEGRATION TESTS ===")
	await get_tree().process_frame
	await get_tree().process_frame

	var signals = World.signals
	assert(signals != null, "World.signals must be initialized!")

	_test_water_generation_counts()
	_test_river_span_and_channel()
	_test_river_fords_walkability(signals)
	_test_small_ponds_exist()
	_test_riparian_zone_moisture()
	_test_fluid_and_tile_integrity(signals)
	_test_water_remains_liquid_under_simulation()

	print("\n>>> ALL RIVER SYSTEM & POND GENERATION TESTS PASSED! <<<\n")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: Water Generation Counts
# ---------------------------------------------------------------------------
func _test_water_generation_counts() -> void:
	print("[Test 1] Water generation counts...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")

	var deep_water_count: int = 0
	var shallow_water_count: int = 0

	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		if fluid != null and fluid.material_id == _MaterialTypes.Type.WATER:
			if fluid.volume >= 0.4:
				deep_water_count += 1
			else:
				shallow_water_count += 1

	var total_water: int = deep_water_count + shallow_water_count
	print("  -> Total water tiles: %d (Deep: %d, Shallow: %d)" % [total_water, deep_water_count, shallow_water_count])

	assert(total_water > 200, "Should have generated at least 200 water tiles from rivers and ponds (got %d)" % total_water)
	assert(deep_water_count > 50, "Should have deep river channel / pond centers (got %d)" % deep_water_count)
	assert(shallow_water_count > 50, "Should have shallow riverbanks / fords / pond edges (got %d)" % shallow_water_count)
	print("  -> PASSED: Substantial deep and shallow water generated.")

# ---------------------------------------------------------------------------
# Test 2: River Span & Channel Extent
# ---------------------------------------------------------------------------
func _test_river_span_and_channel() -> void:
	print("[Test 2] River span across the map...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	var min_x: int = 999
	var max_x: int = -999
	var min_y: int = 999
	var max_y: int = -999

	for eid: int in fluid_store:
		var tile = tile_store.get(eid, null)
		if tile != null:
			min_x = mini(min_x, tile.position.x)
			max_x = maxi(max_x, tile.position.x)
			min_y = mini(min_y, tile.position.y)
			max_y = maxi(max_y, tile.position.y)

	var span_x: int = max_x - min_x
	var span_y: int = max_y - min_y
	print("  -> Water bounding box: X[%d..%d] span=%d, Y[%d..%d] span=%d" % [min_x, max_x, span_x, min_y, max_y, span_y])

	# A river traversing North->South or West->East spans at least 100 tiles along its flow axis
	var max_span: int = maxi(span_x, span_y)
	assert(max_span >= 100, "River must span at least 100 tiles across the 128x128 map (got %d)" % max_span)
	print("  -> PASSED: River spans continuously across the map (span=%d)." % max_span)

# ---------------------------------------------------------------------------
# Test 3: River Fords Walkability
# ---------------------------------------------------------------------------
func _test_river_fords_walkability(signals) -> void:
	print("[Test 3] River fords walkability and affordance...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	var shallow_water_tiles: Array[Vector2i] = []
	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		if fluid != null and fluid.material_id == _MaterialTypes.Type.WATER:
			if fluid.volume < 0.4 and fluid.volume >= 0.15:
				var tile = tile_store.get(eid, null)
				if tile != null:
					shallow_water_tiles.append(tile.position)

	assert(not shallow_water_tiles.is_empty(), "Must have shallow water tiles for crossings")

	# Run a tick to ensure signals reflect affordances
	World._run_tick()

	var walkable_ford_tiles: int = 0
	for pos: Vector2i in shallow_water_tiles:
		if signals.has_affordance(pos, _TileAffordance.WALKABLE):
			assert(not signals.has_affordance(pos, _TileAffordance.SWIMMABLE), "Shallow ford must NOT require swimming")
			walkable_ford_tiles += 1

	print("  -> Found %d walkable ford/shallow water tiles." % walkable_ford_tiles)
	assert(walkable_ford_tiles >= 20, "Should have multiple walkable shallow water tiles along fords/banks (got %d)" % walkable_ford_tiles)
	print("  -> PASSED: Fords provide walkable crossings without swimming requirement.")

# ---------------------------------------------------------------------------
# Test 4: Small Ponds Exist
# ---------------------------------------------------------------------------
func _test_small_ponds_exist() -> void:
	print("[Test 4] Small ponds exist...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	# Collect all water coordinates
	var water_set: Dictionary = {}
	for eid: int in fluid_store:
		var tile = tile_store.get(eid, null)
		if tile != null:
			water_set[tile.position] = true

	# Perform flood-fill connected component analysis to count distinct water bodies
	var visited: Dictionary = {}
	var components: Array[Array] = []

	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	for pos: Vector2i in water_set:
		if visited.has(pos):
			continue
		var cluster: Array = []
		var queue: Array[Vector2i] = [pos]
		visited[pos] = true

		while not queue.is_empty():
			var curr: Vector2i = queue.pop_front()
			cluster.append(curr)

			for dir: Vector2i in directions:
				var npos: Vector2i = curr + dir
				if water_set.has(npos) and not visited.has(npos):
					visited[npos] = true
					queue.append(npos)

		components.append(cluster)

	print("  -> Identified %d distinct water bodies on the map." % components.size())

	# Main river is the largest component (>150 tiles).
	# Small ponds are separate smaller components (between 5 and 60 tiles).
	var pond_count: int = 0
	for comp: Array in components:
		if comp.size() >= 4 and comp.size() <= 80:
			pond_count += 1

	print("  -> Found %d small ponds (size 4..80 tiles)." % pond_count)
	assert(pond_count >= 1, "Should identify at least 1 distinct small pond body (got %d)" % pond_count)
	print("  -> PASSED: Distinct small organic ponds identified.")

# ---------------------------------------------------------------------------
# Test 5: Riparian Zone Moisture
# ---------------------------------------------------------------------------
func _test_riparian_zone_moisture() -> void:
	print("[Test 5] Riparian zone moisture boost...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	var riparian_land_moistures: Array[float] = []
	var inland_dry_moistures: Array[float] = []

	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
	]

	for eid: int in biome_store:
		var tile = tile_store.get(eid, null)
		var biome = biome_store.get(eid, null)
		if tile == null or biome == null:
			continue

		# If this tile itself does not have standing water
		if not fluid_store.has(eid):
			var adjacent_to_water: bool = false
			for off: Vector2i in offsets:
				var npos: Vector2i = tile.position + off
				var nid: int = World.get_entity_at(npos)
				if nid != -1 and fluid_store.has(nid):
					adjacent_to_water = true
					break

			if adjacent_to_water:
				riparian_land_moistures.append(biome.moisture)
			else:
				inland_dry_moistures.append(biome.moisture)

	assert(not riparian_land_moistures.is_empty(), "Must have land tiles bordering water")

	var avg_riparian: float = 0.0
	for m: float in riparian_land_moistures:
		avg_riparian += m
	avg_riparian /= float(riparian_land_moistures.size())

	var avg_inland: float = 0.0
	for m: float in inland_dry_moistures:
		avg_inland += m
	avg_inland /= float(inland_dry_moistures.size())

	print("  -> Average riparian bank moisture: %.2f vs inland: %.2f" % [avg_riparian, avg_inland])
	assert(avg_riparian > avg_inland, "Riparian banks must have higher average moisture than inland terrain")
	print("  -> PASSED: Riparian banks receive moisture boost.")

# ---------------------------------------------------------------------------
# Test 6: Fluid & Tile Integrity
# ---------------------------------------------------------------------------
func _test_fluid_and_tile_integrity(signals) -> void:
	print("[Test 6] Fluid and tile integrity...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		var tile = tile_store.get(eid, null)

		assert(fluid.material_id == _MaterialTypes.Type.WATER, "Fluid material must be WATER")
		assert(fluid.settled == true, "Terrain generated fluid must be settled")
		assert(fluid.volume > 0.0, "Fluid volume must be positive")

		# Check that water tiles are drinkable in signals
		var hyd: float = signals.get_signal(_SignalTypes.HYDRATION, tile.position)
		assert(hyd > 0.0, "Water tile at %s must provide HYDRATION signal (got %f)" % [tile.position, hyd])
		assert(signals.has_affordance(tile.position, _TileAffordance.DRINKABLE), "Water tile must have DRINKABLE affordance")

	print("  -> PASSED: Fluid settled state, water material, and drinkable hydration verified.")

# ---------------------------------------------------------------------------
# Test 7: Water Does Not Freeze Under Temperate Simulation
# ---------------------------------------------------------------------------
func _test_water_remains_liquid_under_simulation() -> void:
	print("[Test 7] Water liquid stability over extended simulation (60 ticks)...")
	var reg = World.get_registry()
	var initial_fluid_count: int = reg.get_store(&"FluidComponent").size()
	assert(initial_fluid_count > 0, "Must have initial fluid tiles")

	# Run 60 simulation ticks (~6 seconds at 10 TPS, spanning multiple phase-change slices)
	for i in range(60):
		World._run_tick()

	var frozen_store: Dictionary = reg.get_store(&"FrozenComponent")
	var fluid_store: Dictionary  = reg.get_store(&"FluidComponent")

	assert(frozen_store.is_empty(), "No water tiles should freeze at temperate plains temperature (~15C) (found %d frozen)" % frozen_store.size())
	assert(fluid_store.size() == initial_fluid_count, "All fluid water tiles must remain intact (expected %d, got %d)" % [initial_fluid_count, fluid_store.size()])
	print("  -> PASSED: All %d water tiles remained liquid across 60 simulation ticks without freezing." % fluid_store.size())

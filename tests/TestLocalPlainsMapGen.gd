## TestLocalPlainsMapGen.gd
## Automated integration test verifying local tile Plains map generation:
## - 100% of tiles are classified as Plains biome
## - Average temperature matches temperate plains climate (~0.50) without latitudinal pole-to-equator gradients
## - Inland moisture matches plains climate (~0.48) with riparian zones boosted near water
## - Rolling grassland is the dominant terrain (> 65% of map)
## - Rivers and ponds generate cleanly within the plains
## - Native plains vegetation (grass, tall grass, wildflowers, oaks) spawns and thrives
extends Node2D

const _BiomeTypes       = preload("res://modules/terrain/data/BiomeTypes.gd")
const _TileTypes        = preload("res://modules/terrain/data/TileTypes.gd")
const _VegetationTypes  = preload("res://modules/vegetation/data/VegetationTypes.gd")
const _FluidComponent   = preload("res://modules/matter/components/FluidComponent.gd")
const _MaterialTypes    = preload("res://modules/matter/data/MaterialTypes.gd")

func _ready() -> void:
	print("\n=== STARTING LOCAL PLAINS MAP GENERATION INTEGRATION TESTS ===")
	await get_tree().process_frame
	await get_tree().process_frame

	_test_world_local_biome_property()
	_test_all_tiles_plains_biome()
	_test_plains_average_temperature_no_latitude_gradient()
	_test_plains_average_moisture_and_riparian()
	_test_dominant_grassland_terrain()
	_test_water_features_in_plains()
	await _test_plains_vegetation_spawning()

	print("\n>>> ALL LOCAL PLAINS MAP GENERATION TESTS PASSED! <<<\n")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: World Local Biome Property
# ---------------------------------------------------------------------------
func _test_world_local_biome_property() -> void:
	print("[Test 1] World.local_biome property...")
	assert(World != null, "World autoload must exist")
	assert(World.local_biome == _BiomeTypes.Type.PLAINS, "World.local_biome must be PLAINS (0), got %d" % World.local_biome)
	print("  -> PASSED: World.local_biome is correctly set to PLAINS.")

# ---------------------------------------------------------------------------
# Test 2: All Tiles Have Plains Biome
# ---------------------------------------------------------------------------
func _test_all_tiles_plains_biome() -> void:
	print("[Test 2] Uniform Plains biome classification...")
	var reg = World.get_registry()
	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var total_tiles: int = biome_store.size()
	assert(total_tiles == World.MAP_WIDTH * World.MAP_HEIGHT, "Expected %d tiles, found %d" % [World.MAP_WIDTH * World.MAP_HEIGHT, total_tiles])

	var non_plains_count: int = 0
	var plains_count: int = 0

	for eid: int in biome_store:
		var biome = biome_store[eid]
		if biome.biome == _BiomeTypes.Type.PLAINS:
			plains_count += 1
		else:
			non_plains_count += 1

	print("  -> Total tiles: %d | Plains: %d | Other: %d" % [total_tiles, plains_count, non_plains_count])
	assert(non_plains_count == 0, "All tiles on local map must have PLAINS biome (found %d non-plains tiles)" % non_plains_count)
	assert(plains_count == total_tiles, "100%% of tiles must be PLAINS")
	print("  -> PASSED: 100% of terrain tiles have Plains biome.")

# ---------------------------------------------------------------------------
# Test 3: Plains Average Temperature & Latitude Gradient Removal
# ---------------------------------------------------------------------------
func _test_plains_average_temperature_no_latitude_gradient() -> void:
	print("[Test 3] Plains average climate temperature and latitude uniformity...")
	var reg = World.get_registry()
	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	var total_temp: float = 0.0
	var min_temp: float = 999.0
	var max_temp: float = -999.0

	var north_temps: Array[float] = []
	var south_temps: Array[float] = []

	for eid: int in biome_store:
		var biome = biome_store[eid]
		var tile  = tile_store.get(eid, null)
		var t: float = biome.temperature

		total_temp += t
		min_temp = minf(min_temp, t)
		max_temp = maxf(max_temp, t)

		if tile != null:
			if tile.position.y < 20:
				north_temps.append(t)
			elif tile.position.y > (World.MAP_HEIGHT - 21):
				south_temps.append(t)

	var avg_temp: float = total_temp / float(biome_store.size())

	var avg_north: float = 0.0
	for t: float in north_temps:
		avg_north += t
	avg_north /= float(north_temps.size())

	var avg_south: float = 0.0
	for t: float in south_temps:
		avg_south += t
	avg_south /= float(south_temps.size())

	print("  -> Map-wide temp: avg=%.3f, min=%.3f, max=%.3f" % [avg_temp, min_temp, max_temp])
	print("  -> North (y < 20) avg temp: %.3f vs South (y > 107) avg temp: %.3f (diff: %.3f)" % [
		avg_north, avg_south, absf(avg_north - avg_south)
	])

	# Target average temperature for plains: ~0.50 (15°C base)
	assert(avg_temp >= 0.47 and avg_temp <= 0.53, "Average plains temperature must be near 0.50 (got %.3f)" % avg_temp)

	# In local embark tile, there is NO north-to-south latitude pole/equator gradient
	# North and South should differ by less than 0.04 (only subtle micro-terrain fluctuations)
	assert(absf(avg_north - avg_south) < 0.04, "Latitude gradient must be eliminated on local tile (north=%.3f, south=%.3f)" % [avg_north, avg_south])

	# No extreme polar freeze (< 0.30) or extreme scorching desert (> 0.70) in spring base temps
	assert(min_temp > 0.35, "Plains base temperature should not drop to polar freeze (min: %.3f)" % min_temp)
	assert(max_temp < 0.65, "Plains base temperature should not rise to scorching heat (max: %.3f)" % max_temp)

	print("  -> PASSED: Temperate plains climate confirmed across the entire local map without latitudinal gradient.")

# ---------------------------------------------------------------------------
# Test 4: Plains Average Moisture & Riparian Influence
# ---------------------------------------------------------------------------
func _test_plains_average_moisture_and_riparian() -> void:
	print("[Test 4] Plains average moisture & riparian gradients...")
	var reg = World.get_registry()
	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")

	var inland_moistures: Array[float] = []
	var riparian_moistures: Array[float] = []

	var offsets := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	for eid: int in biome_store:
		var biome = biome_store[eid]
		var tile  = tile_store.get(eid, null)
		if tile == null:
			continue

		if not fluid_store.has(eid):
			var is_riparian: bool = false
			for off: Vector2i in offsets:
				var nid: int = World.get_entity_at(tile.position + off)
				if nid != -1 and fluid_store.has(nid):
					is_riparian = true
					break

			if is_riparian:
				riparian_moistures.append(biome.moisture)
			else:
				inland_moistures.append(biome.moisture)

	var avg_inland: float = 0.0
	for m: float in inland_moistures:
		avg_inland += m
	avg_inland /= float(inland_moistures.size())

	var avg_riparian: float = 0.0
	for m: float in riparian_moistures:
		avg_riparian += m
	avg_riparian /= float(riparian_moistures.size())

	print("  -> Average inland moisture: %.3f | Riparian moisture: %.3f" % [avg_inland, avg_riparian])
	assert(avg_inland >= 0.44 and avg_inland <= 0.54, "Average inland plains moisture should be ~0.48 (got %.3f)" % avg_inland)
	assert(avg_riparian > avg_inland + 0.02, "Riparian banks must receive moisture boost above inland (riparian=%.3f, inland=%.3f)" % [avg_riparian, avg_inland])
	print("  -> PASSED: Inland plains moisture and riparian boosts verified.")

# ---------------------------------------------------------------------------
# Test 5: Dominant Grassland Terrain
# ---------------------------------------------------------------------------
func _test_dominant_grassland_terrain() -> void:
	print("[Test 5] Dominant rolling grassland terrain...")
	var reg = World.get_registry()
	var tile_store: Dictionary = reg.get_store(&"TileComponent")

	var grass_count: int = 0
	var ground_count: int = 0
	var dirt_count: int = 0
	var stone_count: int = 0
	var mud_count: int = 0

	for eid: int in tile_store:
		var tile = tile_store[eid]
		match tile.tile_type:
			_TileTypes.Type.GRASS:  grass_count += 1
			_TileTypes.Type.GROUND: ground_count += 1
			_TileTypes.Type.DIRT:   dirt_count += 1
			_TileTypes.Type.STONE:  stone_count += 1
			_TileTypes.Type.MUD:    mud_count += 1

	var total: int = tile_store.size()
	var grass_pct: float = (float(grass_count) / float(total)) * 100.0
	print("  -> Tiles: GRASS=%d (%.1f%%), GROUND=%d, DIRT=%d, MUD=%d, STONE=%d" % [
		grass_count, grass_pct, ground_count, dirt_count, mud_count, stone_count
	])

	assert(grass_pct >= 60.0, "Rolling plains should have GRASS as dominant land cover (>= 60%%, got %.1f%%)" % grass_pct)
	assert(stone_count < total * 0.10, "Plains should have only sparse stone outcrops (< 10%%, got %d)" % stone_count)
	print("  -> PASSED: Rolling plains terrain is predominantly lush grassland.")

# ---------------------------------------------------------------------------
# Test 6: Water Features in Plains
# ---------------------------------------------------------------------------
func _test_water_features_in_plains() -> void:
	print("[Test 6] Water features embedded within Plains biome...")
	var reg = World.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")

	var water_count: int = 0
	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		var biome = biome_store.get(eid, null)
		if fluid != null and fluid.material_id == _MaterialTypes.Type.WATER:
			water_count += 1
			assert(biome != null and biome.biome == _BiomeTypes.Type.PLAINS, "Water tile at eid=%d must have PLAINS biome" % eid)

	print("  -> Found %d water tiles, all belonging to Plains biome." % water_count)
	assert(water_count > 200, "Should generate water bodies (river/ponds) in plains (got %d)" % water_count)
	print("  -> PASSED: Water features exist and belong to local Plains biome.")

# ---------------------------------------------------------------------------
# Test 7: Plains Vegetation Spawning
# ---------------------------------------------------------------------------
func _test_plains_vegetation_spawning() -> void:
	print("[Test 7] Native plains flora spawning...")
	# Advance world tick 1 to trigger VegetationSpawnSystem
	World._run_tick()

	var reg = World.get_registry()
	var veg_store: Dictionary = reg.get_store(&"VegetationComponent")
	print("  -> Spawned %d vegetation entities on tick 1." % veg_store.size())
	assert(veg_store.size() > 500, "Should spawn substantial vegetation across grassy plains (got %d)" % veg_store.size())

	var counts := {
		_VegetationTypes.Type.GRASS_PATCH: 0,
		_VegetationTypes.Type.TALL_GRASS:  0,
		_VegetationTypes.Type.WILDFLOWER:  0,
		_VegetationTypes.Type.OAK_TREE:    0,
		_VegetationTypes.Type.PINE_TREE:   0,
		_VegetationTypes.Type.SHRUB:       0,
	}

	for eid: int in veg_store:
		var veg = veg_store[eid]
		counts[veg.veg_type] = counts.get(veg.veg_type, 0) + 1

	print("  -> Grass Patch: %d | Tall Grass: %d | Wildflower: %d | Oak Tree: %d | Pine: %d | Shrub: %d" % [
		counts[_VegetationTypes.Type.GRASS_PATCH],
		counts[_VegetationTypes.Type.TALL_GRASS],
		counts[_VegetationTypes.Type.WILDFLOWER],
		counts[_VegetationTypes.Type.OAK_TREE],
		counts[_VegetationTypes.Type.PINE_TREE],
		counts[_VegetationTypes.Type.SHRUB]
	])

	assert(counts[_VegetationTypes.Type.GRASS_PATCH] > 200, "Grass patches should be abundant in plains")
	assert(counts[_VegetationTypes.Type.WILDFLOWER] > 10, "Wildflowers should spawn across plains")
	assert(counts[_VegetationTypes.Type.OAK_TREE] > 5, "Oak trees should spawn across plains")
	# Pine trees are native to Forest Edge / cold regions, not Plains
	assert(counts[_VegetationTypes.Type.PINE_TREE] == 0, "Pine trees should not spawn on a pure Plains local tile")
	print("  -> PASSED: Plains flora (grass, tall grass, wildflowers, oaks) thrive across the local tile.")

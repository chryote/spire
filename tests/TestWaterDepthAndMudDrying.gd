## TestWaterDepthAndMudDrying.gd
## Integration test for:
## 1. Dynamic Water Tile Depth (Approach B): WALKABLE vs SWIMMABLE signals and traversability
## 2. Mud Drying & Original Tile Reversion Mechanic
extends Node2D

const _TileAffordance = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes    = preload("res://modules/signal/data/SignalTypes.gd")
const _FluidComponent = preload("res://modules/matter/components/FluidComponent.gd")
const _MaterialTypes  = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes      = preload("res://modules/terrain/data/TileTypes.gd")

func _ready() -> void:
	print("\n=== STARTING WATER DEPTH & MUD DRYING INTEGRATION TESTS ===")
	await get_tree().process_frame
	await get_tree().process_frame

	var signals = World.signals
	assert(signals != null, "World.signals must be initialized!")

	_test_deep_water_affordance_and_traversability(signals)
	_test_shallow_water_affordance_and_traversability(signals)
	_test_puddle_affordance(signals)
	_test_mud_saturation_preserves_history(signals)
	_test_mud_submergence_guard(signals)
	_test_mud_drying_and_reversion(signals)

	print("\n>>> ALL WATER DEPTH & MUD DRYING TESTS PASSED! <<<\n")
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: Deep Water (volume >= 0.4) -> SWIMMABLE, not WALKABLE, trav = 0.4
# ---------------------------------------------------------------------------
func _test_deep_water_affordance_and_traversability(signals) -> void:
	print("[Test 1] Deep Water (volume >= 0.4)...")
	var test_pos = Vector2i(20, 20)
	var eid: int = World.get_entity_at(test_pos)

	var fl = _FluidComponent.new()
	fl.material_id = _MaterialTypes.Type.WATER
	fl.volume = 0.8
	fl.settled = true
	World.add_component(eid, fl)

	World._run_tick()

	assert(signals.has_affordance(test_pos, _TileAffordance.SWIMMABLE), "Deep water must be SWIMMABLE")
	assert(not signals.has_affordance(test_pos, _TileAffordance.WALKABLE), "Deep water must NOT be WALKABLE")
	var trav: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav, 0.4), "Deep water traversability must be 0.4 (actual: %f)" % trav)

	# Clean up
	World.remove_component(eid, &"FluidComponent")
	World._run_tick()
	print("  -> PASSED: Deep water sets SWIMMABLE, clears WALKABLE, and sets trav=0.4.")

# ---------------------------------------------------------------------------
# Test 2: Shallow Water (0.15 <= volume < 0.4) -> WALKABLE, HAZARD_SLOW, not SWIMMABLE, trav = 0.7
# ---------------------------------------------------------------------------
func _test_shallow_water_affordance_and_traversability(signals) -> void:
	print("[Test 2] Shallow Water (0.15 <= volume < 0.4)...")
	var test_pos = Vector2i(22, 22)
	var eid: int = World.get_entity_at(test_pos)

	var fl = _FluidComponent.new()
	fl.material_id = _MaterialTypes.Type.WATER
	fl.volume = 0.25
	fl.settled = true
	World.add_component(eid, fl)

	World._run_tick()

	assert(signals.has_affordance(test_pos, _TileAffordance.WALKABLE), "Shallow water must be WALKABLE")
	assert(signals.has_affordance(test_pos, _TileAffordance.HAZARD_SLOW), "Shallow water must have HAZARD_SLOW")
	assert(not signals.has_affordance(test_pos, _TileAffordance.SWIMMABLE), "Shallow water must NOT be SWIMMABLE")
	var trav: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav, 0.7), "Shallow water traversability must be 0.7 (actual: %f)" % trav)

	# Clean up
	World.remove_component(eid, &"FluidComponent")
	World._run_tick()
	print("  -> PASSED: Shallow water sets WALKABLE | HAZARD_SLOW, no SWIMMABLE, and sets trav=0.7.")

# ---------------------------------------------------------------------------
# Test 3: Minor Puddle (< 0.15) -> WALKABLE, not SWIMMABLE, not HAZARD_SLOW
# ---------------------------------------------------------------------------
func _test_puddle_affordance(signals) -> void:
	print("[Test 3] Minor Puddle (< 0.15)...")
	var test_pos = Vector2i(24, 24)
	var eid: int = World.get_entity_at(test_pos)

	var fl = _FluidComponent.new()
	fl.material_id = _MaterialTypes.Type.WATER
	fl.volume = 0.08
	fl.settled = true
	World.add_component(eid, fl)

	World._run_tick()

	assert(signals.has_affordance(test_pos, _TileAffordance.WALKABLE), "Puddle must be WALKABLE")
	assert(not signals.has_affordance(test_pos, _TileAffordance.SWIMMABLE), "Puddle must NOT be SWIMMABLE")

	# Clean up
	World.remove_component(eid, &"FluidComponent")
	World._run_tick()
	print("  -> PASSED: Puddle retains normal WALKABLE without swimming penalty.")

# ---------------------------------------------------------------------------
# Test 4: Mud Saturation Preserves Original Tile Type
# ---------------------------------------------------------------------------
func _test_mud_saturation_preserves_history(signals) -> void:
	print("[Test 4] Mud Saturation & History Preservation...")
	var reg = World.get_registry()
	var test_pos = Vector2i(30, 30)
	var eid: int = World.get_entity_at(test_pos)
	var tile = reg.get_component(eid, &"TileComponent")
	var biome = reg.get_component(eid, &"BiomeComponent")

	# Ensure starting state is GRASS
	tile.tile_type = _TileTypes.Type.GRASS
	tile.original_tile_type = -1
	signals.notify_tile_type_changed(test_pos, _TileTypes.Type.GRASS)

	# Simulate rain saturation
	biome.moisture = 1.0
	World.rain_allowed = true
	var orig_wind: float = World.wind_strength
	World.wind_strength = 10.0  # Guarantees threshold < 0 so is_raining is true

	# Run tick of RainSystem
	var rain_sys = null
	for sys in World._sim_systems:
		if sys.get_script().resource_path.ends_with("RainSystem.gd"):
			rain_sys = sys
			break
	assert(rain_sys != null, "RainSystem must exist in World._sim_systems")

	# Tick entity directly via slice
	var slice_mod: int = eid % rain_sys.SLICE_COUNT
	rain_sys.tick(slice_mod)
	World.wind_strength = orig_wind

	# Verify transition to MUD
	assert(tile.tile_type == _TileTypes.Type.MUD, "Tile must convert to MUD upon saturation")
	assert(tile.original_tile_type == _TileTypes.Type.GRASS, "Tile must record original_tile_type == GRASS")
	assert(signals.has_affordance(test_pos, _TileAffordance.HAZARD_SLOW), "Mud tile must have HAZARD_SLOW affordance")
	var trav: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav, 0.6), "Mud traversability must be 0.6")

	print("  -> PASSED: Flooding correctly converts tile to MUD and records pre-flood type.")

# ---------------------------------------------------------------------------
# Test 5: Mud Submergence Guard (Does not dry if submerged)
# ---------------------------------------------------------------------------
func _test_mud_submergence_guard(_signals) -> void:
	print("[Test 5] Mud Submergence Guard...")
	var reg = World.get_registry()
	var test_pos = Vector2i(30, 30)
	var eid: int = World.get_entity_at(test_pos)
	var tile = reg.get_component(eid, &"TileComponent")
	var biome = reg.get_component(eid, &"BiomeComponent")

	# Add standing water layer on top of mud
	var fl = _FluidComponent.new()
	fl.material_id = _MaterialTypes.Type.WATER
	fl.volume = 0.5
	World.add_component(eid, fl)

	# Drop soil moisture below dry threshold
	biome.moisture = 0.4
	World.rain_allowed = false

	var rain_sys = null
	for sys in World._sim_systems:
		if sys.get_script().resource_path.ends_with("RainSystem.gd"):
			rain_sys = sys
			break

	var slice_mod: int = eid % rain_sys.SLICE_COUNT
	rain_sys.tick(slice_mod)

	# Must remain MUD because it is submerged!
	assert(tile.tile_type == _TileTypes.Type.MUD, "Mud under standing water must NOT revert even if moisture is low")
	assert(tile.original_tile_type == _TileTypes.Type.GRASS, "original_tile_type must be preserved while submerged")

	# Clean up standing water
	World.remove_component(eid, &"FluidComponent")
	print("  -> PASSED: Submerged mud does not prematurely dry out.")

# ---------------------------------------------------------------------------
# Test 6: Mud Drying & Reversion to Original Tile
# ---------------------------------------------------------------------------
func _test_mud_drying_and_reversion(signals) -> void:
	print("[Test 6] Mud Drying & Original Tile Reversion...")
	var reg = World.get_registry()
	var test_pos = Vector2i(30, 30)
	var eid: int = World.get_entity_at(test_pos)
	var tile = reg.get_component(eid, &"TileComponent")
	var biome = reg.get_component(eid, &"BiomeComponent")
	var render = reg.get_component(eid, &"RenderComponent")
	var matter = reg.get_component(eid, &"MatterComponent")

	# Soil is dry (not submerged, moisture <= 0.65)
	biome.moisture = 0.5
	World.rain_allowed = false

	var rain_sys = null
	for sys in World._sim_systems:
		if sys.get_script().resource_path.ends_with("RainSystem.gd"):
			rain_sys = sys
			break

	var slice_mod: int = eid % rain_sys.SLICE_COUNT
	rain_sys.tick(slice_mod)

	# Must revert to GRASS!
	assert(tile.tile_type == _TileTypes.Type.GRASS, "Tile must revert back to GRASS after drying (actual: %d)" % tile.tile_type)
	assert(tile.original_tile_type == -1, "original_tile_type must reset to -1 after restoration")
	if matter != null:
		assert(matter.material_id == _MaterialTypes.Type.GRASS_TURF, "Matter material must revert to GRASS_TURF")

	# Render visual glyph restored
	var td: Dictionary = _TileTypes.get_data(_TileTypes.Type.GRASS)
	assert(render.glyph == td["glyph"], "Render glyph must revert to original grass glyph")

	# Signals restored
	World._run_tick()
	assert(signals.has_affordance(test_pos, _TileAffordance.WALKABLE), "Restored grass must be WALKABLE")
	assert(not signals.has_affordance(test_pos, _TileAffordance.HAZARD_SLOW), "Restored grass must NOT have HAZARD_SLOW")
	var trav: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav, 1.0), "Restored grass traversability must be 1.0 (actual: %f)" % trav)

	print("  -> PASSED: Mud tile successfully dried and reverted to original tile with restored signals and visuals.")

## TestGrassWaterContent.gd
## Integration test suite for grass holding water material and creature hydration.
extends Node2D

const _MaterialTypes      = preload("res://modules/matter/data/MaterialTypes.gd")
const _MatterComponent    = preload("res://modules/matter/components/MatterComponent.gd")
const _ItemTypes          = preload("res://modules/item/data/ItemTypes.gd")
const _ItemComponent      = preload("res://modules/item/components/ItemComponent.gd")
const _InventoryComponent = preload("res://modules/item/components/InventoryComponent.gd")
const _ItemFactory        = preload("res://modules/item/systems/ItemFactory.gd")
const _CreatureFactory    = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes      = preload("res://modules/creature/data/CreatureTypes.gd")
const _MindComponent      = preload("res://modules/creature/components/mind/MindComponent.gd")
const _PositionComponent  = preload("res://modules/creature/components/PositionComponent.gd")

func _ready() -> void:
	print("\n=== STARTING GRASS WATER MATERIAL & CREATURE HYDRATION TESTS ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	_test_grass_mold_archetype()
	_test_single_material_backward_compatibility()
	_test_fresh_grass_composite_and_physical_synthesis()
	_test_grass_stacking_separation()
	_test_creature_graze_quenches_thirst_with_fresh_grass()
	_test_creature_graze_dry_grass_no_thirst_quench()

	print("\n>>> ALL GRASS WATER MATERIAL & HYDRATION TESTS PASSED! <<<\n")
	var log_file = FileAccess.open("res://logs/test_grass_water_content.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("PASSED: Grass item mold supports water material, physical synthesis, and quenches creature thirst.\n")
		log_file.close()

	World.paused = false
	get_tree().quit(0)

func _test_grass_mold_archetype() -> void:
	print("[Test 1] Verifying Grass Mold Archetype in ItemTypes...")
	var mold = _ItemTypes.get_data(_ItemTypes.Type.GRASS)
	assert(mold != null, "Grass archetype mold must exist")
	assert(mold.has("parts"), "Grass mold must have parts definition")

	var parts: Dictionary = mold["parts"]
	assert(parts.has("main"), "Grass mold must have 'main' part")
	assert(parts.has("water"), "Grass mold must have 'water' part")

	var water_part: Dictionary = parts["water"]
	assert(water_part["role"] == _ItemTypes.PartRole.CONTAINER, "Water part role must be CONTAINER")
	assert(_MaterialTypes.Type.WATER in water_part["valid_matters"], "Water part must accept WATER material")
	assert(water_part.get("optional", false) == true, "Water part must be optional for dry grass")
	assert(water_part["volume"] > 0.0, "Water part volume must be positive")
	print("  -> PASSED: Grass mold archetype correctly defines CONTAINER water part.")

func _test_single_material_backward_compatibility() -> void:
	print("[Test 2] Verifying Single-Material Creation Backward Compatibility...")
	var grass_eid = _ItemFactory.create(World, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, 5)
	var comp: _ItemComponent = World.get_component(grass_eid, &"ItemComponent")
	var matter: _MatterComponent = World.get_component(grass_eid, &"MatterComponent")

	assert(comp != null, "ItemComponent must be attached")
	assert(matter != null, "MatterComponent must be attached")
	assert(comp.display_name == "Organic Grass", "Single-material grass display name must remain 'Organic Grass' (was: %s)" % comp.display_name)
	assert(comp.parts.has("main"), "Single-material grass must have 'main' part")
	assert(not comp.parts.has("water"), "Single-material grass should not forcibly include optional water part")
	print("  -> PASSED: Single-material grass is 100%% backward compatible ('%s')." % comp.display_name)

func _test_fresh_grass_composite_and_physical_synthesis() -> void:
	print("[Test 3] Verifying Fresh Grass with Water Material & Physical Synthesis...")
	var fresh_eid = _ItemFactory.create_grass(World, true, 1)
	var comp: _ItemComponent = World.get_component(fresh_eid, &"ItemComponent")
	var matter: _MatterComponent = World.get_component(fresh_eid, &"MatterComponent")

	assert(comp != null and matter != null, "Components must exist")
	assert(comp.display_name == "Fresh Organic Grass", "Fresh grass display name must be 'Fresh Organic Grass' (was: %s)" % comp.display_name)
	assert(comp.parts.has("main"), "Must have main part")
	assert(comp.parts.has("water"), "Must have water part")
	assert(comp.parts["water"]["material_id"] == _MaterialTypes.Type.WATER, "Water part must hold WATER material")

	# Physical properties check:
	# Main: 0.00006 m3 * 200 kg/m3 = 0.012 kg
	# Water: 0.00004 m3 * 1000 kg/m3 = 0.040 kg
	# Total mass: 0.052 kg
	assert(is_equal_approx(comp.total_mass, 0.052), "Fresh grass mass must equal plant + water mass (actual: %f)" % comp.total_mass)
	# Moisture: (0.012 * 0.55 + 0.040 * 1.0) / 0.052 = 0.0466 / 0.052 ≈ 0.896
	assert(matter.moisture > 0.85, "Fresh grass moisture should be ~0.896 (actual: %f)" % matter.moisture)
	# Specific heat: weighted average should be high (> 3000 J/kg) due to water
	assert(matter.specific_heat > 3000.0, "Specific heat should reflect high water content (actual: %f)" % matter.specific_heat)

	print("  -> PASSED: Fresh grass created with mass=%.3f kg, moisture=%.3f, specific_heat=%.1f J/kg." % [
		comp.total_mass, matter.moisture, matter.specific_heat
	])

func _test_grass_stacking_separation() -> void:
	print("[Test 4] Verifying Stacking Separation between Fresh and Dry Grass...")
	var fresh_eid = _ItemFactory.create_grass(World, true, 5)
	var dry_eid   = _ItemFactory.create_grass(World, false, 5)

	var fresh_comp: _ItemComponent = World.get_component(fresh_eid, &"ItemComponent")
	var _dry_comp: _ItemComponent  = World.get_component(dry_eid, &"ItemComponent")

	# Fresh can stack with fresh
	assert(fresh_comp.can_stack_with(_ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, {
		"main": _MaterialTypes.Type.ORGANIC,
		"water": _MaterialTypes.Type.WATER,
	}), "Fresh grass must be stackable with other fresh grass")

	# Fresh cannot stack with dry (missing water part)
	assert(not fresh_comp.can_stack_with(_ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, {
		"main": _MaterialTypes.Type.ORGANIC,
	}), "Fresh grass must NOT stack with dry grass missing water")

	# Fresh cannot stack with kindling
	assert(not fresh_comp.can_stack_with(_ItemTypes.Type.GRASS, _MaterialTypes.Type.KINDLING), "Fresh grass must not stack with kindling")

	print("  -> PASSED: Stacking rules preserve physical distinction of water content.")

func _test_creature_graze_quenches_thirst_with_fresh_grass() -> void:
	print("[Test 5] Verifying Creature Grazing on Fresh Grass Quenches Both Hunger & Thirst...")
	var reg = World.get_registry()

	# Create a walkable test tile entity
	var test_pos := Vector2i(10, 10)
	var tile_eid: int = World.get_entity_at(test_pos)
	if tile_eid == -1:
		tile_eid = World.create_entity()

	# Clear any previous inventory items
	var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		inv.container_id = tile_eid
		World.add_component(tile_eid, inv)
	inv.clear_items()

	# Deposit fresh grass holding water into inventory
	_ItemFactory.create_and_deposit_grass(World, tile_eid, true, 3)
	assert(inv.get_total_quantity_of_type(reg, _ItemTypes.Type.GRASS) == 3, "Inventory must have 3 fresh grass items")

	# Spawn grazer creature at this tile
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, test_pos, "ThirstyGrazer")
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")
	assert(mind != null, "MindComponent must exist")

	# Set high hunger and thirst
	mind.hunger = 0.85
	mind.thirst = 0.85
	var initial_hunger: float = mind.hunger
	var initial_thirst: float = mind.thirst

	# Run a simulation tick to trigger locomotion and grazing
	World._run_tick()

	print("[Test 5] Hunger: %.2f -> %.2f, Thirst: %.2f -> %.2f" % [
		initial_hunger, mind.hunger, initial_thirst, mind.thirst
	])

	assert(mind.hunger < initial_hunger, "Hunger must decrease after grazing fresh grass")
	assert(mind.thirst < initial_thirst - 0.15, "Thirst must decrease after grazing fresh grass with water (was: %.2f, now: %.2f)" % [
		initial_thirst, mind.thirst
	])
	assert(is_equal_approx(mind.thirst, initial_thirst + 0.003 - 0.20), "Thirst reduction should equal 0.20 (net of 0.003 metabolic tick)")
	print("  -> PASSED: Creature successfully quenched hunger AND thirst from fresh grass holding water material.")

func _test_creature_graze_dry_grass_no_thirst_quench() -> void:
	print("[Test 6] Verifying Creature Grazing on Dry Grass Does NOT Quench Thirst...")
	var reg = World.get_registry()

	var test_pos := Vector2i(12, 12)
	var tile_eid: int = World.get_entity_at(test_pos)
	if tile_eid == -1:
		tile_eid = World.create_entity()

	var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		inv.container_id = tile_eid
		World.add_component(tile_eid, inv)
	inv.clear_items()

	# Deposit dry grass (no water)
	_ItemFactory.create_and_deposit_grass(World, tile_eid, false, 3)
	assert(inv.get_total_quantity_of_type(reg, _ItemTypes.Type.GRASS) == 3, "Inventory must have 3 dry grass items")

	# Spawn grazer creature at this tile
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, test_pos, "DryGrazer")
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")

	mind.hunger = 0.85
	mind.thirst = 0.85
	var initial_hunger: float = mind.hunger
	var initial_thirst: float = mind.thirst

	World._run_tick()

	print("[Test 6] Dry Grass - Hunger: %.2f -> %.2f, Thirst: %.2f -> %.2f" % [
		initial_hunger, mind.hunger, initial_thirst, mind.thirst
	])

	assert(mind.hunger < initial_hunger, "Hunger must decrease after eating dry grass")
	assert(mind.thirst >= initial_thirst, "Thirst must NOT decrease when eating dry grass without water")
	print("  -> PASSED: Eating dry grass satisfied hunger while leaving thirst unquenched.")

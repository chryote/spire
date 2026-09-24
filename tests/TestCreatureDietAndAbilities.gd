## TestCreatureDietAndAbilities.gd
## Integration test verifying:
## 1. Food matter diet categorization (HERBIVORE, OMNIVORE, CARNIVORE).
## 2. Creature diet tendencies and compatibility filtering.
## 3. Universal Action.EAT AI evaluation and execution.
## 4. Decoupled execution between CreatureLocomotionSystem and CreatureAbilitySystem.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE DIET & ABILITY SYSTEM INTEGRATION TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	_test_matter_diet_categories()
	_test_diet_compatibility_matrix()
	_test_decoupled_locomotion_and_ability_systems()
	_test_herbivore_refuses_meat_and_eats_vegetation()
	_test_carnivore_eats_meat_and_refuses_vegetation()
	_test_omnivore_eats_both()

	print("\n>>> ALL CREATURE DIET & ABILITY TESTS PASSED! <<<\n")
	World.paused = false
	get_tree().quit(0)

func _test_matter_diet_categories() -> void:
	print("[Test 1] Testing Matter Food Classification...")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.ORGANIC) == _DietTypes.Category.HERBIVORE, "Organic must be HERBIVORE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.GRASS_TURF) == _DietTypes.Category.HERBIVORE, "Grass turf must be HERBIVORE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.KINDLING) == _DietTypes.Category.HERBIVORE, "Kindling must be HERBIVORE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.RAW_MEAT) == _DietTypes.Category.CARNIVORE, "Raw meat must be CARNIVORE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.BONE) == _DietTypes.Category.CARNIVORE, "Bone must be CARNIVORE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.ANIMAL_BLOOD) == _DietTypes.Category.CARNIVORE, "Animal blood must be CARNIVORE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.STONE) == _DietTypes.Category.NONE, "Stone must be NONE")
	assert(_MaterialTypes.get_diet_category(_MaterialTypes.Type.STEEL) == _DietTypes.Category.NONE, "Steel must be NONE")
	print("  -> PASSED: Matter dietary categorization verified.")

func _test_diet_compatibility_matrix() -> void:
	print("[Test 2] Testing Diet Compatibility Matrix...")
	# Herbivore
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.HERBIVORE, _DietTypes.Category.HERBIVORE), "Herbivore can eat herbivore food")
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.HERBIVORE, _DietTypes.Category.OMNIVORE), "Herbivore can eat omnivore food")
	assert(not _DietTypes.can_creature_eat(_DietTypes.Category.HERBIVORE, _DietTypes.Category.CARNIVORE), "Herbivore CANNOT eat carnivore food")
	assert(not _DietTypes.can_creature_eat(_DietTypes.Category.HERBIVORE, _DietTypes.Category.NONE), "Herbivore CANNOT eat non-food")

	# Carnivore
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.CARNIVORE, _DietTypes.Category.CARNIVORE), "Carnivore can eat carnivore food")
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.CARNIVORE, _DietTypes.Category.OMNIVORE), "Carnivore can eat omnivore food")
	assert(not _DietTypes.can_creature_eat(_DietTypes.Category.CARNIVORE, _DietTypes.Category.HERBIVORE), "Carnivore CANNOT eat herbivore food")

	# Omnivore
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.OMNIVORE, _DietTypes.Category.HERBIVORE), "Omnivore can eat herbivore food")
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.OMNIVORE, _DietTypes.Category.CARNIVORE), "Omnivore can eat carnivore food")
	assert(_DietTypes.can_creature_eat(_DietTypes.Category.OMNIVORE, _DietTypes.Category.OMNIVORE), "Omnivore can eat omnivore food")
	assert(not _DietTypes.can_creature_eat(_DietTypes.Category.OMNIVORE, _DietTypes.Category.NONE), "Omnivore CANNOT eat non-food")
	print("  -> PASSED: Diet compatibility matrix verified.")

func _test_decoupled_locomotion_and_ability_systems() -> void:
	print("[Test 3] Testing Decoupled Locomotion & Ability Execution...")
	var reg = World.get_registry()
	var test_pos := Vector2i(20, 20)
	var target_pos := Vector2i(20, 21)

	var eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, test_pos, "Pacer")
	var pos_comp: _PositionComponent = reg.get_component(eid, &"PositionComponent")
	var plan: _ActionPlanComponent   = reg.get_component(eid, &"ActionPlanComponent")
	var mind: _MindComponent         = reg.get_component(eid, &"MindComponent")

	mind.hunger = 0.80
	var before_hunger: float = mind.hunger
	plan.current_goal = _MindEmbeddings.Action.EAT
	plan.target_tile = target_pos
	plan.path_queue = [target_pos]

	# Tick Locomotion ONLY
	World.creature_locomotion.tick(World.tick_count)

	# Locomotion moved creature to target_pos
	assert(pos_comp.position == target_pos, "Locomotion system must step creature to target tile")
	# But locomotion alone must NOT execute the action (hunger unchanged)
	assert(mind.hunger == before_hunger, "Locomotion system must NOT execute eating action")

	World.destroy_entity(eid)
	print("  -> PASSED: Locomotion strictly navigates without executing abilities.")

func _get_or_create_inv(reg, tile_eid: int) -> _InventoryComponent:
	var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		inv.container_id = tile_eid
		reg.add(tile_eid, inv)
	return inv

func _test_herbivore_refuses_meat_and_eats_vegetation() -> void:
	print("[Test 4] Testing Herbivore Refuses Meat & Eats Vegetation...")
	var reg = World.get_registry()
	var p := Vector2i(25, 25)

	# Place raw meat item on tile
	var tile_eid: int = World.get_entity_at(p)
	var meat_eid: int = _ItemFactory.create(World, _ItemTypes.Type.ORGAN, _MaterialTypes.Type.RAW_MEAT)
	var inv: _InventoryComponent = _get_or_create_inv(reg, tile_eid)
	inv.items.append(meat_eid)
	inv.update_cache(reg)

	var herb_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "StrictHerbivore")
	var creature: _CreatureComponent = reg.get_component(herb_eid, &"CreatureComponent")
	var mind: _MindComponent         = reg.get_component(herb_eid, &"MindComponent")
	var plan: _ActionPlanComponent   = reg.get_component(herb_eid, &"ActionPlanComponent")
	creature.diet = _DietTypes.Category.HERBIVORE
	mind.hunger = 0.85
	var before_herb_hunger: float = mind.hunger
	plan.current_goal = _MindEmbeddings.Action.EAT
	plan.target_tile = p

	# Tick AbilitySystem directly
	World.creature_abilities.tick(World.tick_count)

	# Herbivore must NOT eat the meat
	assert(mind.hunger == before_herb_hunger, "Herbivore must refuse raw meat; hunger must remain unchanged")
	assert(inv.items.has(meat_eid), "Meat item must remain intact in inventory")

	# Clean up meat
	inv.remove_item(meat_eid)
	World.destroy_entity(meat_eid)

	# Now add living vegetation to tile
	var veg = _VegetationComponent.new()
	veg.veg_type = 0
	veg.growth_stage = 2
	reg.add(tile_eid, veg)

	# Tick AbilitySystem on grass
	World.creature_abilities.tick(World.tick_count)
	assert(mind.hunger < before_herb_hunger, "Herbivore must eat living vegetation; hunger must decrease")
	assert(veg.growth_stage == 1, "Vegetation stage must decrement from 2 to 1")

	# Cleanup
	reg.remove(tile_eid, &"VegetationComponent")
	World.destroy_entity(herb_eid)
	print("  -> PASSED: Herbivore dietary constraints verified.")

func _test_carnivore_eats_meat_and_refuses_vegetation() -> void:
	print("[Test 5] Testing Carnivore Eats Meat & Refuses Vegetation...")
	var reg = World.get_registry()
	var p := Vector2i(30, 30)
	var tile_eid: int = World.get_entity_at(p)

	# Add living vegetation
	var veg = _VegetationComponent.new()
	veg.veg_type = 0
	veg.growth_stage = 2
	reg.add(tile_eid, veg)

	var carn_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "LoneCarnivore")
	var creature: _CreatureComponent = reg.get_component(carn_eid, &"CreatureComponent")
	var mind: _MindComponent         = reg.get_component(carn_eid, &"MindComponent")
	var plan: _ActionPlanComponent   = reg.get_component(carn_eid, &"ActionPlanComponent")
	creature.diet = _DietTypes.Category.CARNIVORE
	mind.hunger = 0.85
	var before_carn_hunger: float = mind.hunger
	plan.current_goal = _MindEmbeddings.Action.EAT
	plan.target_tile = p

	# Carnivore attempts to eat at tile with ONLY vegetation
	World.creature_abilities.tick(World.tick_count)
	assert(mind.hunger == before_carn_hunger, "Carnivore must refuse vegetation; hunger must remain unchanged")
	assert(veg.growth_stage == 2, "Vegetation must not be grazed by carnivore")

	# Now add raw meat item to tile inventory
	var meat_eid: int = _ItemFactory.create(World, _ItemTypes.Type.ORGAN, _MaterialTypes.Type.RAW_MEAT)
	var inv: _InventoryComponent = _get_or_create_inv(reg, tile_eid)
	inv.items.append(meat_eid)
	inv.update_cache(reg)

	# Carnivore attempts to eat at tile with meat item
	World.creature_abilities.tick(World.tick_count)
	assert(mind.hunger < 0.85, "Carnivore must eat raw meat item; hunger must decrease")
	assert(not inv.items.has(meat_eid), "Meat item must be consumed from inventory")

	# Cleanup
	reg.remove(tile_eid, &"VegetationComponent")
	World.destroy_entity(carn_eid)
	print("  -> PASSED: Carnivore dietary constraints verified.")

func _test_omnivore_eats_both() -> void:
	print("[Test 6] Testing Omnivore Eats Both Meat and Vegetation...")
	var reg = World.get_registry()
	var p := Vector2i(35, 35)
	var tile_eid: int = World.get_entity_at(p)

	var omni_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "AdaptiveOmnivore")
	var creature: _CreatureComponent = reg.get_component(omni_eid, &"CreatureComponent")
	var mind: _MindComponent         = reg.get_component(omni_eid, &"MindComponent")
	var plan: _ActionPlanComponent   = reg.get_component(omni_eid, &"ActionPlanComponent")
	creature.diet = _DietTypes.Category.OMNIVORE

	# 1. Omnivore eats meat
	var meat_eid: int = _ItemFactory.create(World, _ItemTypes.Type.ORGAN, _MaterialTypes.Type.RAW_MEAT)
	var inv: _InventoryComponent = _get_or_create_inv(reg, tile_eid)
	inv.items.append(meat_eid)
	inv.update_cache(reg)

	mind.hunger = 0.80
	plan.current_goal = _MindEmbeddings.Action.EAT
	plan.target_tile = p
	World.creature_abilities.tick(World.tick_count)
	assert(mind.hunger < 0.80, "Omnivore must eat meat")
	assert(not inv.items.has(meat_eid), "Meat must be consumed")

	# 2. Omnivore eats vegetation
	var veg = _VegetationComponent.new()
	veg.veg_type = 0
	veg.growth_stage = 2
	reg.add(tile_eid, veg)

	mind.hunger = 0.70
	plan.current_goal = _MindEmbeddings.Action.EAT
	plan.target_tile = p
	World.creature_abilities.tick(World.tick_count)
	assert(mind.hunger < 0.70, "Omnivore must eat vegetation")
	assert(veg.growth_stage == 1, "Vegetation stage must decrement")

	# Cleanup
	reg.remove(tile_eid, &"VegetationComponent")
	World.destroy_entity(omni_eid)
	print("  -> PASSED: Omnivore versatility verified.")

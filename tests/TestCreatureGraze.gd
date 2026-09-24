## TestCreatureGraze.gd
## Integration test verifying Creature module architecture:
## - Physical body anatomy (limbs, organs, blood made of items and matter)
## - Mind Utility AI (embedding vector state, action evaluation)
## - Locomotion, grass detection via SignalSystem, navigation, and grazing consumption
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")
const _MatterComponent     = preload("res://modules/matter/components/MatterComponent.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE & UTILITY AI GRAZING TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	await _test_creature_lifecycle_and_graze()

	print("\n>>> ALL CREATURE & GRAZING TESTS PASSED! <<<\n")
	World.paused = false
	get_tree().quit(0)

func _test_creature_lifecycle_and_graze() -> void:
	var reg = World.get_registry()
	assert(reg != null, "World registry must be initialized")

	# Run a tick to ensure signals and terrain caches are initialized
	World._run_tick()

	# -----------------------------------------------------------------------
	# 1. Locate an eligible grass patch on the map
	# -----------------------------------------------------------------------
	var veg_store: Dictionary  = reg.get_store(&"VegetationComponent")
	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	assert(not veg_store.is_empty(), "World should contain vegetation")

	var target_grass_pos := Vector2i(-1, -1)
	var target_tile_eid: int = -1

	for eid: int in veg_store:
		var veg: _VegetationComponent = veg_store[eid]
		var tile = tile_store.get(eid, null)
		if tile != null and veg.growth_stage >= 2 and tile.position.y >= 70 and tile.position.y <= 95:
			var p: Vector2i = tile.position
			if World.signals.has_affordance(p, _TileAffordance.WALKABLE) and not World.signals.has_affordance(p, _TileAffordance.HAZARD_LETHAL):
				if World.signals.get_signal(_SignalTypes.HAZARD, p) < 0.05:
					target_grass_pos = p
					target_tile_eid = eid
					break

	assert(target_grass_pos != Vector2i(-1, -1), "Must find a walkable established grass tile in temperate zone")
	print("[Test] Target grass tile found at %s (eid=%d)" % [target_grass_pos, target_tile_eid])

	# Pick a walkable spawn position 2 to 5 tiles away that is not itself a grass patch
	var spawn_pos := Vector2i(-1, -1)
	for r in range(2, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) + absi(dy) != r:
					continue
				var candidate: Vector2i = target_grass_pos + Vector2i(dx, dy)
				if World.is_valid_position(candidate) and World.signals.has_affordance(candidate, _TileAffordance.WALKABLE):
					if not World.signals.has_affordance(candidate, _TileAffordance.HAZARD_LETHAL):
						if not World.signals.has_affordance(candidate, _TileAffordance.GRAZEABLE):
							spawn_pos = candidate
							break
			if spawn_pos != Vector2i(-1, -1):
				break
		if spawn_pos != Vector2i(-1, -1):
			break

	# Fallback: create clear ground 2 steps away
	if spawn_pos == Vector2i(-1, -1):
		spawn_pos = target_grass_pos + Vector2i(2, 0)
		var clear_eid: int = World.get_entity_at(spawn_pos)
		if clear_eid != -1 and reg.has(clear_eid, &"VegetationComponent"):
			reg.remove(clear_eid, &"VegetationComponent")

	assert(spawn_pos != Vector2i(-1, -1), "Must find a valid spawn position near grass")
	print("[Test] Spawning creature at %s (distance %.1f from grass at %s)" % [spawn_pos, float(spawn_pos.distance_to(target_grass_pos)), target_grass_pos])

	# -----------------------------------------------------------------------
	# 2. Spawn Grazer Creature
	# -----------------------------------------------------------------------
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "Bramble")
	assert(creature_eid >= 0, "Creature creation should succeed")

	var creature: _CreatureComponent   = reg.get_component(creature_eid, &"CreatureComponent")
	var pos_comp: _PositionComponent   = reg.get_component(creature_eid, &"PositionComponent")
	var body: _BodyComponent           = reg.get_component(creature_eid, &"BodyComponent")
	var mind: _MindComponent           = reg.get_component(creature_eid, &"MindComponent")
	var mem: _MemoryComponent          = reg.get_component(creature_eid, &"MemoryComponent")
	var plan: _ActionPlanComponent     = reg.get_component(creature_eid, &"ActionPlanComponent")
	var render_comp                    = reg.get_component(creature_eid, &"RenderComponent")

	assert(creature != null, "CreatureComponent must exist")
	assert(pos_comp != null, "PositionComponent must exist")
	assert(body != null, "BodyComponent must exist")
	assert(mind != null, "MindComponent must exist")
	assert(mem != null, "MemoryComponent must exist")
	assert(plan != null, "ActionPlanComponent must exist")
	assert(render_comp != null, "RenderComponent must exist")

	print("[Test] Creature instantiated: id=%d, name='%s', glyph='%s'" % [creature_eid, creature.creature_name, render_comp.glyph])

	# -----------------------------------------------------------------------
	# 3. Verify Anatomy: Limbs, Organs, and Blood made of Item & Matter
	# -----------------------------------------------------------------------
	print("[Test] Verifying physical body anatomy...")
	assert(body.limbs.size() == 6, "Grazer should have 6 limbs (head, torso, 4 legs)")
	assert(body.organs.size() == 4, "Grazer should have 4 organs (heart, lungs, stomach, brain)")
	assert(body.blood_volume > 2.0, "Blood volume should be initialized (>2.0L)")

	# Check limb item & matter integration
	var left_foreleg_eid: int = body.limbs["left_foreleg"]
	var limb_item: _ItemComponent = reg.get_component(left_foreleg_eid, &"ItemComponent")
	var limb_matter: _MatterComponent = reg.get_component(left_foreleg_eid, &"MatterComponent")
	assert(limb_item != null, "Limb must be an ItemComponent entity")
	assert(limb_matter != null, "Limb must have a MatterComponent")
	assert(limb_item.parts.has("flesh"), "Limb should have flesh part")
	assert(limb_item.parts.has("bone"), "Limb should have bone part")
	assert(limb_item.container_id == creature_eid, "Limb container_id must point to creature")

	# Check organ item & matter integration
	var heart_eid: int = body.organs["heart"]
	var heart_item: _ItemComponent = reg.get_component(heart_eid, &"ItemComponent")
	var heart_matter: _MatterComponent = reg.get_component(heart_eid, &"MatterComponent")
	assert(heart_item != null, "Organ must be an ItemComponent entity")
	assert(heart_matter != null, "Organ must have a MatterComponent")
	assert(heart_item.container_id == creature_eid, "Organ container_id must point to creature")

	var total_mass: float = body.get_total_mass(reg)
	print("[Test] Total creature anatomical mass: %.2f kg (blood: %.2f L)" % [total_mass, body.blood_volume])
	assert(total_mass > 10.0, "Total mass should be consistent with anatomy (>10kg)")
	assert(body.get_mobility(reg) == 1.0, "Pristine limbs should provide 1.0 mobility")
	assert(body.are_vitals_functional(reg), "All vitals should be functional")
	print("  -> PASSED: Physical anatomy (limbs, organs, blood) fully verified.")

	# -----------------------------------------------------------------------
	# 4. Set Hunger and Verify Utility AI Action Selection
	# -----------------------------------------------------------------------
	print("[Test] Setting creature hunger = 0.85 (starving)...")
	mind.hunger = 0.85
	creature.stomach_fill = 0.0
	var initial_hunger: float = mind.hunger

	# Run a tick to trigger AI perception & planning
	World._run_tick()

	print("[Test] Evaluated Action Utilities: %s" % [mind.action_utilities])
	print("[Test] Selected Goal: %d (EAT=%d)" % [mind.current_action, _MindEmbeddings.Action.EAT])
	assert(mind.current_action == _MindEmbeddings.Action.EAT, "Utility AI must select EAT when hungry near grass")

	# -----------------------------------------------------------------------
	# 5. Simulate Locomotion towards Grass & Grazing
	# -----------------------------------------------------------------------
	var reached_and_grazed: bool = (mind.hunger <= initial_hunger - 0.25)
	if not reached_and_grazed:
		print("[Test] Simulating movement & grazing over up to 30 ticks...")
		for tick_idx in range(30):
			World._run_tick()
			await get_tree().process_frame

			# Check if grazing occurred
			if mind.hunger <= initial_hunger - 0.25:
				reached_and_grazed = true
				print("[Test] Grazing successfully occurred at tick %d! Hunger: %.2f" % [
					tick_idx + 1, mind.hunger
				])
				break
	else:
		print("[Test] Grazing successfully occurred on initial approach! Hunger: %.2f" % mind.hunger)

	assert(reached_and_grazed, "Creature must navigate to grass and graze successfully")
	assert(mind.hunger < initial_hunger, "Creature hunger must decrease after grazing")
	assert(creature.stomach_fill > 0.0, "Stomach fill must increase after grazing")
	print("  -> PASSED: Creature autonomously navigated and grazed living plant.")

	# -----------------------------------------------------------------------
	# 6. Test Grazing Consumes Grass Items Directly from Tile Inventory
	# -----------------------------------------------------------------------
	print("[Test] Testing direct consumption of grass item from tile inventory...")
	var cur_tile_eid: int = World.get_entity_at(pos_comp.position)
	var grass_item_eid: int = _ItemFactory.create(World, _ItemTypes.Type.GRASS, 20) # ORGANIC
	var inv: _InventoryComponent = reg.get_component(cur_tile_eid, &"InventoryComponent")
	if inv == null:
		inv = _InventoryComponent.new()
		inv.container_id = cur_tile_eid
		World.add_component(cur_tile_eid, inv)
	inv.items.append(grass_item_eid)
	World.signals.register_active_inventory(cur_tile_eid)

	var inv_grass_before: int = inv.get_total_quantity_of_type(reg, _ItemTypes.Type.GRASS)
	assert(inv_grass_before >= 1, "Tile inventory must contain grass item")

	# Spike hunger again
	mind.hunger = 0.80
	var pre_eat_hunger: float = mind.hunger

	World._run_tick()

	var inv_grass_after: int = inv.get_total_quantity_of_type(reg, _ItemTypes.Type.GRASS)
	print("[Test] Tile inventory grass items before: %d, after: %d, hunger before: %.2f, after: %.2f" % [
		inv_grass_before, inv_grass_after, pre_eat_hunger, mind.hunger
	])
	assert(inv_grass_after == inv_grass_before - 1, "Grazing must consume grass item from tile inventory")
	assert(mind.hunger < pre_eat_hunger, "Hunger must decrease after eating inventory grass item")
	print("  -> PASSED: Creature successfully consumed grass item from tile inventory.")

	# -----------------------------------------------------------------------
	# 7. Verify Memory Records
	# -----------------------------------------------------------------------
	print("[Test] Checking memory logs...")
	var has_grazed_memory: bool = false
	var has_stepped_memory: bool = false

	for mem_entry in mem.short_term_events:
		if mem_entry.get("event") == &"grazed":
			has_grazed_memory = true
		if mem_entry.get("event") == &"stepped":
			has_stepped_memory = true

	assert(has_stepped_memory, "Memory must record stepping movement events")
	assert(has_grazed_memory, "Memory must record grazing event")
	var has_pasture_landmark: bool = false
	for p in mem.long_term_landmarks:
		if mem.long_term_landmarks[p].get("type") == &"pasture":
			has_pasture_landmark = true
			break
	assert(has_pasture_landmark, "Long-term memory must record pasture landmark")
	print("  -> PASSED: Working short-term and long-term memories successfully recorded.")

	# -----------------------------------------------------------------------
	# 7. Write Log Artifact
	# -----------------------------------------------------------------------
	var log_file = FileAccess.open("res://logs/test_creature_graze.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("PASSED: Creature Body & Mind Utility AI successfully spawned, navigated, and grazed.\n" +
			"Limbs: %d, Organs: %d, Blood: %.2f L, Initial hunger: %.2f, Final hunger: %.2f\n" % [
				body.limbs.size(), body.organs.size(), body.blood_volume, initial_hunger, mind.hunger
			] +
			"Tile Inventory Grass: %d -> %d (consumed loose grass item directly from inventory).\n" % [
				inv_grass_before, inv_grass_after
			])
		log_file.close()

## TestCreatureRestCover.gd
## Integration test verifying Creature Rest behavior:
## 1. Prioritizes searching for tiles with affordance of COVER when fatigued.
## 2. Navigates to the cover tile and rests there, recovering fatigue and feeling secure.
## 3. Falls back to resting wherever it is if no COVER affordance is found.
## 4. Stays in place if already standing on a tile with COVER.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _VegetationTypes     = preload("res://modules/vegetation/data/VegetationTypes.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE REST & COVER AFFORDANCE TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	_test_rest_with_nearby_cover()
	_test_rest_fallback_without_cover()
	_test_rest_already_in_cover()

	print("\n>>> ALL CREATURE REST & COVER TESTS PASSED! <<<\n")
	var log_file = FileAccess.open("res://logs/test_creature_rest_cover.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("PASSED: Creature Rest prioritizes COVER affordance and falls back to resting wherever.\n")
		log_file.close()

	World.paused = false
	get_tree().quit(0)

## Test 1: Creature searches for and navigates to nearby tile with COVER
func _test_rest_with_nearby_cover() -> void:
	print("[Test 1] Testing Creature searches for tile with priority affordance of COVER...")
	var reg = World.get_registry()

	# Find or prepare a walkable tile with COVER (e.g. shrub or tree)
	var spawn_pos := Vector2i(20, 20)
	var cover_pos := Vector2i(23, 20) # 3 tiles east

	# Ensure spawn_pos is walkable and clear of cover
	var spawn_eid: int = World.get_entity_at(spawn_pos)
	if spawn_eid != -1 and reg.has(spawn_eid, &"VegetationComponent"):
		reg.remove(spawn_eid, &"VegetationComponent")

	# Ensure cover_pos has vegetation that grants COVER (e.g. SHRUB or PINE_TREE)
	var cover_eid: int = World.get_entity_at(cover_pos)
	if cover_eid == -1:
		cover_eid = World.create_entity()

	var veg: _VegetationComponent = reg.get_component(cover_eid, &"VegetationComponent")
	if veg == null:
		veg = _VegetationComponent.new()
		veg.veg_type = _VegetationTypes.Type.SHRUB
		veg.growth_stage = 2
		World.add_component(cover_eid, veg)
	else:
		veg.veg_type = _VegetationTypes.Type.SHRUB
		veg.growth_stage = 2

	# Re-sync signals & affordances
	World.signals._build_veg_cache(reg)
	World.signals.tick(1)

	assert(World.signals.has_affordance(cover_pos, _TileAffordance.COVER), "Target tile must have COVER affordance")
	assert(not World.signals.has_affordance(spawn_pos, _TileAffordance.COVER), "Spawn tile must not have COVER affordance")

	# Spawn creature at spawn_pos
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "TiredGrazer")
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")
	var plan: _ActionPlanComponent = reg.get_component(creature_eid, &"ActionPlanComponent")
	var pos_comp: _PositionComponent = reg.get_component(creature_eid, &"PositionComponent")

	# Set high fatigue, low hunger/thirst
	mind.fatigue = 0.90
	mind.hunger = 0.10
	mind.thirst = 0.10
	var initial_fatigue: float = mind.fatigue

	# Run single tick for AI perception & planning
	World._run_tick()

	print("[Test 1] Evaluated Action: %d (REST=%d), Target: %s, Path size: %d" % [
		mind.current_action, _MindEmbeddings.Action.REST, plan.target_tile, plan.path_queue.size()
	])

	assert(mind.current_action == _MindEmbeddings.Action.REST, "Creature with high fatigue must select REST action")
	assert(World.signals.has_affordance(plan.target_tile, _TileAffordance.COVER), "Creature must target a tile with COVER affordance (got %s)" % plan.target_tile)
	assert(not plan.path_queue.is_empty(), "Creature must have a path planned towards the COVER tile")

	var target_cover_pos: Vector2i = plan.target_tile

	# Step creature along path until it reaches target_cover_pos
	var reached_cover: bool = false
	for tick_idx in range(15):
		World._run_tick()
		if pos_comp.position == target_cover_pos:
			reached_cover = true
			print("[Test 1] Reached COVER tile at tick %d! Position: %s, Fatigue: %.2f" % [
				tick_idx + 1, pos_comp.position, mind.fatigue
			])
			break

	assert(reached_cover, "Creature must reach the COVER tile")
	assert(World.signals.has_affordance(pos_comp.position, _TileAffordance.COVER), "Creature position must have COVER affordance")

	# Rest an additional tick in cover to verify fatigue recovery
	var pre_rest_fatigue: float = mind.fatigue
	World._run_tick()
	assert(mind.fatigue < pre_rest_fatigue, "Fatigue must decrease while resting under cover")
	print("  -> PASSED: Creature successfully prioritized COVER affordance tile, pathed there, and rested.")

## Test 2: When no COVER tile is found anywhere nearby, falls back to rest wherever it is
func _test_rest_fallback_without_cover() -> void:
	print("[Test 2] Testing Fallback to rest wherever when no COVER affordance is found...")
	var reg = World.get_registry()

	var fallback_pos := Vector2i(45, 45)

	# Ensure 33x33 area around fallback_pos has NO cover affordance
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			var p := fallback_pos + Vector2i(dx, dy)
			var peid: int = World.get_entity_at(p)
			if peid != -1 and reg.has(peid, &"VegetationComponent"):
				reg.remove(peid, &"VegetationComponent")

	World.signals._build_veg_cache(reg)
	World.signals.tick(1)
	assert(not World.signals.has_affordance(fallback_pos, _TileAffordance.COVER), "Fallback pos must not have COVER")

	# Spawn creature
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, fallback_pos, "IsolatedTiredGrazer")
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")
	var plan: _ActionPlanComponent = reg.get_component(creature_eid, &"ActionPlanComponent")
	var pos_comp: _PositionComponent = reg.get_component(creature_eid, &"PositionComponent")

	mind.fatigue = 0.90
	mind.hunger = 0.10
	mind.thirst = 0.10
	var initial_fatigue: float = mind.fatigue

	World._run_tick()

	print("[Test 2] Fallback - Action: %d (REST=%d), Target: %s, Path size: %d" % [
		mind.current_action, _MindEmbeddings.Action.REST, plan.target_tile, plan.path_queue.size()
	])

	assert(mind.current_action == _MindEmbeddings.Action.REST, "Action must still be REST")
	assert(plan.target_tile == fallback_pos or plan.target_tile == Vector2i(-1, -1), "Target tile must reflect in-place rest")
	assert(plan.path_queue.is_empty(), "Path queue must be empty for in-place fallback rest")
	assert(pos_comp.position == fallback_pos, "Creature must remain in-place")

	# Verify in-place fatigue recovery occurs
	World._run_tick()
	assert(mind.fatigue < initial_fatigue, "Fatigue must decrease during in-place fallback resting")
	print("  -> PASSED: Creature successfully fell back to resting in-place wherever it was.")

## Test 3: If creature is already standing in COVER, stays and rests immediately
func _test_rest_already_in_cover() -> void:
	print("[Test 3] Testing Creature already standing in COVER rests immediately in-place...")
	var reg = World.get_registry()

	var cover_pos := Vector2i(60, 60)
	var cover_eid: int = World.get_entity_at(cover_pos)
	if cover_eid == -1:
		cover_eid = World.create_entity()

	var veg = _VegetationComponent.new()
	veg.veg_type = _VegetationTypes.Type.PINE_TREE
	veg.growth_stage = 3
	World.add_component(cover_eid, veg)

	World.signals._build_veg_cache(reg)
	World.signals.tick(1)
	assert(World.signals.has_affordance(cover_pos, _TileAffordance.COVER), "Tile must have COVER affordance")

	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, cover_pos, "ShelteredGrazer")
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")
	var plan: _ActionPlanComponent = reg.get_component(creature_eid, &"ActionPlanComponent")
	var pos_comp: _PositionComponent = reg.get_component(creature_eid, &"PositionComponent")

	mind.fatigue = 0.90
	mind.hunger = 0.10
	mind.thirst = 0.10

	World._run_tick()

	assert(mind.current_action == _MindEmbeddings.Action.REST, "Must select REST action")
	assert(plan.target_tile == cover_pos or plan.target_tile == Vector2i(-1, -1), "Target must be current position or in-place rest")
	assert(plan.path_queue.is_empty(), "Must not path anywhere since it is already in COVER")
	assert(pos_comp.position == cover_pos, "Must stay in place under cover")
	print("  -> PASSED: Creature already standing in COVER immediately rests in-place.")

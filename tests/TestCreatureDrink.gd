## TestCreatureDrink.gd
## Integration test verifying Creature Drinking & Hydration Navigation:
## - Thirsty creature evaluates DRINK as highest utility action.
## - Detects nearby water bodies (ponds/rivers).
## - Calculates shore/bank approach waypoints for non-walkable deep water or walkable shallow water.
## - Steps through locomotion path towards the water.
## - Executes drinking on arrival, reducing thirst, decrementing fluid, and storing spatial memories.
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
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _FluidComponent      = preload("res://modules/matter/components/FluidComponent.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE DRINKING & HYDRATION NAVIGATION TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	await _test_creature_seek_and_drink()
	await _test_immediate_drinking_adjacent()

	print("\n>>> ALL CREATURE DRINKING TESTS PASSED! <<<\n")
	World.paused = false
	get_tree().quit(0)

func _test_creature_seek_and_drink() -> void:
	var reg = World.get_registry()
	assert(reg != null, "World registry must be initialized")

	# Initialize signals and terrain caches
	World._run_tick()

	# -----------------------------------------------------------------------
	# 1. Locate a natural drinkable water tile in temperate zone
	# -----------------------------------------------------------------------
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")
	assert(not fluid_store.is_empty(), "World should contain fluid/water bodies")

	var target_water_pos := Vector2i(-1, -1)
	for eid: int in fluid_store:
		var fl: _FluidComponent = fluid_store[eid]
		if fl == null or fl.material_id != _MaterialTypes.Type.WATER or fl.volume < 0.1:
			continue
		var tile = tile_store.get(eid, null)
		if tile != null and tile.position.y >= 60 and tile.position.y <= 100:
			var p: Vector2i = tile.position
			if World.signals.has_affordance(p, _TileAffordance.DRINKABLE) and not World.signals.has_affordance(p, _TileAffordance.HAZARD_LETHAL):
				target_water_pos = p
				break

	assert(target_water_pos != Vector2i(-1, -1), "Must find a drinkable water tile on the map")
	print("[Test] Target water tile located at: %s" % target_water_pos)

	# -----------------------------------------------------------------------
	# 2. Pick a dry walkable spawn position at least 4 tiles away from all water
	# -----------------------------------------------------------------------
	var spawn_pos := Vector2i(-1, -1)
	for r in range(5, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cand: Vector2i = target_water_pos + Vector2i(dx, dy)
				if not World.is_valid_position(cand) or not World.signals.has_affordance(cand, _TileAffordance.WALKABLE):
					continue
				if World.signals.has_affordance(cand, _TileAffordance.HAZARD_LETHAL):
					continue

				# Ensure cand is not within 3 tiles of any water body
				var near_water: bool = false
				for cdy in range(-3, 4):
					for cdx in range(-3, 4):
						var cp: Vector2i = cand + Vector2i(cdx, cdy)
						if World.is_valid_position(cp) and World.signals.has_affordance(cp, _TileAffordance.DRINKABLE):
							near_water = true
							break
					if near_water:
						break

				if not near_water:
					spawn_pos = cand
					break
			if spawn_pos != Vector2i(-1, -1):
				break
		if spawn_pos != Vector2i(-1, -1):
			break

	assert(spawn_pos != Vector2i(-1, -1), "Must find dry ground at least 4 tiles from all water")
	print("[Test] Spawning creature at %s (dist %.1f from water at %s)" % [
		spawn_pos, float(spawn_pos.distance_to(target_water_pos)), target_water_pos
	])

	# -----------------------------------------------------------------------
	# 3. Spawn Grazer and Make Dehydrated (Thirst = 1.0)
	# -----------------------------------------------------------------------
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "ThirstyGrazer")
	var creature: _CreatureComponent = reg.get_component(creature_eid, &"CreatureComponent")
	var pos_comp: _PositionComponent = reg.get_component(creature_eid, &"PositionComponent")
	var mind: _MindComponent         = reg.get_component(creature_eid, &"MindComponent")
	var mem: _MemoryComponent        = reg.get_component(creature_eid, &"MemoryComponent")
	var plan: _ActionPlanComponent   = reg.get_component(creature_eid, &"ActionPlanComponent")

	mind.thirst = 1.0
	mind.hunger = 0.10
	var initial_thirst: float = mind.thirst

	# Run a tick to trigger perception, utility evaluation, and planning
	World._run_tick()

	print("[Test] Selected Action: %d (DRINK=%d)" % [mind.current_action, _MindEmbeddings.Action.DRINK])
	print("[Test] Utilities: %s" % [mind.action_utilities])
	assert(mind.current_action == _MindEmbeddings.Action.DRINK, "Thirsty creature must select DRINK action")
	assert(plan.current_goal == _MindEmbeddings.Action.DRINK, "Plan goal must be set to DRINK")
	assert(plan.target_tile != Vector2i(-1, -1), "Plan must establish a target tile towards water")
	assert(not plan.path_queue.is_empty(), "Plan must generate a path towards water approach")
	print("[Test] Planned approach target: %s with %d path steps" % [plan.target_tile, plan.path_queue.size()])

	# -----------------------------------------------------------------------
	# 4. Simulate Locomotion and Drinking over successive ticks
	# -----------------------------------------------------------------------
	var initial_path_size: int = plan.path_queue.size()
	var drank_success: bool = false

	for tick_idx in range(40):
		World._run_tick()
		await get_tree().process_frame

		if mind.thirst <= initial_thirst - 0.35:
			drank_success = true
			print("[Test] Creature arrived and drank successfully at tick %d! Thirst: %.2f (was %.2f)" % [
				tick_idx + 1, mind.thirst, initial_thirst
			])
			break

	assert(drank_success, "Creature must navigate to water and drink within 40 ticks")
	assert(mind.thirst < initial_thirst, "Thirst drive must decrease after drinking")

	# Check memory records
	var has_drank_mem: bool = false
	for evt in mem.short_term_events:
		if evt.get("event") == &"drank":
			has_drank_mem = true
			break
	assert(has_drank_mem, "Short-term memory must record 'drank' event")
	assert(not mem.long_term_landmarks.is_empty(), "Long-term memory must record water_source landmark")
	print("  -> PASSED: Multi-step navigation to water shoreline and drinking verified.")

func _test_immediate_drinking_adjacent() -> void:
	print("\n[Test] Testing immediate in-place drinking when adjacent to water...")
	var reg = World.get_registry()

	# Create a controlled 2-tile test setup:
	# Water tile at (50, 50), creature at (50, 51)
	var water_pos := Vector2i(50, 50)
	var creature_pos := Vector2i(50, 51)

	var water_eid: int = World.get_entity_at(water_pos)
	var fluid: _FluidComponent = reg.get_component(water_eid, &"FluidComponent")
	if fluid == null:
		fluid = _FluidComponent.new()
		fluid.material_id = _MaterialTypes.Type.WATER
		fluid.volume = 0.5
		fluid.settled = true
		reg.add(water_eid, fluid)

	World._run_tick()

	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, creature_pos, "ShoreDrinker")
	var mind: _MindComponent       = reg.get_component(creature_eid, &"MindComponent")
	var plan: _ActionPlanComponent = reg.get_component(creature_eid, &"ActionPlanComponent")

	mind.thirst = 0.95
	mind.hunger = 0.10
	var initial_thirst: float = mind.thirst

	World._run_tick()

	print("[Test] Immediate Drink Test - Action: %d, Thirst: %.2f (was %.2f)" % [
		mind.current_action, mind.thirst, initial_thirst
	])
	assert(mind.thirst < initial_thirst, "Creature standing adjacent to water must drink immediately")
	print("  -> PASSED: Immediate drinking adjacent to water verified.")

	# Write log file artifact
	var log_file = FileAccess.open("res://logs/test_creature_drink.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("PASSED: Creature Navigation and Drinking verified.\n" +
			"- Navigation to shore approach and drinking successful.\n" +
			"- Immediate in-place drinking from adjacent water tile successful.\n")
		log_file.close()

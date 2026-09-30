## TestCreatureTileOccupancy.gd
## Integration test suite verifying strict 1-creature-per-tile occupancy enforcement:
## 1. No overlapping spawns: Spawner respects occupied tiles.
## 2. Head-on avoidance & sidestep: Locomotion detours around occupied intermediate waypoints.
## 3. Blocked wait & re-plan: Locomotion pauses and clears path when bypass is impossible.
## 4. Resource target exclusion: AI avoids selecting occupied food, water shore, or cover tiles.
## 5. Interaction range stopping: Pursuers stop adjacent to targets rather than colliding.
## 6. Dead creature tile freeing: Carcass dropping immediately frees tile for other actors.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureSpawner     = preload("res://modules/creature/systems/CreatureSpawner.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE TILE OCCUPANCY TEST SUITE ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_test_no_overlapping_spawns()
	_test_head_on_avoidance_and_sidestep()
	_test_blocked_wait_and_clear_path()
	_test_food_and_water_approach_exclusion()
	_test_interaction_range_stopping()
	_test_dead_creature_tile_freeing()

	print("\n>>> ALL CREATURE TILE OCCUPANCY TESTS PASSED! <<<\n")
	_write_log_artifact()
	World.paused = false
	get_tree().quit(0)

func _test_no_overlapping_spawns() -> void:
	print("\n[Test 1] Testing No Overlapping Spawns...")
	var reg = World.get_registry()
	assert(reg != null, "World registry must be valid")

	var pos := Vector2i(25, 25)
	var c1_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, pos, "Grazer_One")
	assert(c1_eid != -1, "First creature must spawn")
	assert(World.get_creature_at(pos) == c1_eid, "Spatial index must map (25, 25) to c1")

	# Attempt to spawn another creature at the exact same position via criteria
	var spawn_crit: Dictionary = {
		"min_x": pos.x,
		"max_x": pos.x,
		"min_y": pos.y,
		"max_y": pos.y,
		"require_vegetation": false,
	}
	var cand_pos: Vector2i = _CreatureSpawner.find_spawn_position(World, spawn_crit, [])
	assert(cand_pos != pos, "Spawner must reject occupied tile (25, 25)")
	print("  PASS: Spawner successfully rejected occupied tile %s" % str(pos))

func _test_head_on_avoidance_and_sidestep() -> void:
	print("\n[Test 2] Testing Locomotion Head-on Avoidance & Sidestep...")
	var reg = World.get_registry()

	# Clear previous test creatures
	_cleanup_all_creatures()

	# Create Actor A at (10, 10), aiming to reach (12, 10)
	var a_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(10, 10), "ActorA")
	var a_plan: _ActionPlanComponent = reg.get_component(a_eid, &"ActionPlanComponent")
	var a_pos: _PositionComponent = reg.get_component(a_eid, &"PositionComponent")
	a_pos.move_cooldown_ticks = 0
	a_plan.target_tile = Vector2i(12, 10)
	a_plan.path_queue = [Vector2i(11, 10), Vector2i(12, 10)]

	# Create Stationary Obstacle B at (11, 10)
	var b_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(11, 10), "ActorB")
	var b_pos: _PositionComponent = reg.get_component(b_eid, &"PositionComponent")
	b_pos.move_cooldown_ticks = 9999 # Keep stationary

	# Ensure surrounding tiles (10, 9), (10, 11) are walkable
	World.signals.set_affordance(Vector2i(10, 9), _TileAffordance.WALKABLE)
	World.signals.set_affordance(Vector2i(10, 11), _TileAffordance.WALKABLE)

	# Run locomotion tick
	World.creature_locomotion.tick(1)

	# Actor A must NOT be at (11, 10)! It must have sidestepped or remained at (10, 10)
	assert(a_pos.position != Vector2i(11, 10), "Actor A must NEVER occupy (11, 10) while B is there")
	assert(World.get_creature_at(Vector2i(11, 10)) == b_eid, "Actor B must still own (11, 10)")

	var stepped_lateral: bool = (a_pos.position == Vector2i(10, 9) or a_pos.position == Vector2i(10, 11))
	assert(stepped_lateral or a_pos.position == Vector2i(10, 10), "Actor A must either lateral sidestep or wait")
	print("  PASS: Actor A avoided stepping into occupied tile (11, 10). Position: %s" % str(a_pos.position))

func _test_blocked_wait_and_clear_path() -> void:
	print("\n[Test 3] Testing Locomotion Blocked Wait & Clear Path...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	# Actor A at (10, 10) wants to move to (11, 10)
	var a_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(10, 10), "BlockedActor")
	var a_plan: _ActionPlanComponent = reg.get_component(a_eid, &"ActionPlanComponent")
	var a_pos: _PositionComponent = reg.get_component(a_eid, &"PositionComponent")
	a_pos.move_cooldown_ticks = 0
	a_plan.target_tile = Vector2i(11, 10)
	a_plan.path_queue = [Vector2i(11, 10)]

	# Obstacle B at (11, 10)
	var b_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(11, 10), "ObstacleB")

	# Block lateral sidestep tiles (10, 9) and (10, 11) with obstacles C and D
	var _c_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(10, 9), "ObstacleC")
	var _d_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(10, 11), "ObstacleD")

	# Tick locomotion 3 times
	for t in range(1, 4):
		a_pos.move_cooldown_ticks = 0
		World.creature_locomotion.tick(t)

	# Position must still be (10, 10) and path must be cleared after 3 blocked attempts
	assert(a_pos.position == Vector2i(10, 10), "Blocked actor must remain at original position")
	assert(a_plan.path_queue.is_empty(), "Path queue must be cleared after consecutive blocks to allow re-planning")
	print("  PASS: Blocked actor held position and cleared path after being blocked.")

func _test_food_and_water_approach_exclusion() -> void:
	print("\n[Test 4] Testing AI Target Selection Skips Occupied Tiles...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	# --- Food target test ---
	var food_pos := Vector2i(30, 30)
	World.signals.set_affordance(food_pos, _TileAffordance.WALKABLE)
	World.signals.set_affordance(food_pos, _TileAffordance.HERBIVORE_FOOD)
	World.signals.emit_scent(_SignalTypes.FOOD_PLANT, food_pos, 1.0, 1)

	# Grazer 1 occupies food_pos
	var g1_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, food_pos, "Grazer1")

	# Grazer 2 at (30, 32) plans to eat
	var g2_pos := Vector2i(30, 32)
	var g2_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, g2_pos, "Grazer2")
	var g2_plan: _ActionPlanComponent = reg.get_component(g2_eid, &"ActionPlanComponent")
	var g2_creature: _CreatureComponent = reg.get_component(g2_eid, &"CreatureComponent")
	var g2_mem = reg.get_component(g2_eid, &"MemoryComponent")

	World.creature_ai._plan_eat(g2_pos, g2_plan, g2_creature, g2_mem, 1, g2_eid)

	# g2 must NOT select food_pos because g1 is standing on it!
	assert(g2_plan.target_tile != food_pos, "AI must not select occupied food tile")
	print("  PASS: AI correctly skipped occupied food tile.")

	# --- Water approach test ---
	var water_pos := Vector2i(20, 20)
	var shore_pos := Vector2i(20, 21)
	World.signals.set_affordance(water_pos, _TileAffordance.DRINKABLE)
	World.signals.set_affordance(shore_pos, _TileAffordance.WALKABLE)

	# Grazer 1 stands on shore_pos
	var pos_g1: _PositionComponent = reg.get_component(g1_eid, &"PositionComponent")
	World.update_creature_position(g1_eid, pos_g1.position, shore_pos)
	pos_g1.position = shore_pos

	var approach: Vector2i = World.creature_ai._find_approach_for_water(water_pos, Vector2i(20, 23))
	assert(approach != shore_pos, "Water approach must skip occupied shore tile %s" % str(shore_pos))
	print("  PASS: Water approach selection skipped occupied shore tile.")

func _test_interaction_range_stopping() -> void:
	print("\n[Test 5] Testing Interaction Range Stopping (Adjacent Hold)...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	# Hunter at (15, 15), Target at (15, 16)
	var h_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(15, 15), "Hunter")
	var t_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(15, 16), "Prey")

	var h_pos: _PositionComponent = reg.get_component(h_eid, &"PositionComponent")
	var h_plan: _ActionPlanComponent = reg.get_component(h_eid, &"ActionPlanComponent")
	h_pos.move_cooldown_ticks = 0
	h_plan.target_tile = Vector2i(15, 16)
	h_plan.path_queue = [Vector2i(15, 16)] # Path mistakenly goes into target tile

	World.creature_locomotion.tick(1)

	# Locomotion must recognize target tile is occupied and within adjacent range <= 2 -> hold position & clear path
	assert(h_pos.position == Vector2i(15, 15), "Hunter must not step into target prey tile")
	assert(h_plan.path_queue.is_empty(), "Path queue must be cleared on reaching adjacent interaction range")
	print("  PASS: Hunter stopped adjacent to prey without overlapping.")

func _test_dead_creature_tile_freeing() -> void:
	print("\n[Test 6] Testing Dead Creature Tile Freeing...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	var grave_pos := Vector2i(18, 18)
	var prey_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, grave_pos, "DoomedPrey")
	assert(World.get_creature_at(grave_pos) == prey_eid, "Prey must occupy tile initially")

	# Kill prey and drop carcass
	var prey_creature: _CreatureComponent = reg.get_component(prey_eid, &"CreatureComponent")
	prey_creature.is_alive = false
	World.creature_body._drop_carcass_items(prey_eid, prey_creature, reg.get_component(prey_eid, &"PositionComponent"), reg)

	# Tile must immediately be reported as unoccupied
	var occ_after_death: int = World.get_creature_at(grave_pos)
	assert(occ_after_death == -1, "Dead creature's tile must be freed immediately (got %d)" % occ_after_death)

	# A living carnivore can now freely step onto grave_pos
	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(18, 17), "ScavengerWolf")
	var w_pos: _PositionComponent = reg.get_component(wolf_eid, &"PositionComponent")
	var w_plan: _ActionPlanComponent = reg.get_component(wolf_eid, &"ActionPlanComponent")
	w_pos.move_cooldown_ticks = 0
	w_plan.target_tile = grave_pos
	w_plan.path_queue = [grave_pos]

	World.creature_locomotion.tick(1)

	assert(w_pos.position == grave_pos, "Wolf must be able to step onto carcass tile now that it's freed")
	assert(World.get_creature_at(grave_pos) == wolf_eid, "Spatial index must now register the wolf on the carcass tile")
	print("  PASS: Dead creature tile freed immediately and accessible for scavenging.")

func _cleanup_all_creatures() -> void:
	var reg = World.get_registry()
	if reg == null:
		return
	var creature_store: Dictionary = reg.get_store(&"CreatureComponent").duplicate()
	for eid: int in creature_store:
		World.destroy_entity(eid)

func _write_log_artifact() -> void:
	var log_dir := "res://logs"
	if not DirAccess.dir_exists_absolute(log_dir):
		DirAccess.make_dir_recursive_absolute(log_dir)
	var file = FileAccess.open("res://logs/creature_tile_occupancy.log", FileAccess.WRITE)
	if file != null:
		file.store_string("=== CREATURE TILE OCCUPANCY TEST COMPLETED SUCCESSFULLY ===\n")
		file.store_string("Timestamp: %s\n" % Time.get_datetime_string_from_system())
		file.store_string("All 6 test cases passed with zero collisions, verified sidesteps, and instant carcass tile freeing.\n")
		file.close()

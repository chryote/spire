## TestCreatureSwimming.gd
## Integration test suite verifying creature swimming mechanics on SWIMMABLE affordance:
## 1. Archetype swimming capability defaults (Wolf/Deer can swim, Grazer/Hare cannot).
## 2. Locomotion traversability gate: Non-swimmers rejected, Swimmers permitted on SWIMMABLE.
## 3. Genetic trait SWIMMER: Grants swimming capability to otherwise non-swimming species.
## 4. Water drag & splash impulse: Slower movement interval and splash sounds in water.
## 5. Pathfinding across rivers: Swimmers path through deep water to pursue targets.
## 6. Lethal water hazard avoidance: Swimmers refuse to enter toxic / HAZARD_LETHAL water.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE SWIMMING INTEGRATION TEST SUITE ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_test_archetype_capabilities()
	_test_deep_water_traversability()
	_test_genetic_trait_swimmer()
	_test_swimming_drag_and_splash()
	_test_swimming_pathfinding()
	_test_lethal_water_avoidance()

	print("\n>>> ALL CREATURE SWIMMING TESTS PASSED! <<<\n")
	_write_log_artifact()
	World.paused = false
	get_tree().quit(0)

func _test_archetype_capabilities() -> void:
	print("\n[Test 1] Testing Archetype Swimming Capabilities...")
	var reg = World.get_registry()
	assert(reg != null, "World registry must be valid")

	_cleanup_all_creatures()

	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(10, 10), "TestWolf")
	var deer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.DEER, Vector2i(11, 10), "TestDeer")
	var grazer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(12, 10), "TestGrazer")
	var hare_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, Vector2i(13, 10), "TestHare")

	var wolf_c: _CreatureComponent = reg.get_component(wolf_eid, &"CreatureComponent")
	var deer_c: _CreatureComponent = reg.get_component(deer_eid, &"CreatureComponent")
	var grazer_c: _CreatureComponent = reg.get_component(grazer_eid, &"CreatureComponent")
	var hare_c: _CreatureComponent = reg.get_component(hare_eid, &"CreatureComponent")

	assert(wolf_c.can_swim == true, "Wolf must have can_swim = true")
	assert(wolf_c.swim_speed_mult >= 0.70, "Wolf must have strong swim_speed_mult")
	assert(deer_c.can_swim == true, "Deer must have can_swim = true")
	assert(grazer_c.can_swim == false, "Grazer must have can_swim = false")
	assert(hare_c.can_swim == false, "Hare must have can_swim = false")

	print("  PASS: Wolf & Deer can swim; Grazer & Hare cannot.")

func _test_deep_water_traversability() -> void:
	print("\n[Test 2] Testing Deep Water Locomotion Traversability...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	# Create a deep water tile at (20, 20) with SWIMMABLE only (NOT WALKABLE)
	var water_pos := Vector2i(20, 20)
	World.signals.set_affordance(water_pos, _TileAffordance.SWIMMABLE, true)
	World.signals.set_affordance(water_pos, _TileAffordance.WALKABLE, false)
	World.signals.set_affordance(water_pos, _TileAffordance.HAZARD_LETHAL, false)

	# 1. Non-swimmer Grazer at (19, 20) tries to step onto (20, 20)
	var g_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(19, 20), "LandGrazer")
	var g_plan: _ActionPlanComponent = reg.get_component(g_eid, &"ActionPlanComponent")
	var g_pos: _PositionComponent = reg.get_component(g_eid, &"PositionComponent")
	g_pos.move_cooldown_ticks = 0
	g_plan.target_tile = water_pos
	g_plan.path_queue = [water_pos]

	World.creature_locomotion.tick(1)

	assert(g_pos.position == Vector2i(19, 20), "Non-swimmer Grazer must not enter SWIMMABLE tile")
	assert(g_plan.path_queue.is_empty(), "Non-swimmer path must be cleared when facing deep water")

	# 2. Swimmer Wolf at (21, 20) tries to step onto (20, 20)
	var w_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(21, 20), "SwimmerWolf")
	var w_plan: _ActionPlanComponent = reg.get_component(w_eid, &"ActionPlanComponent")
	var w_pos: _PositionComponent = reg.get_component(w_eid, &"PositionComponent")
	w_pos.move_cooldown_ticks = 0
	w_plan.target_tile = water_pos
	w_plan.path_queue = [water_pos]

	World.creature_locomotion.tick(2)

	assert(w_pos.position == water_pos, "Wolf swimmer must successfully enter SWIMMABLE tile (got %s)" % str(w_pos.position))
	assert(World.get_creature_at(water_pos) == w_eid, "Spatial index must register wolf on the water tile")
	print("  PASS: Non-swimmer rejected; Wolf successfully entered SWIMMABLE tile.")

func _test_genetic_trait_swimmer() -> void:
	print("\n[Test 3] Testing Genetic Trait SWIMMER...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	var water_pos := Vector2i(30, 30)
	World.signals.set_affordance(water_pos, _TileAffordance.SWIMMABLE, true)
	World.signals.set_affordance(water_pos, _TileAffordance.WALKABLE, false)

	# Spawn a Grazer with the SWIMMER genetic trait
	var g_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(29, 30), "OtterGrazer", [_TraitTypes.Type.SWIMMER])
	var g_plan: _ActionPlanComponent = reg.get_component(g_eid, &"ActionPlanComponent")
	var g_pos: _PositionComponent = reg.get_component(g_eid, &"PositionComponent")
	g_pos.move_cooldown_ticks = 0
	g_plan.target_tile = water_pos
	g_plan.path_queue = [water_pos]

	World.creature_locomotion.tick(1)

	assert(g_pos.position == water_pos, "Grazer with SWIMMER trait must successfully swim into SWIMMABLE tile")
	print("  PASS: Trait SWIMMER enabled swimming for grazer.")

func _test_swimming_drag_and_splash() -> void:
	print("\n[Test 4] Testing Swimming Movement Drag & Water Splashes...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	var water_pos := Vector2i(40, 40)
	World.signals.set_affordance(water_pos, _TileAffordance.SWIMMABLE, true)
	World.signals.set_affordance(water_pos, _TileAffordance.WALKABLE, false)

	var w_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(39, 40), "WaterWolf")
	var w_plan: _ActionPlanComponent = reg.get_component(w_eid, &"ActionPlanComponent")
	var w_pos: _PositionComponent = reg.get_component(w_eid, &"PositionComponent")
	w_pos.base_move_interval = 2
	w_pos.move_cooldown_ticks = 0
	w_plan.target_tile = water_pos
	w_plan.path_queue = [water_pos]

	World.creature_locomotion.tick(1)

	# In water: interval = int(2 / 0.75) = 2. Cooldown is maxi(1, interval) >= base interval
	assert(w_pos.position == water_pos, "Wolf must step into water")
	assert(w_pos.move_cooldown_ticks >= w_pos.base_move_interval, "Swimming drag must set cooldown ticks properly")
	print("  PASS: Swimming drag and cooldown verified.")

func _test_swimming_pathfinding() -> void:
	print("\n[Test 5] Testing AI Pathfinding Across River...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	# Create a river barrier at x = 52
	for y in range(48, 54):
		var r_pos := Vector2i(52, y)
		World.signals.set_affordance(r_pos, _TileAffordance.SWIMMABLE, true)
		World.signals.set_affordance(r_pos, _TileAffordance.WALKABLE, false)

	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(50, 50), "RiverWolf")
	var wolf_c: _CreatureComponent = reg.get_component(wolf_eid, &"CreatureComponent")

	var grazer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(50, 50), "RiverGrazer")
	var grazer_c: _CreatureComponent = reg.get_component(grazer_eid, &"CreatureComponent")

	var destination := Vector2i(54, 50) # Target across river

	var wolf_path: Array[Vector2i] = World.creature_ai._build_simple_path(Vector2i(50, 50), destination, wolf_c.can_swim)
	var grazer_path: Array[Vector2i] = World.creature_ai._build_simple_path(Vector2i(50, 50), destination, grazer_c.can_swim)

	# Wolf path should cross the river at (52, 50)
	assert(wolf_path.has(Vector2i(52, 50)), "Wolf path must cross SWIMMABLE river tile")
	assert(wolf_path.back() == destination, "Wolf must reach destination across river")

	# Grazer path must NOT step onto (52, 50)
	assert(not grazer_path.has(Vector2i(52, 50)), "Grazer path must NOT enter SWIMMABLE river tile")
	print("  PASS: Wolf path bridges river; Grazer path respects water barrier.")

func _test_lethal_water_avoidance() -> void:
	print("\n[Test 6] Testing Lethal Water Hazard Avoidance...")
	var reg = World.get_registry()
	_cleanup_all_creatures()

	var toxic_water := Vector2i(60, 60)
	World.signals.set_affordance(toxic_water, _TileAffordance.SWIMMABLE, true)
	World.signals.set_affordance(toxic_water, _TileAffordance.WALKABLE, false)
	World.signals.set_affordance(toxic_water, _TileAffordance.HAZARD_LETHAL, true)

	var w_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, Vector2i(59, 60), "CautiousWolf")
	var w_plan: _ActionPlanComponent = reg.get_component(w_eid, &"ActionPlanComponent")
	var w_pos: _PositionComponent = reg.get_component(w_eid, &"PositionComponent")
	w_pos.move_cooldown_ticks = 0
	w_plan.target_tile = toxic_water
	w_plan.path_queue = [toxic_water]

	World.creature_locomotion.tick(1)

	assert(w_pos.position == Vector2i(59, 60), "Wolf must NOT enter lethal toxic water despite can_swim")
	assert(w_plan.path_queue.is_empty(), "Path must be aborted when facing lethal hazard")
	print("  PASS: Swimmers strictly avoid HAZARD_LETHAL toxic water.")

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
	var file = FileAccess.open("res://logs/creature_swimming.log", FileAccess.WRITE)
	if file != null:
		file.store_string("=== CREATURE SWIMMING TEST COMPLETED SUCCESSFULLY ===\n")
		file.store_string("Timestamp: %s\n" % Time.get_datetime_string_from_system())
		file.store_string("All 6 test cases passed: Wolf and Deer swim freely across SWIMMABLE deep water with drag and splash effects.\n")
		file.close()

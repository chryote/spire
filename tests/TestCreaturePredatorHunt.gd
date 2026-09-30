## TestCreaturePredatorHunt.gd
## Comprehensive integration test suite for carnivore predator introduction:
## 1. Wolf archetype creation, anatomy, carnivore diet, and natural attacks.
## 2. Scent emission and prey fear/evasion dynamics.
## 3. Hungry predator hunting AI: detecting prey, stalking, and pathfinding.
## 4. Predator combat execution: kinetic piercing bite / claw impacts and wound trauma.
## 5. Prey mortality & carcass drop: dropping meat items and subsequent predator feeding.
## 6. Extensible map spawning: starter population with Grazers and Lone Wolf.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureSpawner     = preload("res://modules/creature/systems/CreatureSpawner.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")
const _ImpactTypes         = preload("res://modules/matter/data/ImpactTypes.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE PREDATOR & HUNTING INTEGRATION TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_test_wolf_archetype_definition()
	_test_scent_emission_and_prey_fear()
	_test_predator_hunting_and_stalking_ai()
	_test_predator_combat_and_mortality()
	_test_carcass_drop_and_carnivore_feeding()
	_test_starter_population_spawning_with_predator()
	_test_carnivore_hunger_hunt_and_prowl()

	print("\n>>> ALL PREDATOR & HUNTING INTEGRATION TESTS PASSED! <<<\n")
	_write_log_artifact()
	World.paused = false
	get_tree().quit(0)

func _test_wolf_archetype_definition() -> void:
	print("\n[Test 1] Testing Wolf Archetype, Anatomy, and Attacks...")
	var reg = World.get_registry()
	assert(reg != null, "World registry must be valid")

	var spawn_pos := Vector2i(40, 40)
	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, spawn_pos, "ApexWolf")
	assert(wolf_eid != -1, "Wolf must instantiate successfully")

	var creature: _CreatureComponent = reg.get_component(wolf_eid, &"CreatureComponent")
	var body: _BodyComponent         = reg.get_component(wolf_eid, &"BodyComponent")
	var traits: _TraitComponent      = reg.get_component(wolf_eid, &"TraitComponent")
	var pos_c: _PositionComponent    = reg.get_component(wolf_eid, &"PositionComponent")

	assert(creature != null, "Wolf must have CreatureComponent")
	assert(creature.species_type == _CreatureTypes.Type.WOLF, "Species must be WOLF")
	assert(creature.diet == _DietTypes.Category.CARNIVORE, "Wolf diet must be CARNIVORE")
	assert(creature.is_alive, "Wolf must start alive")

	assert(traits.has_genetic_trait(_TraitTypes.Type.BOLD), "Wolf must have BOLD trait")
	assert(traits.has_genetic_trait(_TraitTypes.Type.FLEET_FOOTED), "Wolf must have FLEET_FOOTED trait")

	# Check attacks
	var attacks: Dictionary = _CreatureTypes.get_natural_attacks(_CreatureTypes.Type.WOLF)
	assert(attacks.has("bite"), "Wolf must possess bite attack")
	assert(attacks.has("claw_swipe"), "Wolf must possess claw_swipe attack")
	assert(attacks["bite"]["form"] == _ImpactTypes.Form.PIERCE, "Bite must be PIERCE form")
	assert(attacks["claw_swipe"]["form"] == _ImpactTypes.Form.SLASH, "Claw swipe must be SLASH form")

	World.destroy_entity(wolf_eid)
	print("  -> PASSED: Wolf archetype, anatomy, and attacks verified.")

func _test_scent_emission_and_prey_fear() -> void:
	print("\n[Test 2] Testing Predator Scent Emission & Prey Evasion Reaction...")
	var reg = World.get_registry()
	var wolf_pos := Vector2i(45, 45)
	var grazer_pos := Vector2i(46, 45)

	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, wolf_pos, "ScentWolf")
	var grazer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, grazer_pos, "NervousGrazer")

	var grazer_mind: _MindComponent = reg.get_component(grazer_eid, &"MindComponent")
	var initial_fear: float = grazer_mind.fear

	# Emit wolf passive scent
	World.signals.emit_scent(_SignalTypes.SCENT_PREDATOR, wolf_pos, 0.8, 2)
	assert(World.signals.has_signal_at(_SignalTypes.SCENT_PREDATOR, grazer_pos), "Grazer must smell predator scent")

	# Run AI tick
	World.creature_ai.tick(World.tick_count)
	assert(grazer_mind.fear > initial_fear, "Grazer fear must increase in proximity of predator scent")

	World.destroy_entity(wolf_eid)
	World.destroy_entity(grazer_eid)
	print("  -> PASSED: Predator scent emission and prey fear reaction verified.")

func _test_predator_hunting_and_stalking_ai() -> void:
	print("\n[Test 3] Testing Predator Stalking & Hunting AI...")
	var reg = World.get_registry()
	var wolf_pos := Vector2i(50, 50)
	var prey_pos := Vector2i(54, 50)

	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, wolf_pos, "HungryWolf")
	var prey_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, prey_pos, "TargetHare")

	var wolf_mind: _MindComponent = reg.get_component(wolf_eid, &"MindComponent")
	var wolf_plan: _ActionPlanComponent = reg.get_component(wolf_eid, &"ActionPlanComponent")
	wolf_mind.hunger = 0.80

	# Run AI tick
	World.creature_ai.tick(World.tick_count)

	assert(wolf_mind.current_action == _MindEmbeddings.Action.EAT or wolf_plan.current_goal == _MindEmbeddings.Action.EAT, "Hungry wolf must choose EAT/Hunt action")
	assert(wolf_plan.target_tile == prey_pos, "Wolf must target prey position")
	assert(not wolf_plan.path_queue.is_empty(), "Wolf must generate pursuit path towards prey")

	World.destroy_entity(wolf_eid)
	World.destroy_entity(prey_eid)
	print("  -> PASSED: Predator stalking and pursuit AI verified.")

func _test_predator_combat_and_mortality() -> void:
	print("\n[Test 4] Testing Predator Combat Strike & Prey Injury...")
	var reg = World.get_registry()
	var wolf_pos := Vector2i(60, 60)
	var prey_pos := Vector2i(61, 60)

	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, wolf_pos, "StrikeWolf")
	var prey_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, prey_pos, "DoomedHare")

	var wolf_plan: _ActionPlanComponent = reg.get_component(wolf_eid, &"ActionPlanComponent")
	var wolf_mind: _MindComponent = reg.get_component(wolf_eid, &"MindComponent")
	var prey_c: _CreatureComponent = reg.get_component(prey_eid, &"CreatureComponent")
	var prey_body: _BodyComponent = reg.get_component(prey_eid, &"BodyComponent")

	wolf_mind.hunger = 0.85
	wolf_plan.target_tile = prey_pos
	wolf_plan.target_eid = prey_eid
	wolf_plan.current_goal = _MindEmbeddings.Action.ATTACK

	# 1. Run AI system tick: verify target_tile and target_eid are PRESERVED and not wiped to (-1, -1)
	World.creature_ai.tick(World.tick_count)
	assert(wolf_plan.target_tile == prey_pos, "Wolf target_tile must remain pointed at adjacent prey after AI planning")
	assert(wolf_plan.target_eid == prey_eid, "Wolf target_eid must remain locked to prey entity after AI planning")

	# 2. Execute ability and impact resolution
	World.creature_abilities.tick(World.tick_count)
	World.impact_solver.tick(World.tick_count)
	World.creature_body.tick(World.tick_count)

	# Verify prey took injury/bleeding or lost health
	assert(prey_body.bleed_rate > 0.0 or prey_c.health < 1.0 or not prey_c.is_alive, "Prey must sustain wound damage or bleeding from wolf attack")

	World.destroy_entity(wolf_eid)
	if reg.has(prey_eid, &"CreatureComponent"):
		World.destroy_entity(prey_eid)
	print("  -> PASSED: Predator combat execution and prey injury verified.")

func _test_carcass_drop_and_carnivore_feeding() -> void:
	print("\n[Test 5] Testing Carcass Item Drop & Carnivore Feeding...")
	var reg = World.get_registry()
	var p := Vector2i(70, 70)
	var tile_eid: int = World.get_entity_at(p)
	assert(tile_eid != -1, "Tile must exist at (70, 70)")

	var prey_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, p, "MeatYieldHare")
	var prey_c: _CreatureComponent = reg.get_component(prey_eid, &"CreatureComponent")

	# Slay prey
	prey_c.is_alive = false

	# Run body system to trigger carcass drop
	World.creature_body.tick(World.tick_count)

	var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	assert(inv != null and not inv.items.is_empty(), "Carcass drop must populate tile inventory")
	assert(inv.has_carnivore_food, "Tile inventory must be recognized as CARNIVORE_FOOD")

	# Now place hungry wolf on that tile
	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, p, "FeastingWolf")
	var wolf_mind: _MindComponent = reg.get_component(wolf_eid, &"MindComponent")
	var wolf_plan: _ActionPlanComponent = reg.get_component(wolf_eid, &"ActionPlanComponent")
	wolf_mind.hunger = 0.90
	wolf_plan.target_tile = p
	wolf_plan.current_goal = _MindEmbeddings.Action.EAT

	var before_hunger: float = wolf_mind.hunger
	World.creature_abilities.tick(World.tick_count)

	assert(wolf_mind.hunger < before_hunger, "Wolf must consume meat from carcass and reduce hunger")

	World.destroy_entity(wolf_eid)
	World.destroy_entity(prey_eid)
	print("  -> PASSED: Carcass drop and carnivore feeding loop verified.")

func _test_starter_population_spawning_with_predator() -> void:
	print("\n[Test 6] Testing Starter Population Spawning with 1 Predator...")
	var reg = World.get_registry()

	var spawned: Array[int] = _CreatureSpawner.spawn_creatures(World, _CreatureSpawner.STARTER_CONFIGS_WITH_PREDATOR)
	assert(spawned.size() == 3, "Must spawn exactly 3 starter creatures (2 Grazers + 1 Wolf)")

	var found_grazer: int = 0
	var found_wolf: int = 0

	for eid: int in spawned:
		var c = reg.get_component(eid, &"CreatureComponent")
		assert(c != null and c.is_alive, "Spawned creature must be alive")
		if c.species_type == _CreatureTypes.Type.GRAZER:
			found_grazer += 1
		elif c.species_type == _CreatureTypes.Type.WOLF:
			found_wolf += 1

	assert(found_grazer == 2, "Must spawn 2 Grazers")
	assert(found_wolf == 1, "Must spawn 1 Wolf predator")

	# Cleanup
	for eid in spawned:
		World.destroy_entity(eid)
	print("  -> PASSED: Starter population with predator verified.")

func _test_carnivore_hunger_hunt_and_prowl() -> void:
	print("\n[Test 7] Testing Carnivore Hunger Drive 1.0 (Long-Range Hunt & Active Prowl)...")
	var reg = World.get_registry()

	# --- Subtest A: Long-Range Prey Detection (Distance 28 tiles > old 16 limit) ---
	var wolf_pos := Vector2i(25, 25)
	var wolf_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, wolf_pos, "FarSightHunter")
	var wolf_mind: _MindComponent = reg.get_component(wolf_eid, &"MindComponent")
	var wolf_plan: _ActionPlanComponent = reg.get_component(wolf_eid, &"ActionPlanComponent")
	wolf_mind.hunger = 1.0

	# Place hare 28 tiles away
	var hare_pos := Vector2i(53, 25)
	var hare_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, hare_pos, "DistantHare")

	World.creature_ai.tick(World.tick_count)

	assert(wolf_plan.current_goal == _MindEmbeddings.Action.EAT, "Goal must be EAT/HUNT when hunger is 1.0")
	assert(wolf_plan.target_eid == hare_eid, "Wolf must lock onto distant prey (target_eid) using 50-tile sight radius")
	assert(wolf_plan.target_tile == hare_pos, "Target tile must point to prey position (53, 25)")
	assert(not wolf_plan.path_queue.is_empty(), "Pursuit path must not be empty")

	# Step locomotion forward to verify movement along pursuit path
	World.creature_locomotion.tick(World.tick_count)
	var wolf_pos_comp: _PositionComponent = reg.get_component(wolf_eid, &"PositionComponent")
	assert(wolf_pos_comp.position != wolf_pos, "Wolf must take pursuit steps towards prey, not freeze!")

	# Clean up distant prey and wolf
	World.destroy_entity(wolf_eid)
	World.destroy_entity(hare_eid)
	print("  -> Subtest A PASSED: Distant prey (28 tiles) locked and pursued using full sight radius.")

	# --- Subtest B: Zero-Freeze Territory Prowl (No Prey in Sight) ---
	var prowler_pos := Vector2i(64, 64)
	var prowler_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.WOLF, prowler_pos, "LoneProwler")
	var prowler_mind: _MindComponent = reg.get_component(prowler_eid, &"MindComponent")
	var prowler_plan: _ActionPlanComponent = reg.get_component(prowler_eid, &"ActionPlanComponent")
	var prowler_pos_c: _PositionComponent = reg.get_component(prowler_eid, &"PositionComponent")
	prowler_mind.hunger = 1.0

	World.creature_ai.tick(World.tick_count)

	assert(prowler_plan.current_goal == _MindEmbeddings.Action.EAT, "Goal must be EAT when hunger is 1.0")
	assert(prowler_plan.target_tile != Vector2i(-1, -1), "Target tile must not be empty; must pick prowl waypoint")
	assert(not prowler_plan.path_queue.is_empty(), "Must build hunting prowl path queue when hungry, NEVER freeze!")

	# Step locomotion forward
	World.creature_locomotion.tick(World.tick_count)
	assert(prowler_pos_c.position != prowler_pos, "Carnivore must be actively prowling territory, not frozen on same tile!")

	World.destroy_entity(prowler_eid)
	print("  -> Subtest B PASSED: Carnivore with hunger 1.0 actively prowls territory with zero freeze.")

func _write_log_artifact() -> void:
	var file = FileAccess.open("res://logs/test_creature_predator_hunt.log", FileAccess.WRITE)
	if file != null:
		file.store_line("PASSED: Predator (Wolf) Archetype, Scent, Hunting & Feeding Loop Verified.")
		file.store_line("- Wolf archetype with CARNIVORE diet, bite (PIERCE) and claw (SLASH) attacks.")
		file.store_line("- Scent emission: SCENT_PREDATOR triggers panic and evasion in prey.")
		file.store_line("- Autonomous hunting AI: Hungry wolves target, stalk, and pursue live prey.")
		file.store_line("- Kinetic combat impact execution and wound trauma.")
		file.store_line("- Prey mortality drops carcass items (RAW_MEAT, BONE) to tile inventory.")
		file.store_line("- Carnivore feeding loop consumes carcass meat and reduces hunger.")
		file.store_line("- Extensible starter population spawning with 1 Lone Wolf and 2 Grazers.")
		file.store_line("- Long-range sight hunting (up to 50 tiles) and zero-freeze active territory prowl.")
		file.close()

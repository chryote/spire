## TestCreatureImpactOptionB.gd
## Comprehensive integration test suite for Option B:
## Asynchronous Queued ECS Creature Physical Action Force & Impact Solver Coupling.
##
## Tests:
## 1. Fast shallow blow (Hare scratch: low effective mass, high speed, SLASH, surface deformation).
## 2. Fast deep blow (Deer antler gore: massive committed body mass, high speed, PIERCE, deep penetration).
## 3. Newton's Third Law (Bilateral force/stress calculation: Deer antler vs Granite wall).
## 4. Asynchronous ECS Queue Lifecycle (Option B: queue on tick N, resolve on tick N+1).
## 5. End-to-end action execution via CreatureLocomotionSystem when ActionPlan goal is ATTACK.
extends Node2D

const _ImpactTypes          = preload("res://modules/matter/data/ImpactTypes.gd")
const _MaterialTypes        = preload("res://modules/matter/data/MaterialTypes.gd")
const _MatterComponent      = preload("res://modules/matter/components/MatterComponent.gd")
const _ImpactEventComponent = preload("res://modules/matter/components/ImpactEventComponent.gd")
const _ImpactSolverSystem   = preload("res://modules/matter/systems/ImpactSolverSystem.gd")
const _CreatureFactory      = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes        = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureKinematics   = preload("res://modules/creature/data/CreatureKinematics.gd")
const _CreatureComponent    = preload("res://modules/creature/components/CreatureComponent.gd")
const _BodyComponent        = preload("res://modules/creature/components/body/BodyComponent.gd")
const _PositionComponent    = preload("res://modules/creature/components/PositionComponent.gd")
const _ActionPlanComponent  = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings       = preload("res://modules/creature/data/MindEmbeddings.gd")
const _SignalTypes          = preload("res://modules/signal/data/SignalTypes.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE IMPACT (OPTION B) INTEGRATION TESTS ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_test_fast_shallow_blow_hare_scratch()
	_test_fast_deep_blow_deer_antler_gore()
	_test_newtons_third_law_bilateral_stress()
	_test_option_b_asynchronous_ecs_queue_lifecycle()
	_test_creature_action_execution_via_plan()

	print("\n>>> ALL CREATURE IMPACT (OPTION B) TESTS PASSED! <<<\n")
	World.paused = false
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: Fast Shallow Blow (Hare Scratch)
# ---------------------------------------------------------------------------
func _test_fast_shallow_blow_hare_scratch() -> void:
	print("[Test 1] Fast Shallow Blow (Hare Scratch: Low Mass, SLASH, Surface Cut)...")
	var reg = World.get_registry()

	var hare_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, Vector2i(10, 10), "TestHare")
	var creature: _CreatureComponent = reg.get_component(hare_eid, &"CreatureComponent")
	var body: _BodyComponent         = reg.get_component(hare_eid, &"BodyComponent")
	var traits                       = reg.get_component(hare_eid, &"TraitComponent")

	var attack_cfg: Dictionary = _CreatureTypes.get_natural_attack(_CreatureTypes.Type.HARE, "scratch")
	assert(not attack_cfg.is_empty(), "Hare must have 'scratch' natural attack configured")

	var params: _ImpactTypes.ImpactParams = _CreatureKinematics.build_attack_impact_params(
		reg, hare_eid, creature, body, traits, attack_cfg, Vector2(1, 0)
	)

	# Verify shallow blow kinematics:
	# Effective mass should be small (< 1.0 kg), speed high (~8.8 m/s), kinetic energy low (< 35 J)
	assert(params.mass < 1.0, "Hare scratch effective mass must be small (limb only, got %.2f kg)" % params.mass)
	assert(params.velocity.length() >= 7.0, "Hare scratch velocity must be fast (got %.1f m/s)" % params.velocity.length())
	assert(params.kinetic_energy < 35.0, "Hare scratch kinetic energy must be low (<35 J, got %.1f J)" % params.kinetic_energy)
	assert(params.form == _ImpactTypes.Form.SLASH, "Hare scratch must be Form.SLASH")
	assert(params.sharpness >= 1.5, "Hare claw sharpness must be high (got %.1f)" % params.sharpness)

	# Solve against a wooden door/target
	var wood_target = _MatterComponent.new()
	_MaterialTypes.apply_to(wood_target, _MaterialTypes.Type.WOOD_SOFT) # Yield = 15

	var claw_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(claw_matter, _MaterialTypes.Type.BONE)

	var res = _ImpactSolverSystem.solve_impact(claw_matter, wood_target, params)

	# Shallow blow: causes surface deformation / cut, but does NOT shatter the door completely
	assert(res.outcome == _ImpactTypes.Outcome.DEFORMED, "Fast shallow blow must result in DEFORMED surface cut (got %d)" % res.outcome)
	assert(not res.target_fractured, "Fast shallow blow must NOT fracture the whole wooden barrier")
	assert(res.penetration_depth < 0.35, "Fast shallow blow penetration depth must be low (got %.2f)" % res.penetration_depth)
	assert(res.damage_to_target > 0.0, "Wood surface must sustain light yield damage (got %.1f)" % res.damage_to_target)

	World.destroy_entity(hare_eid)
	print("  -> PASSED: Hare scratch verified as fast shallow blow (E=%.1f J, Depth=%.2f)." % [params.kinetic_energy, res.penetration_depth])

# ---------------------------------------------------------------------------
# Test 2: Fast Deep Blow (Deer Antler Gore)
# ---------------------------------------------------------------------------
func _test_fast_deep_blow_deer_antler_gore() -> void:
	print("[Test 2] Fast Deep Blow (Deer Antler Gore: High Mass, PIERCE, Deep Puncture)...")
	var reg = World.get_registry()

	var deer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.DEER, Vector2i(15, 15), "TestDeer")
	var creature: _CreatureComponent = reg.get_component(deer_eid, &"CreatureComponent")
	var body: _BodyComponent         = reg.get_component(deer_eid, &"BodyComponent")
	var traits                       = reg.get_component(deer_eid, &"TraitComponent")

	var attack_cfg: Dictionary = _CreatureTypes.get_natural_attack(_CreatureTypes.Type.DEER, "antler_gore")
	assert(not attack_cfg.is_empty(), "Deer must have 'antler_gore' natural attack configured")

	var params: _ImpactTypes.ImpactParams = _CreatureKinematics.build_attack_impact_params(
		reg, deer_eid, creature, body, traits, attack_cfg, Vector2(1, 0)
	)

	# Verify deep blow kinematics:
	# Effective mass should be massive (> 30 kg backed by body mass), kinetic energy huge (> 400 J)
	assert(params.mass > 30.0, "Deer charge effective mass must be massive (got %.2f kg)" % params.mass)
	assert(params.velocity.length() >= 5.0, "Deer charge velocity must be fast (got %.1f m/s)" % params.velocity.length())
	assert(params.kinetic_energy > 400.0, "Deer charge kinetic energy must be massive (>400 J, got %.1f J)" % params.kinetic_energy)
	assert(params.form == _ImpactTypes.Form.PIERCE, "Deer antler gore must be Form.PIERCE")

	# Solve against a wooden door/target
	var wood_target = _MatterComponent.new()
	_MaterialTypes.apply_to(wood_target, _MaterialTypes.Type.WOOD_SOFT) # Yield = 15

	var antler_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(antler_matter, _MaterialTypes.Type.BONE) # Hardness = 3.0, Yield = 120

	var res = _ImpactSolverSystem.solve_impact(antler_matter, wood_target, params)

	# Deep blow: punches completely through wooden barrier, shattering it into kindling
	assert(res.outcome == _ImpactTypes.Outcome.PENETRATED, "Fast deep blow must PENETRATE barrier (got %d)" % res.outcome)
	assert(res.target_fractured, "Wood barrier must fracture under full deer charge")
	assert(res.penetration_depth >= 0.99, "Fast deep blow must reach full penetration depth (got %.2f)" % res.penetration_depth)
	assert(res.damage_to_target > 50.0, "Target must sustain catastrophic damage (got %.1f)" % res.damage_to_target)
	assert(res.debris_material_id == _MaterialTypes.Type.KINDLING, "Splintered wood must yield kindling debris")

	World.destroy_entity(deer_eid)
	print("  -> PASSED: Deer charge verified as fast deep blow (E=%.1f J, Penetration=%.2f, Fractured=%s)." % [
		params.kinetic_energy, res.penetration_depth, str(res.target_fractured)
	])

# ---------------------------------------------------------------------------
# Test 3: Newton's Third Law (Bilateral Force & Stress: Deer vs Granite Wall)
# ---------------------------------------------------------------------------
func _test_newtons_third_law_bilateral_stress() -> void:
	print("[Test 3] Newton's Third Law (Bilateral Force: Deer Bone Antler vs Granite Wall)...")
	var reg = World.get_registry()

	var deer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.DEER, Vector2i(20, 20), "TestDeer3")
	var creature: _CreatureComponent = reg.get_component(deer_eid, &"CreatureComponent")
	var body: _BodyComponent         = reg.get_component(deer_eid, &"BodyComponent")
	var traits                       = reg.get_component(deer_eid, &"TraitComponent")

	var attack_cfg: Dictionary = _CreatureTypes.get_natural_attack(_CreatureTypes.Type.DEER, "antler_gore")
	var params: _ImpactTypes.ImpactParams = _CreatureKinematics.build_attack_impact_params(
		reg, deer_eid, creature, body, traits, attack_cfg, Vector2(1, 0)
	)

	# Hard stone wall: Hardness = 7.0, Yield = 200
	var stone_wall = _MatterComponent.new()
	_MaterialTypes.apply_to(stone_wall, _MaterialTypes.Type.STONE)

	# Antler: Bone (Hardness = 3.0, Yield = 120)
	var antler_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(antler_matter, _MaterialTypes.Type.BONE)

	var res = _ImpactSolverSystem.solve_impact(antler_matter, stone_wall, params)

	# Stone is much harder than bone -> reaction stress concentrates back into the antler striker!
	assert(res.damage_to_striker > 0.0, "Reaction force must inflict damage on the antler striker (got %.1f)" % res.damage_to_striker)
	assert(res.outcome in [_ImpactTypes.Outcome.DEFLECTED, _ImpactTypes.Outcome.SHATTERED, _ImpactTypes.Outcome.DEFORMED], "Outcome must be deflected, shattered, or surface chipped")
	assert(not res.target_fractured, "Granite wall must NOT fracture against bone antler strike")

	World.destroy_entity(deer_eid)
	print("  -> PASSED: Newton's Third Law verified. Reaction stress damaged antler striker: %.1f." % res.damage_to_striker)

# ---------------------------------------------------------------------------
# Test 4: Option B Asynchronous Queued ECS Lifecycle
# ---------------------------------------------------------------------------
func _test_option_b_asynchronous_ecs_queue_lifecycle() -> void:
	print("[Test 4] Option B Asynchronous Queued ECS Lifecycle...")
	var reg = World.get_registry()

	var deer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.DEER, Vector2i(30, 30), "QueuedDeer")
	var body: _BodyComponent = reg.get_component(deer_eid, &"BodyComponent")
	var initial_stamina: float = reg.get_component(deer_eid, &"CreatureComponent").stamina

	# Create a wooden door target entity
	var door_eid: int = World.create_entity()
	var door_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(door_matter, _MaterialTypes.Type.WOOD_SOFT)
	World.add_component(door_eid, door_matter)
	var initial_door_yield: float = door_matter.yield_strength

	# 1. Queue impact event on tick N via World.creature_locomotion
	var event = World.creature_locomotion.queue_creature_impact(deer_eid, door_eid, "antler_gore")
	assert(event != null, "ImpactEventComponent must be generated and queued")
	assert(not event.processed, "Event must initially be unprocessed")
	assert(event.target_eid == door_eid, "Event target must match door_eid")

	# Check that deer stamina was consumed on attack declaration
	var deer_comp: _CreatureComponent = reg.get_component(deer_eid, &"CreatureComponent")
	assert(deer_comp.stamina < initial_stamina, "Deer stamina must decrease upon queueing physical strike")

	# Verify event is attached to the head limb entity
	var head_limb_eid: int = body.limbs["head"]
	assert(World.has_component(head_limb_eid, &"ImpactEventComponent"), "ImpactEventComponent must reside on striking limb entity")

	# 2. Advance 1 tick (Option B asynchronous execution at priority 165)
	World._run_tick()

	# 3. Verify event was processed and automatically removed
	assert(not World.has_component(head_limb_eid, &"ImpactEventComponent"), "Processed event must be removed from queue on tick N+1")
	assert(door_matter.yield_strength < initial_door_yield, "Target door must have sustained structural damage during tick")

	World.destroy_entity(deer_eid)
	World.destroy_entity(door_eid)
	print("  -> PASSED: Option B Asynchronous Queued ECS Lifecycle successfully verified.")

# ---------------------------------------------------------------------------
# Test 5: End-to-End Action Execution via Creature ActionPlan
# ---------------------------------------------------------------------------
func _test_creature_action_execution_via_plan() -> void:
	print("[Test 5] End-to-End Action Execution via Creature ActionPlan (ATTACK)...")
	var reg = World.get_registry()

	var attacker_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(40, 40), "AttackingGrazer")
	var target_eid: int   = _CreatureFactory.create(World, _CreatureTypes.Type.HARE,   Vector2i(40, 41), "DefendingHare")

	var plan: _ActionPlanComponent  = reg.get_component(attacker_eid, &"ActionPlanComponent")
	var body: _BodyComponent        = reg.get_component(attacker_eid, &"BodyComponent")
	var target_body: _BodyComponent = reg.get_component(target_eid, &"BodyComponent")

	# Configure ActionPlan to attack adjacent target tile (40, 41)
	plan.current_goal = _MindEmbeddings.Action.ATTACK
	plan.target_tile = Vector2i(40, 41)

	# Run CreatureLocomotionSystem tick directly
	World.creature_locomotion.tick(World.tick_count)

	# Verify ImpactEventComponent was attached to the grazer's striking limb
	var head_limb: int = body.limbs["head"]
	assert(World.has_component(head_limb, &"ImpactEventComponent"), "Attack execution must queue ImpactEventComponent on head limb")

	# Advance 1 tick to resolve impact via ImpactSolverSystem
	World._run_tick()

	# Verify target hare took damage / bleeding / mortality
	var target_creature: _CreatureComponent = reg.get_component(target_eid, &"CreatureComponent")
	assert(target_body.bleed_rate > 0.0 or not target_creature.is_alive or target_creature.health < 100.0, "Target hare must sustain injury/bleeding")

	World.destroy_entity(attacker_eid)
	World.destroy_entity(target_eid)
	print("  -> PASSED: End-to-End ActionPlan ATTACK execution verified.")

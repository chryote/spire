## TestCreatureShockAndVitalLimbs.gd
## Integration test verifying:
## - Traumatic shock and pain threshold mechanics (incapacitation, AI suppression, recovery).
## - Genetic trait modifiers (Tough, Frail) on shock pain threshold.
## - Vital vs non-vital limb anatomy (head and torso are vital, legs are non-vital).
## - Limb severing mechanics: inventory item drops into tile's InventoryComponent.
## - Instant mortality upon vital limb (head / torso) loss or destruction.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")
const _MatterComponent     = preload("res://modules/matter/components/MatterComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _ImpactTypes         = preload("res://modules/matter/data/ImpactTypes.gd")
const _ImpactEventComponent= preload("res://modules/matter/components/ImpactEventComponent.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE SHOCK PAIN THRESHOLD & VITAL LIMBS TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	_run_all_tests()

	print("\n>>> ALL SHOCK PAIN THRESHOLD & VITAL LIMB TESTS PASSED! <<<\n")
	World.paused = false
	get_tree().quit(0)

func _run_all_tests() -> void:
	var reg = World.get_registry()
	assert(reg != null, "World registry must be initialized")

	# Ensure system baseline is ready
	World._run_tick()

	_test_shock_threshold_and_recovery(reg)
	_test_trait_shock_modifiers(reg)
	_test_ai_suppression_in_shock(reg)
	_test_non_vital_limb_severing(reg)
	_test_vital_head_severing(reg)
	_test_vital_torso_destruction(reg)
	_test_impact_solver_limb_fracture(reg)

func _test_shock_threshold_and_recovery(reg) -> void:
	print("\n[Test 1] Verifying Shock Pain Threshold and Recovery Dynamics...")
	var spawn_pos := Vector2i(30, 30)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, spawn_pos, "ShockSubject", [])
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")

	assert(mind != null, "Creature must have MindComponent")
	assert(is_equal_approx(mind.shock_pain_threshold, 0.80), "Base shock threshold for Hare should be 0.80, got %f" % mind.shock_pain_threshold)
	assert(not mind.is_in_shock, "Creature should not start in shock")

	# 1. Raise pain above threshold (0.85 >= 0.80)
	mind.pain = 0.85
	# Run a tick to allow CreatureBodySystem to evaluate shock
	World._run_tick()
	assert(mind.is_in_shock, "Pain of 0.85 must trigger traumatic shock")
	assert(mind.shock_ticks > 0, "Shock ticks must increment while in shock")
	print("  -> Creature entered traumatic shock successfully (pain=%.2f, threshold=%.2f, shock_ticks=%d)" % [
		mind.pain, mind.shock_pain_threshold, mind.shock_ticks
	])

	# 2. Lower pain below recovery threshold (0.50 < 0.80 - 0.15 = 0.65)
	mind.pain = 0.50
	World._run_tick()
	assert(not mind.is_in_shock, "Creature must recover from shock when pain subsides below threshold")
	assert(mind.shock_ticks == 0, "Shock ticks must reset to 0 after recovery")
	print("  -> Creature recovered from shock cleanly.")

func _test_trait_shock_modifiers(reg) -> void:
	print("\n[Test 2] Verifying Genetic Trait Modifiers on Shock Threshold...")
	# 1. Tough creature (+0.10 threshold -> 0.90)
	var tough_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, Vector2i(32, 30), "ToughSubject", [_TraitTypes.Type.TOUGH])
	var tough_mind: _MindComponent = reg.get_component(tough_eid, &"MindComponent")
	assert(is_equal_approx(tough_mind.shock_pain_threshold, 0.90), "Tough creature should have 0.90 shock threshold, got %f" % tough_mind.shock_pain_threshold)

	tough_mind.pain = 0.85
	World._run_tick()
	assert(not tough_mind.is_in_shock, "Tough creature at 0.85 pain must NOT enter shock (threshold 0.90)")
	print("  -> Tough trait correctly raised shock threshold to 0.90.")

	# 2. Frail creature (-0.15 threshold -> 0.65)
	var frail_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, Vector2i(34, 30), "FrailSubject", [_TraitTypes.Type.FRAIL])
	var frail_mind: _MindComponent = reg.get_component(frail_eid, &"MindComponent")
	assert(is_equal_approx(frail_mind.shock_pain_threshold, 0.65), "Frail creature should have 0.65 shock threshold, got %f" % frail_mind.shock_pain_threshold)

	frail_mind.pain = 0.70
	World._run_tick()
	assert(frail_mind.is_in_shock, "Frail creature at 0.70 pain MUST enter shock (threshold 0.65)")
	print("  -> Frail trait correctly lowered shock threshold to 0.65.")

func _test_ai_suppression_in_shock(reg) -> void:
	print("\n[Test 3] Verifying AI Planning Suppression / Stun in Shock...")
	var spawn_pos := Vector2i(36, 30)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, spawn_pos, "StunnedSubject", [])
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")
	var plan: _ActionPlanComponent = reg.get_component(creature_eid, &"ActionPlanComponent")

	# Set up active path queue and goal
	plan.current_goal = _MindEmbeddings.Action.WANDER
	plan.path_queue = [spawn_pos + Vector2i.RIGHT, spawn_pos + Vector2i.RIGHT * 2]

	# Trigger shock
	mind.pain = 0.90
	mind.is_in_shock = true

	# Run CreatureAISystem via World tick
	World._run_tick()

	assert(plan.path_queue.is_empty(), "In-shock creature must have its movement path cleared")
	assert(mind.current_action == _MindEmbeddings.Action.REST, "In-shock creature must be forced into REST / incapacitated state")
	print("  -> AI planning correctly stunned and suppressed while in shock.")

func _test_non_vital_limb_severing(reg) -> void:
	print("\n[Test 4] Verifying Non-Vital Limb Severing (Leg)...")
	var spawn_pos := Vector2i(40, 30)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "LegSubject", [])
	var creature: _CreatureComponent = reg.get_component(creature_eid, &"CreatureComponent")
	var body: _BodyComponent = reg.get_component(creature_eid, &"BodyComponent")

	assert(body.limbs.has("left_foreleg"), "Must have left_foreleg limb")
	assert(body.vital_limbs.has("head") and body.vital_limbs.has("torso"), "Vital limbs must be head and torso")
	assert(not body.vital_limbs.has("left_foreleg"), "left_foreleg must NOT be vital")

	# Sever left_foreleg
	var severed_eid: int = body.sever_limb(World, creature_eid, "left_foreleg", reg)
	assert(severed_eid != -1, "Severing must return valid entity ID")
	assert(not body.limbs.has("left_foreleg"), "Severed limb must be removed from body.limbs")
	assert(creature.is_alive, "Creature must remain ALIVE after losing a non-vital limb")
	assert(body.are_vitals_functional(reg), "Vitals must remain functional without left_foreleg")

	# Check mobility reduction
	var mobility: float = body.get_mobility(reg)
	assert(mobility < 1.0, "Mobility must decrease after losing a leg (got %.2f)" % mobility)

	# Verify tile InventoryComponent contains the severed limb
	var tile_eid: int = World.get_entity_at(spawn_pos)
	var tile_inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	assert(tile_inv != null, "Tile must have InventoryComponent")
	assert(tile_inv.items.has(severed_eid), "Tile inventory must contain severed limb item entity")

	var severed_item: _ItemComponent = reg.get_component(severed_eid, &"ItemComponent")
	assert(severed_item != null, "Severed entity must have ItemComponent")
	assert(severed_item.container_id == tile_eid, "Severed item container_id must point to tile_eid")
	assert(severed_item.display_name.begins_with("Severed"), "Severed item display name must include 'Severed'")
	print("  -> Non-vital limb severed cleanly: creature alive (mobility=%.2f), item dropped into tile inventory (items=%s)." % [
		mobility, str(tile_inv.items)
	])

func _test_vital_head_severing(reg) -> void:
	print("\n[Test 5] Verifying Vital Head Severing (Decapitation)...")
	var spawn_pos := Vector2i(42, 30)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "DecapSubject", [])
	var creature: _CreatureComponent = reg.get_component(creature_eid, &"CreatureComponent")
	var body: _BodyComponent = reg.get_component(creature_eid, &"BodyComponent")
	var mind: _MindComponent = reg.get_component(creature_eid, &"MindComponent")

	assert(body.limbs.has("head"), "Must have head limb")

	# Sever head (decapitation)
	var severed_eid: int = body.sever_limb(World, creature_eid, "head", reg)
	assert(severed_eid != -1, "Severing must return valid entity ID")
	assert(not body.limbs.has("head"), "Head must be removed from body.limbs")
	assert(not body.are_vitals_functional(reg), "are_vitals_functional() must return FALSE after losing head")
	assert(not creature.is_alive, "Creature must be DEAD immediately upon decapitation")
	assert(mind.is_in_shock, "Decapitation must induce immediate max shock")
	assert(mind.pain == 1.0, "Decapitation pain must be 1.0")

	# Verify tile InventoryComponent contains the severed head
	var tile_eid: int = World.get_entity_at(spawn_pos)
	var tile_inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	assert(tile_inv != null, "Tile must have InventoryComponent")
	assert(tile_inv.items.has(severed_eid), "Tile inventory must contain severed head entity")
	print("  -> Decapitation verified: creature died instantly, severed head placed in tile inventory.")

func _test_vital_torso_destruction(reg) -> void:
	print("\n[Test 6] Verifying Vital Torso Destruction...")
	var spawn_pos := Vector2i(44, 30)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "TorsoSubject", [])
	var creature: _CreatureComponent = reg.get_component(creature_eid, &"CreatureComponent")
	var body: _BodyComponent = reg.get_component(creature_eid, &"BodyComponent")

	var torso_eid: int = body.limbs["torso"]
	var torso_item: _ItemComponent = reg.get_component(torso_eid, &"ItemComponent")
	assert(torso_item != null, "Torso must be ItemComponent")

	# Destroy torso parts
	torso_item.parts["flesh"]["wear"] = 1.0
	torso_item.parts["bone"]["wear"] = 1.0

	assert(not body.are_vitals_functional(reg), "Destroyed torso must cause are_vitals_functional() to return false")

	# Run CreatureBodySystem via World tick
	World._run_tick()
	assert(not creature.is_alive, "Creature must die after vital torso destruction")
	print("  -> Torso destruction verified: lethal mortality triggered.")

func _test_impact_solver_limb_fracture(reg) -> void:
	print("\n[Test 7] Verifying ImpactSolverSystem Target Limb Fracture Severing...")
	var spawn_pos := Vector2i(46, 30)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "ImpactSubject", [])
	var body: _BodyComponent = reg.get_component(creature_eid, &"BodyComponent")

	var right_hindleg_eid: int = body.limbs["right_hindleg"]

	# Construct an impact event that strikes the limb directly with enough kinetic energy to shatter it
	var impact_solver = null
	for sys in World._sim_systems:
		if sys.get_script().resource_path.ends_with("ImpactSolverSystem.gd"):
			impact_solver = sys
			break
	assert(impact_solver != null, "ImpactSolverSystem must be present in World systems")

	var params := _ImpactTypes.ImpactParams.new()
	params.velocity = Vector2(80.0, 0.0)
	params.mass = 20.0
	params.kinetic_energy = 0.5 * params.mass * 80.0 * 80.0 # 64,000 J
	params.form = _ImpactTypes.Form.SLASH
	params.contact_area = 0.0001
	params.sharpness = 2.0

	# Apply massive striking event to the limb
	var event := _ImpactEventComponent.new()
	event.target_eid = right_hindleg_eid
	event.params = params
	event.remove_on_resolve = true
	reg.add(right_hindleg_eid, event)

	# Run impact solver tick
	impact_solver.tick(1)

	# Verify limb was fractured and severed
	assert(not body.limbs.has("right_hindleg"), "Hindleg must be severed by shattering impact")
	var tile_eid: int = World.get_entity_at(spawn_pos)
	var tile_inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	assert(tile_inv != null and tile_inv.items.has(right_hindleg_eid), "Severed hindleg must be in tile inventory")
	print("  -> ImpactSolverSystem limb fracture successfully severed leg and dropped to tile inventory.")

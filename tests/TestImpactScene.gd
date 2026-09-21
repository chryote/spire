## TestImpactScene.gd
## Comprehensive integration test suite for the Universal Collision & Impact Solver in Spire.
extends Node2D

const _ImpactTypes          = preload("res://modules/matter/data/ImpactTypes.gd")
const _MaterialTypes        = preload("res://modules/matter/data/MaterialTypes.gd")
const _MatterComponent      = preload("res://modules/matter/components/MatterComponent.gd")
const _ImpactEventComponent = preload("res://modules/matter/components/ImpactEventComponent.gd")
const _BurningComponent     = preload("res://modules/matter/components/BurningComponent.gd")
const _ContaminantComponent = preload("res://modules/matter/components/ContaminantComponent.gd")
const _ImpactSolverSystem   = preload("res://modules/matter/systems/ImpactSolverSystem.gd")
const _SignalTypes          = preload("res://modules/signal/data/SignalTypes.gd")

func _ready() -> void:
	print("\n=== STARTING IMPACT SOLVER INTEGRATION TESTS ===")
	# Wait for World to complete initial setup
	await get_tree().process_frame
	await get_tree().process_frame

	var solver = World.impact_solver
	assert(solver != null, "World.impact_solver must be registered and accessible!")

	_test_iron_claw_vs_wood_door()
	_test_iron_vs_iron_ricochet_and_sparks()
	_test_obsidian_brittle_shatter_on_steel()
	_test_solid_into_liquid_splash_and_wetting()
	_test_non_newtonian_oobleck_shear_thickening()
	_test_solid_vs_gas_penetration_and_methane_ignition()
	_test_ecs_entity_resolution_and_sound_emission()

	print("\n>>> ALL IMPACT SOLVER TESTS PASSED SUCCESSFULLY! <<<\n")
	await get_tree().create_timer(5.0).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: Iron Claw vs Soft Wood Door (Hard, high-yield claw shears soft barrier)
# ---------------------------------------------------------------------------
func _test_iron_claw_vs_wood_door() -> void:
	print("[Test 1] Iron Claw vs Wooden Door...")
	var claw = _MatterComponent.new()
	_MaterialTypes.apply_to(claw, _MaterialTypes.Type.STEEL)  # H=6.5, Y=850

	var door = _MatterComponent.new()
	_MaterialTypes.apply_to(door, _MaterialTypes.Type.WOOD_SOFT)  # H=1.5, Y=15

	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 250.0  # 250 Joules
	params.contact_area = 0.00005  # Sharp claw tip
	params.form = _ImpactTypes.Form.PIERCE
	params.sharpness = 1.2

	var result: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(claw, door, params)

	assert(result.outcome == _ImpactTypes.Outcome.PENETRATED, "Claw strike must penetrate wooden barrier")
	assert(result.target_fractured, "Wood door must fracture / yield completely")
	assert(result.damage_to_target > 15.0, "Damage to door must exceed wood yield threshold")
	assert(not result.striker_fractured, "Steel claw must NOT fracture")
	assert(result.damage_to_striker == 0.0, "Steel claw should sustain zero yield wear against soft wood")
	assert(result.sound_loudness >= 0.4, "Impact must generate significant acoustic noise")
	assert(result.debris_material_id == _MaterialTypes.Type.KINDLING, "Splintered wood must generate kindling debris")
	print("  -> PASSED: Iron claw punctured wooden door with 0 wear to claw. Output: %s" % result.summary)

# ---------------------------------------------------------------------------
# Test 2: Iron vs Iron (High hardness on both sides, metallic ring, sparks)
# ---------------------------------------------------------------------------
func _test_iron_vs_iron_ricochet_and_sparks() -> void:
	print("[Test 2] Iron vs Iron (High Hardness Rebound & Sparks)...")
	var striker = _MatterComponent.new()
	_MaterialTypes.apply_to(striker, _MaterialTypes.Type.STEEL)

	var target = _MatterComponent.new()
	_MaterialTypes.apply_to(target, _MaterialTypes.Type.STEEL)

	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 220.0
	params.contact_area = 0.0002
	params.form = _ImpactTypes.Form.SLASH
	params.velocity = Vector2(15.0, -10.0)

	var result: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(striker, target, params)

	assert(result.outcome == _ImpactTypes.Outcome.DEFLECTED, "Equal steel blades/surfaces should deflect")
	assert(not result.target_fractured, "Steel armor should not fracture under 220J slash")
	assert(not result.striker_fractured, "Striker blade should not fracture")
	assert(result.sparks_produced, "Friction between hard metals (H >= 5.0) must produce sparks")
	assert(result.rebound_energy > 1.0, "Elastic bounce must preserve residual kinetic energy")
	assert(result.sound_loudness >= 0.5, "Loud metallic clang must be generated")
	print("  -> PASSED: Metallic deflection produced sparks and acoustic clang.")

# ---------------------------------------------------------------------------
# Test 3: Obsidian vs Steel (Brittle shatter on hard tough barrier)
# ---------------------------------------------------------------------------
func _test_obsidian_brittle_shatter_on_steel() -> void:
	print("[Test 3] Obsidian Projectile vs Steel Armor (Brittle Shatter)...")
	var obsidian_proj = _MatterComponent.new()
	_MaterialTypes.apply_to(obsidian_proj, _MaterialTypes.Type.OBSIDIAN)  # H=5.5, Y=40, E=0.01

	var steel_armor = _MatterComponent.new()
	_MaterialTypes.apply_to(steel_armor, _MaterialTypes.Type.STEEL)  # H=6.5, Y=850, E=0.3

	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 160.0
	params.contact_area = 0.0001
	params.form = _ImpactTypes.Form.PROJECTILE

	var result: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(obsidian_proj, steel_armor, params)

	assert(result.outcome == _ImpactTypes.Outcome.SHATTERED, "Brittle obsidian must shatter on steel")
	assert(result.striker_fractured, "Striker obsidian must be destroyed/fractured")
	assert(not result.target_fractured, "Steel target must easily survive intact")
	assert(result.debris_material_id == _MaterialTypes.Type.DIRT, "Shattered obsidian produces shard debris")
	print("  -> PASSED: Brittle obsidian shattered completely upon steel contact.")

# ---------------------------------------------------------------------------
# Test 4: Solid into Liquid (Splash, Drag, Wetting & Contaminant transfer)
# ---------------------------------------------------------------------------
func _test_solid_into_liquid_splash_and_wetting() -> void:
	print("[Test 4] Thrown Stone into Water & Acid (Drag, Splash, Wetting)...")
	var stone = _MatterComponent.new()
	_MaterialTypes.apply_to(stone, _MaterialTypes.Type.STONE)

	var water = _MatterComponent.new()
	_MaterialTypes.apply_to(water, _MaterialTypes.Type.WATER)

	var params = _ImpactTypes.ImpactParams.from_motion(2.0, Vector2(0.0, 15.0), 0.005, _ImpactTypes.Form.PROJECTILE)

	var result: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(stone, water, params)

	assert(result.outcome == _ImpactTypes.Outcome.SPLASHED, "Fast projectile into water must splash")
	assert(result.energy_absorbed > 50.0, "Fluid drag must absorb substantial kinetic energy")
	assert(result.contaminants_transferred.has("moisture"), "Water impact must wet the stone")
	assert(result.contaminants_transferred["moisture"] > 0.3, "Moisture level must increase")
	assert(result.sound_loudness >= 0.25, "Water splash sound generated")

	# Test 4b: Striker hits corrosive acid / Greek fire
	var greek_fire = _MatterComponent.new()
	_MaterialTypes.apply_to(greek_fire, _MaterialTypes.Type.GREEK_FIRE)
	var acid_res: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(stone, greek_fire, params)
	assert(acid_res.contaminants_transferred.has("corrosion"), "Acid/corrosive fluid must transfer corrosion contaminant")
	print("  -> PASSED: Fluid drag decelerated striker, triggered splash, and transferred wetting/corrosion.")

# ---------------------------------------------------------------------------
# Test 5: Non-Newtonian Oobleck Shear Thickening
# ---------------------------------------------------------------------------
func _test_non_newtonian_oobleck_shear_thickening() -> void:
	print("[Test 5] Non-Newtonian Oobleck (Shear Thickening Dynamics)...")
	var iron_slug = _MatterComponent.new()
	_MaterialTypes.apply_to(iron_slug, _MaterialTypes.Type.STEEL)

	var oobleck = _MatterComponent.new()
	_MaterialTypes.apply_to(oobleck, _MaterialTypes.Type.OOBLECK)

	# 5a. High velocity strike: acts like solid barrier
	var fast_params = _ImpactTypes.ImpactParams.from_motion(0.5, Vector2(25.0, 0.0), 0.0001, _ImpactTypes.Form.PROJECTILE)
	var fast_res: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(iron_slug, oobleck, fast_params)
	assert(fast_res.outcome in [_ImpactTypes.Outcome.DEFLECTED, _ImpactTypes.Outcome.DEFORMED, _ImpactTypes.Outcome.SHATTERED],
		"High-velocity strike must experience solid resistance from Oobleck")

	# 5b. Low velocity movement: sinks gently like fluid
	var slow_params = _ImpactTypes.ImpactParams.from_motion(0.5, Vector2(1.0, 0.0), 0.0001, _ImpactTypes.Form.BLUNT)
	var slow_res: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(iron_slug, oobleck, slow_params)
	assert(slow_res.outcome == _ImpactTypes.Outcome.ABSORBED, "Low-velocity motion must gently sink in fluid")
	print("  -> PASSED: Oobleck acted as rigid solid under high velocity and compliant fluid under low velocity.")

# ---------------------------------------------------------------------------
# Test 6: Solid vs Gas (Penetration & Flammable Methane Auto-Ignition)
# ---------------------------------------------------------------------------
func _test_solid_vs_gas_penetration_and_methane_ignition() -> void:
	print("[Test 6] Solid vs Gas (Chlorine Drag & Cave Methane Auto-Ignition)...")
	var arrow = _MatterComponent.new()
	_MaterialTypes.apply_to(arrow, _MaterialTypes.Type.WOOD_HARD)

	var chlorine = _MatterComponent.new()
	_MaterialTypes.apply_to(chlorine, _MaterialTypes.Type.CHLORINE)

	var params = _ImpactTypes.ImpactParams.from_motion(0.1, Vector2(40.0, 0.0), 0.0001, _ImpactTypes.Form.PROJECTILE)
	var res: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(arrow, chlorine, params)

	assert(res.outcome == _ImpactTypes.Outcome.PASSED_THROUGH, "Projectile must pass through gas")
	assert(res.rebound_velocity.x > 38.0, "Gas must exert negligible aerodynamic drag")
	assert(res.contaminants_transferred.has("toxicity"), "Passing through chlorine coats toxic residue")

	# 6b. Red-hot arrow through Cave Methane (500C ignition threshold)
	var methane = _MatterComponent.new()
	_MaterialTypes.apply_to(methane, _MaterialTypes.Type.CAVE_METHANE)

	var hot_params = _ImpactTypes.ImpactParams.from_motion(0.1, Vector2(40.0, 0.0), 0.0001, _ImpactTypes.Form.PROJECTILE)
	hot_params.temperature_c = 550.0  # Hot flaming projectile exceeds 500C ignition
	var hot_res: _ImpactTypes.ImpactResult = _ImpactSolverSystem.solve_impact(arrow, methane, hot_params)

	assert(hot_res.ignition_occurred, "Hot projectile in flammable methane must trigger combustion")
	print("  -> PASSED: Gas penetration confirmed; flaming projectile ignited explosive methane.")

# ---------------------------------------------------------------------------
# Test 7: ECS Entity Resolution, Sound Signal & Event Queue
# ---------------------------------------------------------------------------
func _test_ecs_entity_resolution_and_sound_emission() -> void:
	print("[Test 7] Full ECS Entity Resolution & Sound Signal Emission...")
	var test_pos = Vector2i(42, 42)
	var tile_eid: int = World.get_entity_at(test_pos)
	assert(tile_eid != -1, "Target tile entity must exist")

	# 7a. Attacking a standalone wooden door entity in ECS
	var creature_eid: int = World.create_entity()
	var claw_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(claw_matter, _MaterialTypes.Type.STEEL)
	World.add_component(creature_eid, claw_matter)

	var door_eid: int = World.create_entity()
	var door_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(door_matter, _MaterialTypes.Type.WOOD_SOFT)
	World.add_component(door_eid, door_matter)
	var initial_door_yield: float = door_matter.yield_strength
	assert(initial_door_yield > 0.0, "Door must have positive initial yield strength")

	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 180.0
	params.contact_area = 0.00005
	params.form = _ImpactTypes.Form.SLASH

	var res: _ImpactTypes.ImpactResult = World.impact_solver.resolve_entity_impact(creature_eid, door_eid, params)
	assert(res != null, "Entity impact must resolve successfully")
	assert(res.damage_to_target > 0.0, "Target must sustain structural damage")
	assert(res.target_fractured, "Door must fracture under 180J claw strike")
	assert(door_matter.yield_strength < initial_door_yield, "Target yield strength must decrease")

	# 7b. Striking a world tile entity and testing sound emission to SignalSystem
	var tile_res: _ImpactTypes.ImpactResult = World.impact_solver.resolve_entity_impact(creature_eid, tile_eid, params)
	assert(tile_res != null, "Tile impact must resolve")
	if World.signals != null:
		var sound_val: float = World.signals.get_signal(_SignalTypes.SOUND, test_pos)
		assert(sound_val > 0.0, "Impact must emit acoustic sound signal onto target tile")

	# 7c. Asynchronous ImpactEventComponent via tick queue
	var projectile_eid: int = World.create_entity()
	var p_event = _ImpactEventComponent.new()
	p_event.target_eid = tile_eid
	p_event.params = params
	World.add_component(projectile_eid, p_event)

	# Advance 1 tick
	World._run_tick()

	assert(not World.has_component(projectile_eid, &"ImpactEventComponent"), "Processed event must be removed from queue")

	# Clean up temporary entities
	World.destroy_entity(creature_eid)
	World.destroy_entity(door_eid)
	World.destroy_entity(projectile_eid)
	print("  -> PASSED: ECS entity resolution, sound signal emission, and event queue verified.")


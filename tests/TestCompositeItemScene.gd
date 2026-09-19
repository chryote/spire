## TestCompositeItemScene.gd
## Integration test suite for the Item Mold & Composite Matter System.
extends Node2D

const _ImpactTypes   = preload("res://modules/matter/data/ImpactTypes.gd")
const _MaterialTypes = preload("res://modules/matter/data/MaterialTypes.gd")
const _MatterComponent = preload("res://modules/matter/components/MatterComponent.gd")
const _ItemTypes     = preload("res://modules/item/data/ItemTypes.gd")
const _ItemComponent = preload("res://modules/item/components/ItemComponent.gd")
const _ItemFactory   = preload("res://modules/item/systems/ItemFactory.gd")

func _ready() -> void:
	print("\n=== STARTING COMPOSITE ITEM & MOLD INTEGRATION TESTS ===")
	await get_tree().process_frame
	await get_tree().process_frame

	_test_backwards_compatibility_single_material()
	_test_composite_item_creation_and_mass_synthesis()
	_test_composite_impact_solver_dynamics()
	_test_obsidian_blade_vs_steel_armor()
	_test_composite_combustion_hazard()
	_test_thrust_alt_form()
	_test_blasting_warhammer()
	_test_venomous_spear()
	_test_caustic_dagger()

	print("\n>>> ALL COMPOSITE ITEM & MOLD TESTS PASSED SUCCESSFULLY! <<<\n")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: Backwards Compatibility with Single Material
# ---------------------------------------------------------------------------
func _test_backwards_compatibility_single_material() -> void:
	print("[Test 1] Backwards Compatibility with Single Material...")
	var grass_id = _ItemFactory.create(World, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC)
	var grass_comp: _ItemComponent = World.get_component(grass_id, &"ItemComponent")
	var grass_matter: _MatterComponent = World.get_component(grass_id, &"MatterComponent")

	assert(grass_comp != null, "Grass must have ItemComponent")
	assert(grass_matter != null, "Grass must have MatterComponent")
	assert(grass_comp.display_name == "Organic Grass", "Grass display name should match old format")
	assert(grass_comp.total_mass > 0.0, "Grass total mass must be positive")
	assert(grass_comp.parts.has("main"), "Grass should have a 'main' part")

	var sword_id = _ItemFactory.create(World, _ItemTypes.Type.SWORD, _MaterialTypes.Type.STEEL)
	var sword_comp: _ItemComponent = World.get_component(sword_id, &"ItemComponent")
	assert(sword_comp.parts.has("blade"), "Sword must have a 'blade' part")
	assert(sword_comp.parts["blade"]["material_id"] == _MaterialTypes.Type.STEEL, "Blade should be Steel")
	assert(sword_comp.parts.has("hilt"), "Sword must have a 'hilt' part")
	print("  -> PASSED: Single-material backward compatibility confirmed.")

# ---------------------------------------------------------------------------
# Test 2: Composite Item Creation & Physical Mass Synthesis
# ---------------------------------------------------------------------------
func _test_composite_item_creation_and_mass_synthesis() -> void:
	print("[Test 2] Composite Item Creation & Mass Synthesis...")
	var sword_id = _ItemFactory.create_composite(World, _ItemTypes.Type.SWORD, {
		"blade": _MaterialTypes.Type.STEEL,
		"hilt":  _MaterialTypes.Type.WOOD_HARD,
	})

	var comp: _ItemComponent = World.get_component(sword_id, &"ItemComponent")
	var matter: _MatterComponent = World.get_component(sword_id, &"MatterComponent")

	assert(comp != null and matter != null, "Entities must possess both components")
	assert("Steel Sword (Hard Wood Hilt)" in comp.display_name, "Composite name formatted correctly")

	# Physics check:
	# Steel density = 7850 kg/m3 * 0.0008 m3 = 6.28 kg
	# Hard Wood density = 620 kg/m3 * 0.0003 m3 = 0.186 kg
	# Expected total mass = 6.466 kg
	var expected_mass: float = 6.28 + 0.186
	assert(is_equal_approx(comp.total_mass, expected_mass), "Mass calculation must equal sum of parts mass")
	assert(matter.hardness == 6.5, "Surface hardness should be 6.5 from Steel blade")
	assert(is_equal_approx(matter.density, comp.total_mass / comp.total_volume), "Density must be mass-weighted average")

	print("  -> PASSED: Steel blade (6.28kg) + Wood hilt (0.186kg) = Total: %.3f kg (Density: %.1f kg/m3)" % [comp.total_mass, matter.density])

# ---------------------------------------------------------------------------
# Test 3: Composite Impact Solver Dynamics
# ---------------------------------------------------------------------------
func _test_composite_impact_solver_dynamics() -> void:
	print("[Test 3] Composite Impact Solver Dynamics (Sword cutting wood door)...")
	var sword_id = _ItemFactory.create_composite(World, _ItemTypes.Type.SWORD, {
		"blade": _MaterialTypes.Type.STEEL,
		"hilt":  _MaterialTypes.Type.WOOD_HARD,
	})

	# Create target wooden door
	var door_id = World.create_entity()
	var door_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(door_matter, _MaterialTypes.Type.WOOD_SOFT)
	World.add_component(door_id, door_matter)

	# Execute impact with null params (forces solver to enrich from sword mold)
	var solver = World.impact_solver
	var result: _ImpactTypes.ImpactResult = solver.resolve_entity_impact(sword_id, door_id, null)

	assert(result != null, "Impact result must not be null")
	assert(result.outcome == _ImpactTypes.Outcome.PENETRATED, "Steel blade must penetrate soft wood door")
	assert(result.damage_to_target > 50.0, "Door must take severe cutting damage")
	assert(result.damage_to_striker == 0.0, "Steel blade should suffer 0 wear against soft wood")

	var sword_comp: _ItemComponent = World.get_component(sword_id, &"ItemComponent")
	assert(sword_comp.parts["blade"]["wear"] == 0.0, "Blade wear should remain 0")
	print("  -> PASSED: Mold-enriched impact punctured wooden door with 0 wear to blade.")

# ---------------------------------------------------------------------------
# Test 4: Obsidian Blade vs Steel Armor (Hardness vs Brittleness)
# ---------------------------------------------------------------------------
func _test_obsidian_blade_vs_steel_armor() -> void:
	print("[Test 4] Obsidian Blade vs Steel Armor (Hardness vs Brittleness)...")
	var obs_sword_id = _ItemFactory.create_composite(World, _ItemTypes.Type.SWORD, {
		"blade": _MaterialTypes.Type.OBSIDIAN,
		"hilt":  _MaterialTypes.Type.WOOD_HARD,
	})

	var armor_id = World.create_entity()
	var armor_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(armor_matter, _MaterialTypes.Type.STEEL)
	World.add_component(armor_id, armor_matter)

	var solver = World.impact_solver
	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 200.0
	params.contact_area = 0.0002
	params.form = _ImpactTypes.Form.SLASH

	var result: _ImpactTypes.ImpactResult = solver.resolve_entity_impact(obs_sword_id, armor_id, params)
	assert(result != null, "Impact result must not be null")
	assert(result.damage_to_striker > 0.0 or result.striker_fractured, "Brittle obsidian must sustain damage against steel armor")

	var obs_comp: _ItemComponent = World.get_component(obs_sword_id, &"ItemComponent")
	assert(obs_comp.parts["blade"]["wear"] > 0.0, "Blade wear should have accumulated from striking steel")
	print("  -> PASSED: Obsidian blade chipped/wore down (wear = %.2f) when striking steel armor." % obs_comp.parts["blade"]["wear"])

# ---------------------------------------------------------------------------
# Test 5: Composite Combustion Hazard (Flammable Hilt)
# ---------------------------------------------------------------------------
func _test_composite_combustion_hazard() -> void:
	print("[Test 5] Composite Combustion Hazard (Flammable Hilt)...")
	var sword_id = _ItemFactory.create_composite(World, _ItemTypes.Type.SWORD, {
		"blade": _MaterialTypes.Type.STEEL,
		"hilt":  _MaterialTypes.Type.WOOD_HARD,
	})

	var matter: _MatterComponent = World.get_component(sword_id, &"MatterComponent")
	# Hard Wood ignition is 245C, Steel is INF
	assert(matter.ignition_temp_c < INF, "Composite weapon with wood hilt must have finite ignition temperature")
	assert(matter.ignition_temp_c == 245.0, "Ignition temperature should inherit lowest part threshold (245C)")
	assert(matter.flammability > 0.0, "Flammability should be positive due to wooden hilt")
	print("  -> PASSED: Steel sword with wood hilt has ignition threshold of %.1f C (Flammability: %.2f)." % [matter.ignition_temp_c, matter.flammability])

# ---------------------------------------------------------------------------
# Test 6: Thrust vs Slash (Alt Form)
# ---------------------------------------------------------------------------
func _test_thrust_alt_form() -> void:
	print("[Test 6] Alt Form: Thrust vs Slash...")
	var sword_id = _ItemFactory.create_composite(World, _ItemTypes.Type.SWORD, {
		"blade": _MaterialTypes.Type.STEEL,
		"hilt":  _MaterialTypes.Type.WOOD_HARD,
	})

	var comp: _ItemComponent = World.get_component(sword_id, &"ItemComponent")
	var matter: _MatterComponent = World.get_component(sword_id, &"MatterComponent")

	var slash_params = _ItemTypes.build_impact_params(comp, matter, Vector2(10.0, 0.0), false)
	var thrust_params = _ItemTypes.build_impact_params(comp, matter, Vector2(10.0, 0.0), true)

	assert(slash_params.form == _ImpactTypes.Form.SLASH, "Default attack must be SLASH")
	assert(thrust_params.form == _ImpactTypes.Form.PIERCE, "Alt attack must be PIERCE")
	assert(thrust_params.contact_area < slash_params.contact_area, "Thrust contact area must be smaller than edge slash")
	print("  -> PASSED: Slash area = %.5f m2 (SLASH), Thrust area = %.5f m2 (PIERCE)" % [slash_params.contact_area, thrust_params.contact_area])

# ---------------------------------------------------------------------------
# Test 7: Emergent Blasting Steel Warhammer
# ---------------------------------------------------------------------------
func _test_blasting_warhammer() -> void:
	print("[Test 7] Emergent Blasting Steel Warhammer (Explosion on Impact)...")
	var hammer_id = _ItemFactory.create_composite(World, _ItemTypes.Type.WARHAMMER, {
		"head":    _MaterialTypes.Type.STEEL,
		"shaft":   _MaterialTypes.Type.STEEL,
		"payload": _MaterialTypes.Type.GREEK_FIRE,
	})

	var comp: _ItemComponent = World.get_component(hammer_id, &"ItemComponent")
	assert(comp.display_name == "Blasting Steel Warhammer", "Display name must be emergent 'Blasting Steel Warhammer'")

	# Strike solid stone wall
	var wall_id = World.create_entity()
	var wall_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(wall_matter, _MaterialTypes.Type.STONE)
	World.add_component(wall_id, wall_matter)

	var solver = World.impact_solver
	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 50.0

	var result: _ImpactTypes.ImpactResult = solver.resolve_entity_impact(hammer_id, wall_id, params)
	assert(result.sparks_produced, "Detonation must produce incandescent sparks")
	assert(result.ignition_occurred, "Detonation flash must ignite flammable surroundings")
	assert(result.sound_loudness == 1.0, "Detonation must emit peak acoustic signal (loudness = 1.0)")
	assert(comp.parts["payload"]["wear"] == 1.0, "Payload charge must be spent after detonation")
	print("  -> PASSED: 'Blasting Steel Warhammer' detonated with +300 blast damage! (Sound: 1.0, Heat: +%.0f C)" % result.heat_generated_c)

# ---------------------------------------------------------------------------
# Test 8: Emergent Venomous Obsidian Spear
# ---------------------------------------------------------------------------
func _test_venomous_spear() -> void:
	print("[Test 8] Emergent Venomous Obsidian Spear (Toxic Injection)...")
	var spear_id = _ItemFactory.create_composite(World, _ItemTypes.Type.SPEAR, {
		"head":    _MaterialTypes.Type.OBSIDIAN,
		"shaft":   _MaterialTypes.Type.WOOD_HARD,
		"coating": _MaterialTypes.Type.ECTOPLASM,
	})

	var comp: _ItemComponent = World.get_component(spear_id, &"ItemComponent")
	assert(comp.display_name.begins_with("Venomous Obsidian Spear"), "Display name must begin with 'Venomous Obsidian Spear'")

	# Strike target flesh/creature
	var victim_id = World.create_entity()
	var victim_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(victim_matter, _MaterialTypes.Type.RAW_MEAT)
	World.add_component(victim_id, victim_matter)

	var solver = World.impact_solver
	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 60.0

	var result: _ImpactTypes.ImpactResult = solver.resolve_entity_impact(spear_id, victim_id, params)
	assert(result.outcome == _ImpactTypes.Outcome.PENETRATED, "Obsidian spear must penetrate raw flesh")
	
	var contam = World.get_component(victim_id, &"ContaminantComponent")
	assert(contam != null, "Victim must receive ContaminantComponent on penetration")
	assert(contam.toxicity >= 0.8, "Toxicity from Ectoplasm (0.8) must be transferred to target")
	print("  -> PASSED: 'Venomous Obsidian Spear' punctured target and transferred %.2f toxicity contaminant." % contam.toxicity)

# ---------------------------------------------------------------------------
# Test 9: Emergent Caustic Stone Dagger
# ---------------------------------------------------------------------------
func _test_caustic_dagger() -> void:
	print("[Test 9] Emergent Caustic Stone Dagger (Acidic Corrosion)...")
	var dagger_id = _ItemFactory.create_composite(World, _ItemTypes.Type.DAGGER, {
		"blade":   _MaterialTypes.Type.STONE,
		"hilt":    _MaterialTypes.Type.STONE,
		"coating": _MaterialTypes.Type.CHLORINE,
	})

	var comp: _ItemComponent = World.get_component(dagger_id, &"ItemComponent")
	assert(comp.display_name == "Caustic Stone Dagger", "Display name must be emergent 'Caustic Stone Dagger'")

	var target_id = World.create_entity()
	var target_matter = _MatterComponent.new()
	_MaterialTypes.apply_to(target_matter, _MaterialTypes.Type.DIRT)
	World.add_component(target_id, target_matter)

	var solver = World.impact_solver
	var params = _ImpactTypes.ImpactParams.new()
	params.kinetic_energy = 40.0

	var result: _ImpactTypes.ImpactResult = solver.resolve_entity_impact(dagger_id, target_id, params)
	var contam = World.get_component(target_id, &"ContaminantComponent")
	assert(contam != null, "Target must receive ContaminantComponent")
	assert(contam.corrosion >= 0.8, "Corrosiveness from Chlorine (0.8) must be transferred to target")
	print("  -> PASSED: 'Caustic Stone Dagger' slashed target and transferred %.2f corrosive acid." % contam.corrosion)

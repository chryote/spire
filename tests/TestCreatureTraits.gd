## TestCreatureTraits.gd
## Integration test verifying Creature TraitSystem:
## - Genetic profile assignment and custom genetic initialization.
## - Behavior weighting on Utility AI (Timid vs. Bold flee weighting, Gluttonous grazing weighting).
## - Buff and debuff lifecycle, tick duration expiration, and threshold-triggered status conditions.
## - Physiological modulation (movement cooldowns, metabolism).
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE DATA-DRIVEN TRAIT SYSTEM TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	_test_genetic_profile_spawning()
	_test_trait_behavior_utility_weighting()
	_test_buff_debuff_thresholds_and_lifecycle()
	_test_physical_trait_modifiers()

	print("\n>>> ALL CREATURE TRAIT SYSTEM TESTS PASSED! <<<\n")
	_write_log_artifact()
	World.paused = false
	get_tree().quit(0)

func _test_genetic_profile_spawning() -> void:
	print("\n[Test 1] Testing genetic profile assignment and species archetypes...")
	var reg = World.get_registry()
	assert(reg != null, "World registry must be valid")

	var spawn_pos := Vector2i(40, 40)
	var grazer_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, spawn_pos, "TestGrazer")
	var hare_eid: int   = _CreatureFactory.create(World, _CreatureTypes.Type.HARE, spawn_pos, "TestHare")
	var deer_eid: int   = _CreatureFactory.create(World, _CreatureTypes.Type.DEER, spawn_pos, "TestDeer")

	var g_traits: _TraitComponent = reg.get_component(grazer_eid, &"TraitComponent")
	var h_traits: _TraitComponent = reg.get_component(hare_eid, &"TraitComponent")
	var d_traits: _TraitComponent = reg.get_component(deer_eid, &"TraitComponent")

	assert(g_traits != null, "Grazer must have TraitComponent")
	assert(h_traits != null, "Hare must have TraitComponent")
	assert(d_traits != null, "Deer must have TraitComponent")

	assert(g_traits.has_genetic_trait(_TraitTypes.Type.HARDY), "Grazer must possess innate Hardy trait")
	assert(h_traits.has_genetic_trait(_TraitTypes.Type.TIMID), "Hare must possess innate Timid trait")
	assert(h_traits.has_genetic_trait(_TraitTypes.Type.FLEET_FOOTED), "Hare must possess innate Fleet-Footed trait")
	assert(d_traits.has_genetic_trait(_TraitTypes.Type.CURIOUS), "Deer must possess innate Curious trait")
	assert(d_traits.has_genetic_trait(_TraitTypes.Type.FLEET_FOOTED), "Deer must possess innate Fleet-Footed trait")

	# Test custom genetic traits override
	var custom_eid: int = _CreatureFactory.create(
		World,
		_CreatureTypes.Type.GRAZER,
		spawn_pos,
		"CustomGrazer",
		[_TraitTypes.Type.GLUTTONOUS, _TraitTypes.Type.SLOTHFUL]
	)
	var c_traits: _TraitComponent = reg.get_component(custom_eid, &"TraitComponent")
	assert(c_traits.has_genetic_trait(_TraitTypes.Type.GLUTTONOUS), "Custom creature must possess Gluttonous trait")
	assert(c_traits.has_genetic_trait(_TraitTypes.Type.SLOTHFUL), "Custom creature must possess Slothful trait")

	print("  -> PASSED: Species archetypes and genetic profiles initialized accurately.")

func _test_trait_behavior_utility_weighting() -> void:
	print("\n[Test 2] Testing Trait utility AI behavior weighting...")
	var reg = World.get_registry()

	var p := Vector2i(55, 55)
	var timid_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "TimidCreature", [_TraitTypes.Type.TIMID])
	var bold_eid: int  = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "BoldCreature", [_TraitTypes.Type.BOLD])

	var timid_mind: _MindComponent = reg.get_component(timid_eid, &"MindComponent")
	var bold_mind: _MindComponent  = reg.get_component(bold_eid, &"MindComponent")

	# Set moderate fear on both
	timid_mind.fear = 0.30
	bold_mind.fear  = 0.30

	World._run_tick()

	var timid_flee_u: float = timid_mind.action_utilities.get(_MindEmbeddings.Action.FLEE, 0.0)
	var bold_flee_u: float  = bold_mind.action_utilities.get(_MindEmbeddings.Action.FLEE, 0.0)

	print("  Timid Flee Utility: %.2f | Bold Flee Utility: %.2f" % [timid_flee_u, bold_flee_u])
	assert(timid_flee_u > bold_flee_u, "Timid creature must evaluate FLEE utility higher than Bold creature")

	# Test Gluttonous vs. Normal on GRAZE
	var normal_eid: int     = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "NormalCreature", [_TraitTypes.Type.HARDY])
	var glutton_eid: int    = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "GluttonCreature", [_TraitTypes.Type.HARDY, _TraitTypes.Type.GLUTTONOUS])
	var normal_mind: _MindComponent  = reg.get_component(normal_eid, &"MindComponent")
	var glutton_mind: _MindComponent = reg.get_component(glutton_eid, &"MindComponent")

	normal_mind.hunger  = 0.35
	glutton_mind.hunger = 0.35

	World._run_tick()

	var normal_eat_u: float  = normal_mind.action_utilities.get(_MindEmbeddings.Action.EAT, 0.0)
	var glutton_eat_u: float = glutton_mind.action_utilities.get(_MindEmbeddings.Action.EAT, 0.0)

	print("  Glutton Eat Utility: %.2f | Normal Eat Utility: %.2f" % [glutton_eat_u, normal_eat_u])
	assert(glutton_eat_u > normal_eat_u, "Gluttonous creature must evaluate EAT utility higher than normal creature")

	print("  -> PASSED: Trait-weighted Utility AI decisions verified.")

func _test_buff_debuff_thresholds_and_lifecycle() -> void:
	print("\n[Test 3] Testing buff/debuff lifecycles and threshold triggers...")
	var reg = World.get_registry()

	var eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, Vector2i(60, 60), "StatusTester", [])
	var traits: _TraitComponent = reg.get_component(eid, &"TraitComponent")
	var mind: _MindComponent    = reg.get_component(eid, &"MindComponent")
	var c_comp: _CreatureComponent = reg.get_component(eid, &"CreatureComponent")

	# 1. Starvation trigger
	mind.hunger = 0.90
	World._run_tick()
	assert(traits.has_debuff(_TraitTypes.Type.STARVING), "Hunger >= 0.85 must trigger STARVING debuff")

	# 2. Satiation & Well-Fed trigger
	mind.hunger = 0.10
	c_comp.stomach_fill = c_comp.stomach_capacity * 0.85
	World._run_tick()
	assert(not traits.has_debuff(_TraitTypes.Type.STARVING), "Satiated hunger must clear STARVING debuff")
	assert(traits.has_buff(_TraitTypes.Type.WELL_FED), "Stomach fill >= 70% must trigger WELL_FED buff")

	# 3. Thirst & Dehydration trigger
	mind.thirst = 0.90
	World._run_tick()
	assert(traits.has_debuff(_TraitTypes.Type.DEHYDRATED), "Thirst >= 0.85 must trigger DEHYDRATED debuff")

	# 4. Hydrated trigger
	mind.thirst = 0.10
	World._run_tick()
	assert(not traits.has_debuff(_TraitTypes.Type.DEHYDRATED), "Low thirst must clear DEHYDRATED debuff")
	assert(traits.has_buff(_TraitTypes.Type.HYDRATED), "Thirst <= 0.20 must trigger HYDRATED buff")

	# 5. Panic & Adrenaline Rush trigger
	mind.fear = 0.80
	World._run_tick()
	assert(traits.has_debuff(_TraitTypes.Type.PANICKED), "Fear >= 0.70 must trigger PANICKED debuff")
	assert(traits.has_buff(_TraitTypes.Type.ADRENALINE_RUSH), "High fear panic must trigger ADRENALINE_RUSH buff")

	# 6. Manual timed buff expiration
	mind.fear = 0.0
	traits.remove_debuff(_TraitTypes.Type.PANICKED)
	traits.remove_buff(_TraitTypes.Type.ADRENALINE_RUSH)
	traits.add_buff(_TraitTypes.Type.ADRENALINE_RUSH, 3)
	assert(traits.has_buff(_TraitTypes.Type.ADRENALINE_RUSH), "ADRENALINE_RUSH buff must be added")

	World._run_tick() # duration -> 2
	assert(traits.has_buff(_TraitTypes.Type.ADRENALINE_RUSH), "ADRENALINE_RUSH should still be active after 1 tick")
	World._run_tick() # duration -> 1
	assert(traits.has_buff(_TraitTypes.Type.ADRENALINE_RUSH), "ADRENALINE_RUSH should still be active after 2 ticks")
	World._run_tick() # duration -> 0 (expires)
	assert(not traits.has_buff(_TraitTypes.Type.ADRENALINE_RUSH), "ADRENALINE_RUSH buff must expire after its duration ends")

	print("  -> PASSED: Contextual threshold triggers and buff/debuff expiration verified.")

func _test_physical_trait_modifiers() -> void:
	print("\n[Test 4] Testing physical and metabolic trait modifiers...")
	var reg = World.get_registry()

	var p := Vector2i(70, 70)
	var fast_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "FleetGrazer", [_TraitTypes.Type.FLEET_FOOTED])
	var slow_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "SlothGrazer", [_TraitTypes.Type.SLOTHFUL])

	var fast_pos: _PositionComponent = reg.get_component(fast_eid, &"PositionComponent")
	var slow_pos: _PositionComponent = reg.get_component(slow_eid, &"PositionComponent")

	print("  Fleet-Footed move interval: %d | Slothful move interval: %d" % [
		fast_pos.base_move_interval, slow_pos.base_move_interval
	])
	assert(fast_pos.base_move_interval < slow_pos.base_move_interval, "Fleet-Footed creature must have shorter move interval than Slothful")

	# Test metabolic rate with Hardy
	var normal_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "PlainGrazer", [])
	var hardy_eid: int  = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, p, "HardyGrazer", [_TraitTypes.Type.HARDY])

	var n_traits: _TraitComponent = reg.get_component(normal_eid, &"TraitComponent")
	n_traits.remove_genetic_trait(_TraitTypes.Type.HARDY)

	var n_comp: _CreatureComponent = reg.get_component(normal_eid, &"CreatureComponent")
	var h_comp: _CreatureComponent = reg.get_component(hardy_eid, &"CreatureComponent")
	var n_mind: _MindComponent     = reg.get_component(normal_eid, &"MindComponent")
	var h_mind: _MindComponent     = reg.get_component(hardy_eid, &"MindComponent")
	var n_pos: _PositionComponent  = reg.get_component(normal_eid, &"PositionComponent")
	var h_pos: _PositionComponent  = reg.get_component(hardy_eid, &"PositionComponent")

	# Freeze movement and clear local grass so they don't graze during metabolism comparison
	n_pos.move_cooldown_ticks = 999
	h_pos.move_cooldown_ticks = 999
	var tile_eid: int = World.get_entity_at(p)
	var veg = reg.get_component(tile_eid, &"VegetationComponent")
	if veg != null:
		veg.growth_stage = 0
	var inv = reg.get_component(tile_eid, &"InventoryComponent")
	if inv != null:
		inv.items.clear()

	# Empty stomachs so hunger rises by metabolism_rate each tick
	n_comp.stomach_fill = 0.0
	h_comp.stomach_fill = 0.0
	n_mind.hunger = 0.0
	h_mind.hunger = 0.0

	for i in range(15):
		World._run_tick()

	print("  Normal Hunger after 15 ticks: %.3f | Hardy Hunger after 15 ticks: %.3f" % [n_mind.hunger, h_mind.hunger])
	assert(h_mind.hunger < n_mind.hunger, "Hardy creature must accumulate hunger slower due to reduced metabolic rate")

	print("  -> PASSED: Physical and metabolic trait modulations verified.")

func _write_log_artifact() -> void:
	var log_file = FileAccess.open("res://logs/test_creature_traits.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("PASSED: Data-Driven Creature TraitSystem Verified.\n" +
			"- Species genetic profiles & custom traits initialization verified.\n" +
			"- Utility AI behavior weighting (Timid vs. Bold, Gluttonous vs. Normal) verified.\n" +
			"- Buff & debuff threshold triggers (Starving, Well-Fed, Dehydrated, Hydrated, Panicked) verified.\n" +
			"- Buff duration ticking and expiration verified.\n" +
			"- Physical stat modulations (movement cooldown, metabolic rates) verified.\n")
		log_file.close()

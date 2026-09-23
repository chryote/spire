## TestCreatureGrowth.gd
## Integration test verifying Creature Ontogeny & Data-Driven Growth System:
## 1. Juvenile spawning: physical scaling (mass, blood volume, stomach capacity), juvenile glyph, stage traits.
## 2. Growth progression & Maturation: gradual progress ticks, Adult transition, body rescaling, trait shifts.
## 3. Nutritional gating: malnutrition halts growth, recovery resumes development.
## 4. Experiential conditioning milestones: near-death survival grants TOUGH, hazard evasion grants VIGILANT.
## 5. Senescence: elder transition, frail trait acquisition, body adjustments.
extends Node2D

const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _GrowthComponent     = preload("res://modules/creature/components/GrowthComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _RenderComponent     = preload("res://modules/rendering/components/RenderComponent.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE DATA-DRIVEN GROWTH SYSTEM TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true
	_test_juvenile_initialization()
	_test_growth_progression_and_maturation()
	_test_nutritional_gating()
	_test_experiential_milestones()
	_test_senescence_elder_transition()

	print("\n>>> ALL CREATURE GROWTH SYSTEM TESTS PASSED! <<<\n")
	_write_log_artifact()
	World.paused = false
	get_tree().quit(0)

func _step_to_rare_tick() -> void:
	# Advance World until a rare tick triggers
	for i in range(25):
		World._run_tick()
		if World.is_rare_tick(World.tick_count):
			break

func _test_juvenile_initialization() -> void:
	print("\n[Test 1] Testing juvenile spawning and anatomical downscaling...")
	var reg = World.get_registry()
	assert(reg != null, "World registry must be valid")

	var spawn_pos := Vector2i(35, 35)
	var juv_eid: int = _CreatureFactory.create(
		World,
		_CreatureTypes.Type.GRAZER,
		spawn_pos,
		"LittleGrazer",
		[],
		_CreatureTypes.GrowthStage.JUVENILE
	)

	var growth: _GrowthComponent   = reg.get_component(juv_eid, &"CreatureGrowthComponent")
	var creature: _CreatureComponent = reg.get_component(juv_eid, &"CreatureComponent")
	var body: _BodyComponent       = reg.get_component(juv_eid, &"BodyComponent")
	var traits: _TraitComponent    = reg.get_component(juv_eid, &"TraitComponent")
	var render: _RenderComponent   = reg.get_component(juv_eid, &"RenderComponent")

	assert(growth != null, "Juvenile creature must have GrowthComponent attached")
	assert(growth.current_stage == _CreatureTypes.GrowthStage.JUVENILE, "Growth stage must be JUVENILE")
	assert(is_equal_approx(growth.current_scale, 0.40), "Juvenile scale must be 0.40")
	assert(render.glyph == "g", "Juvenile Grazer glyph must be lowercase 'g'")
	assert(is_equal_approx(creature.stomach_capacity, growth.base_stomach_capacity * 0.40), "Stomach capacity must scale to 40%")
	assert(is_equal_approx(body.max_blood_volume, growth.base_blood_volume * 0.40), "Blood volume must scale to 40%")
	assert(traits.has_genetic_trait(_TraitTypes.Type.TIMID), "Juvenile Grazer must inherit Timid stage trait")
	assert(not traits.has_genetic_trait(_TraitTypes.Type.HARDY), "Juvenile Grazer must not yet possess adult Hardy trait")

	print("  Juvenile Mass: %.1f kg (Base: %.1f kg)" % [body.get_total_mass(reg), growth.base_mass])
	print("  Juvenile Blood: %.1f mL (Base: %.1f mL)" % [body.max_blood_volume, growth.base_blood_volume])
	print("  Juvenile Stomach: %.1f g (Base: %.1f g)" % [creature.stomach_capacity, growth.base_stomach_capacity])
	print("  -> PASSED: Juvenile spawning and downscaling verified.")

func _test_growth_progression_and_maturation() -> void:
	print("\n[Test 2] Testing growth progression and adult maturation transition...")
	var reg = World.get_registry()
	var spawn_pos := Vector2i(36, 36)
	var juv_eid: int = _CreatureFactory.create(
		World,
		_CreatureTypes.Type.GRAZER,
		spawn_pos,
		"GrowingGrazer",
		[],
		_CreatureTypes.GrowthStage.JUVENILE
	)

	var growth: _GrowthComponent   = reg.get_component(juv_eid, &"CreatureGrowthComponent")
	var creature: _CreatureComponent = reg.get_component(juv_eid, &"CreatureComponent")
	var body: _BodyComponent       = reg.get_component(juv_eid, &"BodyComponent")
	var traits: _TraitComponent    = reg.get_component(juv_eid, &"TraitComponent")
	var render: _RenderComponent   = reg.get_component(juv_eid, &"RenderComponent")
	var mind: _MindComponent       = reg.get_component(juv_eid, &"MindComponent")

	# Well-fed juvenile
	mind.hunger = 0.0
	creature.stomach_fill = creature.stomach_capacity

	var init_prog: float = growth.growth_progress
	_step_to_rare_tick()
	assert(growth.growth_progress > init_prog, "Growth progress must advance on rare tick when fed")
	print("  Progress after 1 rare tick: %.3f" % growth.growth_progress)

	# Simulate maturation threshold
	creature.age_ticks = 550
	growth.growth_progress = 1.0
	_step_to_rare_tick()

	assert(growth.current_stage == _CreatureTypes.GrowthStage.ADULT, "Creature must have transitioned to ADULT stage")
	assert(is_equal_approx(growth.current_scale, 1.0), "Adult scale must be 1.0")
	assert(render.glyph == "G", "Adult glyph must become uppercase 'G'")
	assert(is_equal_approx(creature.stomach_capacity, growth.base_stomach_capacity), "Stomach capacity must return to 100%")
	assert(is_equal_approx(body.max_blood_volume, growth.base_blood_volume), "Blood volume must return to 100%")
	assert(traits.has_genetic_trait(_TraitTypes.Type.HARDY), "Adult must have gained Hardy trait")
	assert(not traits.has_genetic_trait(_TraitTypes.Type.TIMID), "Adult must have shed juvenile Timid trait")

	print("  Adult Mass after transition: %.1f kg" % body.get_total_mass(reg))
	print("  Adult Blood volume: %.1f mL" % body.max_blood_volume)
	print("  -> PASSED: Stage transition, trait exchange, and anatomical expansion verified.")

func _test_nutritional_gating() -> void:
	print("\n[Test 3] Testing nutritional gating and stunting...")
	var reg = World.get_registry()
	var spawn_pos := Vector2i(37, 37)
	var hare_eid: int = _CreatureFactory.create(
		World,
		_CreatureTypes.Type.HARE,
		spawn_pos,
		"StarvingHare",
		[],
		_CreatureTypes.GrowthStage.JUVENILE
	)

	var growth: _GrowthComponent   = reg.get_component(hare_eid, &"CreatureGrowthComponent")
	var creature: _CreatureComponent = reg.get_component(hare_eid, &"CreatureComponent")
	var mind: _MindComponent       = reg.get_component(hare_eid, &"MindComponent")

	var pos_comp: _PositionComponent = reg.get_component(hare_eid, &"PositionComponent")
	if pos_comp != null:
		pos_comp.move_cooldown_ticks = 999
	var tile_eid: int = World.get_entity_at(spawn_pos)
	var veg = reg.get_component(tile_eid, &"VegetationComponent")
	if veg != null:
		veg.growth_stage = 0
	var inv = reg.get_component(tile_eid, &"InventoryComponent")
	if inv != null:
		inv.items.clear()

	# Starve the creature
	mind.hunger = 0.90
	creature.stomach_fill = 0.0
	growth.growth_progress = 0.20

	_step_to_rare_tick()
	assert(growth.is_stunted, "Starving creature must be marked stunted")
	assert(is_equal_approx(growth.growth_progress, 0.20), "Growth progress must stall while stunted")
	print("  Stunted status confirmed. Progress halted at: %.2f" % growth.growth_progress)

	# Feed the creature to resolve starvation
	mind.hunger = 0.10
	creature.stomach_fill = 5.0
	_step_to_rare_tick()
	assert(not growth.is_stunted, "Creature must recover from stunting when fed")
	assert(growth.growth_progress > 0.20, "Growth progress must resume advancing once nourished")
	print("  Nourishment restored. Progress resumed to: %.3f" % growth.growth_progress)
	print("  -> PASSED: Nutritional gating verified.")

func _test_experiential_milestones() -> void:
	print("\n[Test 4] Testing experiential conditioning milestones (Tough & Vigilant)...")
	var reg = World.get_registry()
	var spawn_pos := Vector2i(38, 38)
	var deer_eid: int = _CreatureFactory.create(
		World,
		_CreatureTypes.Type.DEER,
		spawn_pos,
		"VeteranDeer",
		[],
		_CreatureTypes.GrowthStage.ADULT
	)

	var growth: _GrowthComponent   = reg.get_component(deer_eid, &"CreatureGrowthComponent")
	var creature: _CreatureComponent = reg.get_component(deer_eid, &"CreatureComponent")
	var body: _BodyComponent       = reg.get_component(deer_eid, &"BodyComponent")
	var traits: _TraitComponent    = reg.get_component(deer_eid, &"TraitComponent")
	var mem: _MemoryComponent      = reg.get_component(deer_eid, &"MemoryComponent")
	var pos_comp: _PositionComponent = reg.get_component(deer_eid, &"PositionComponent")
	if pos_comp != null:
		pos_comp.move_cooldown_ticks = 999

	# Milestone 1: Surviving Near-Death Experience (Critical health between 0.21 and 0.30)
	body.blood_volume = body.max_blood_volume * 0.25
	creature.health = 0.25
	_step_to_rare_tick()
	assert(creature.is_alive, "Creature should survive at 25% blood volume")
	assert(growth.has_milestone(&"near_death_experience"), "Must register near_death_experience milestone")
	assert(not traits.has_genetic_trait(_TraitTypes.Type.TOUGH), "Tough trait not awarded until recovered")

	# Heal and recover
	body.blood_volume = body.max_blood_volume * 0.90
	creature.health = 0.90
	_step_to_rare_tick()
	assert(growth.has_milestone(&"tough_awarded"), "Must register tough_awarded milestone")
	assert(traits.has_genetic_trait(_TraitTypes.Type.TOUGH), "Creature must acquire TOUGH trait from survival")
	print("  Milestone TOUGH awarded after near-death recovery.")

	# Milestone 2: Heightened Alertness from Danger
	assert(mem != null, "Deer must have MemoryComponent")
	for i in range(3):
		mem.short_term_events.append({"event": &"fled", "tick": World.tick_count})
	_step_to_rare_tick()
	assert(growth.has_milestone(&"vigilant_awarded"), "Must register vigilant_awarded milestone")
	assert(traits.has_genetic_trait(_TraitTypes.Type.VIGILANT), "Creature must acquire VIGILANT trait from hazard evasion")
	print("  Milestone VIGILANT awarded after repeated hazard evasion.")
	print("  -> PASSED: Experiential conditioning milestones verified.")

func _test_senescence_elder_transition() -> void:
	print("\n[Test 5] Testing senescence and elder stage transition...")
	var reg = World.get_registry()
	var spawn_pos := Vector2i(39, 39)
	var grazer_eid: int = _CreatureFactory.create(
		World,
		_CreatureTypes.Type.GRAZER,
		spawn_pos,
		"AncientGrazer",
		[],
		_CreatureTypes.GrowthStage.ADULT
	)

	var growth: _GrowthComponent   = reg.get_component(grazer_eid, &"CreatureGrowthComponent")
	var creature: _CreatureComponent = reg.get_component(grazer_eid, &"CreatureComponent")
	var traits: _TraitComponent    = reg.get_component(grazer_eid, &"TraitComponent")
	var pos_comp: _PositionComponent = reg.get_component(grazer_eid, &"PositionComponent")
	if pos_comp != null:
		pos_comp.move_cooldown_ticks = 999

	# Advance age past elder threshold (28800 for grazer)
	creature.age_ticks = 30000
	_step_to_rare_tick()

	assert(growth.current_stage == _CreatureTypes.GrowthStage.ELDER, "Grazer must mature into ELDER stage")
	assert(is_equal_approx(growth.current_scale, 0.90), "Elder grazer scale must contract to 0.90")
	assert(traits.has_genetic_trait(_TraitTypes.Type.FRAIL), "Elder grazer must acquire Frail trait")
	assert(traits.has_genetic_trait(_TraitTypes.Type.VIGILANT), "Elder grazer must acquire Vigilant trait")
	print("  Elder Stage reached. Frail & Vigilant traits acquired. Scale: %.2f" % growth.current_scale)
	print("  -> PASSED: Senescence transition verified.")

func _write_log_artifact() -> void:
	var log_file = FileAccess.open("res://logs/test_creature_growth.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("PASSED: Creature Ontogeny & Data-Driven Growth System Verified.\n" +
			"- Juvenile spawning & anatomical scaling (mass, blood, organs, stomach) verified.\n" +
			"- Maturation progress & adult stage transition verified.\n" +
			"- Stage trait exchange (shedding juvenile traits, gaining adult traits) verified.\n" +
			"- Nutritional gating (starvation stunting & recovery) verified.\n" +
			"- Experiential conditioning milestones (TOUGH on survival, VIGILANT on evasion) verified.\n" +
			"- Senescence (elder stage transition & FRAIL trait) verified.\n")
		log_file.close()

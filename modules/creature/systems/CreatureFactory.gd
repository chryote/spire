## CreatureFactory.gd
## Stateless factory utility for instantiating complete data-driven creatures.
## Assembles the physical anatomy (composite limbs, organs, blood) as discrete
## item/matter entities and initializes the creature's cognitive mind and utility AI.
class_name CreatureFactory
extends RefCounted

const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _GrowthComponent     = preload("res://modules/creature/components/GrowthComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _RenderComponent     = preload("res://modules/rendering/components/RenderComponent.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")
const _MatterComponent     = preload("res://modules/matter/components/MatterComponent.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")
const _MatingComponent     = preload("res://modules/creature/components/MatingComponent.gd")

## Instantiates a creature entity and its physical anatomical sub-entities.
static func create(
	world: Node,
	species_type: int,
	spawn_pos: Vector2i,
	name_override: String = "",
	initial_traits: Array[int] = [],
	start_stage: int = -1,
	gender_override: int = -1
) -> int:
	if world == null:
		return -1

	var spec_data: Dictionary = _CreatureTypes.get_data(species_type)
	var creature_eid: int = world.create_entity()

	# 1. Creature Core Component
	var creature_comp := _CreatureComponent.new()
	creature_comp.species_type = species_type
	creature_comp.diet = spec_data.get("diet", 1)
	creature_comp.gender = gender_override if gender_override >= 0 else (randi() % 2)
	creature_comp.creature_name = name_override if name_override != "" else spec_data.get("display_name", "Creature")
	creature_comp.stomach_capacity = spec_data.get("stomach_capacity", 50.0)
	creature_comp.stomach_fill = creature_comp.stomach_capacity * 0.4
	world.add_component(creature_eid, creature_comp)

	# 2. Position Component
	var pos_comp := _PositionComponent.new()
	pos_comp.position = spawn_pos
	pos_comp.base_move_interval = spec_data.get("move_cooldown", 2)
	pos_comp.move_cooldown_ticks = 0
	world.add_component(creature_eid, pos_comp)

	# 3. Physical Body & Anatomy Component (Limbs, Organs, Blood)
	var body_comp := _BodyComponent.new()
	body_comp.blood_volume = spec_data.get("blood_volume", 2.5)
	body_comp.max_blood_volume = body_comp.blood_volume

	var anatomy: Dictionary = spec_data.get("anatomy", {})
	var limbs_cfg: Dictionary = anatomy.get("limbs", {})
	for limb_name: String in limbs_cfg:
		var cfg: Dictionary = limbs_cfg[limb_name]
		var limb_eid: int = _ItemFactory.create_composite(world, _ItemTypes.Type.LIMB, {
			"flesh": cfg.get("flesh", 12),
			"bone":  cfg.get("bone",  21),
		})
		var limb_item = world.get_component(limb_eid, &"ItemComponent")
		if limb_item != null:
			limb_item.container_id = creature_eid
			limb_item.display_name = "%s's %s" % [creature_comp.creature_name, limb_name.capitalize()]
			var target_vol: float = cfg.get("volume", 0.0) as float
			if target_vol > 0.0 and limb_item.total_volume > 0.0:
				var scale_factor: float = target_vol / limb_item.total_volume
				limb_item.total_volume = target_vol
				limb_item.total_mass *= scale_factor
				for p_name in limb_item.parts:
					var part = limb_item.parts[p_name]
					if part.has("volume"):
						part["volume"] *= scale_factor
					if part.has("mass"):
						part["mass"] *= scale_factor
		body_comp.limbs[limb_name] = limb_eid

	# 3a. Genital Limb (Male or Female based on gender)
	var genitals_cfg: Dictionary = anatomy.get("genitals", {})
	var gen_cfg: Dictionary = genitals_cfg.get(creature_comp.gender, {})
	var gen_name: String = gen_cfg.get("name", "male_genital" if creature_comp.gender == _CreatureTypes.Gender.MALE else "female_genital")
	var gen_eid: int = _ItemFactory.create_composite(world, _ItemTypes.Type.LIMB, {
		"flesh": gen_cfg.get("flesh", 12),
		"bone":  gen_cfg.get("bone",  21),
	})
	var gen_item = world.get_component(gen_eid, &"ItemComponent")
	if gen_item != null:
		gen_item.container_id = creature_eid
		gen_item.display_name = "%s's %s" % [creature_comp.creature_name, gen_name.capitalize()]
		var target_vol: float = gen_cfg.get("volume", 0.0003) as float
		if target_vol > 0.0 and gen_item.total_volume > 0.0:
			var scale_factor: float = target_vol / gen_item.total_volume
			gen_item.total_volume = target_vol
			gen_item.total_mass *= scale_factor
			for p_name in gen_item.parts:
				var part = gen_item.parts[p_name]
				if part.has("volume"):
					part["volume"] *= scale_factor
				if part.has("mass"):
					part["mass"] *= scale_factor
	body_comp.limbs[gen_name] = gen_eid

	var organs_cfg: Dictionary = anatomy.get("organs", {})
	for organ_name: String in organs_cfg:
		var cfg: Dictionary = organs_cfg[organ_name]
		var organ_eid: int = _ItemFactory.create(world, _ItemTypes.Type.ORGAN, cfg.get("matter", 12))
		var organ_item = world.get_component(organ_eid, &"ItemComponent")
		if organ_item != null:
			organ_item.container_id = creature_eid
			organ_item.display_name = "%s's %s" % [creature_comp.creature_name, organ_name.capitalize()]
			var target_vol: float = cfg.get("volume", 0.0) as float
			if target_vol > 0.0 and organ_item.total_volume > 0.0:
				var scale_factor: float = target_vol / organ_item.total_volume
				organ_item.total_volume = target_vol
				organ_item.total_mass *= scale_factor
				for p_name in organ_item.parts:
					var part = organ_item.parts[p_name]
					if part.has("volume"):
						part["volume"] *= scale_factor
					if part.has("mass"):
						part["mass"] *= scale_factor
		body_comp.organs[organ_name] = organ_eid

	world.add_component(creature_eid, body_comp)

	# 3b. Physical Matter Component for Root Creature Entity (living organic flesh)
	var creature_matter := _MatterComponent.new()
	_MaterialTypes.apply_to(creature_matter, _MaterialTypes.Type.RAW_MEAT)
	creature_matter.temperature_c = body_comp.body_temperature_c
	creature_matter.moisture = 0.70
	world.add_component(creature_eid, creature_matter)

	# 4. Cognitive Mind Component
	var mind_comp := _MindComponent.new()
	world.add_component(creature_eid, mind_comp)

	# 5. Spatial Memory Component
	var mem_comp := _MemoryComponent.new()
	world.add_component(creature_eid, mem_comp)

	# 6. Action Plan Component
	var plan_comp := _ActionPlanComponent.new()
	world.add_component(creature_eid, plan_comp)

	# 7. Render Component (ASCII glyph & color)
	var render_comp := _RenderComponent.new()
	render_comp.glyph = spec_data.get("glyph", "c")
	render_comp.fg_color = spec_data.get("fg_color", Color.WHITE)
	render_comp.bg_color = spec_data.get("bg_color", Color.BLACK)
	render_comp.z_layer = 10  # Drawn on top of terrain
	world.add_component(creature_eid, render_comp)

	# 8. Trait & Genetic Profile Component
	var trait_comp := _TraitComponent.new()
	var innate: Array = spec_data.get("innate_traits", [])
	for t in innate:
		trait_comp.add_genetic_trait(t)

	if not initial_traits.is_empty():
		for t in initial_traits:
			trait_comp.add_genetic_trait(t)
	else:
		var pool: Array = spec_data.get("trait_pool", [])
		if not pool.is_empty():
			if randf() < 0.60:
				var rolled = pool[randi() % pool.size()]
				trait_comp.add_genetic_trait(rolled)

	# Apply initial trait stat modifiers
	if trait_comp.get_stat_multiplier(&"stomach_capacity_mult") != 1.0:
		creature_comp.stomach_capacity *= trait_comp.get_stat_multiplier(&"stomach_capacity_mult")
		creature_comp.stomach_fill = creature_comp.stomach_capacity * 0.4
	if trait_comp.get_stat_offset(&"move_cooldown") != 0:
		pos_comp.base_move_interval = maxi(1, pos_comp.base_move_interval + trait_comp.get_stat_offset(&"move_cooldown"))

	world.add_component(creature_eid, trait_comp)

	# 9. Growth & Maturation Component
	var growth_comp := _GrowthComponent.new()
	growth_comp.current_stage = start_stage if start_stage >= 0 else _CreatureTypes.GrowthStage.ADULT
	growth_comp.base_mass = spec_data.get("base_mass", 20.0)
	growth_comp.base_blood_volume = spec_data.get("blood_volume", 2.5)
	growth_comp.base_stomach_capacity = creature_comp.stomach_capacity

	var spec_growth: Dictionary = _CreatureTypes.get_growth_profile(species_type)
	var stages_cfg: Dictionary = spec_growth.get("stages", {})
	var stage_cfg: Dictionary = stages_cfg.get(growth_comp.current_stage, {})
	var body_scale: float = stage_cfg.get("body_scale", 1.0)
	growth_comp.current_scale = body_scale

	if growth_comp.current_stage != _CreatureTypes.GrowthStage.ADULT:
		body_comp.rescale_anatomy(world.get_registry(), body_scale, 1.0)
		creature_comp.stomach_capacity *= body_scale
		creature_comp.stomach_fill = creature_comp.stomach_capacity * 0.4
		var stage_glyph: String = stage_cfg.get("glyph", "")
		if stage_glyph != "":
			render_comp.glyph = stage_glyph

		var lost: Array = stage_cfg.get("traits_lost", [])
		for tid in lost:
			trait_comp.remove_genetic_trait(tid)
		var gained: Array = stage_cfg.get("traits_gained", [])
		for tid in gained:
			trait_comp.add_genetic_trait(tid)

	world.add_component(creature_eid, growth_comp)

	# 10. Reproduction & Mating Component
	var mating_comp := _MatingComponent.new()
	mating_comp.gender = creature_comp.gender

	var repro_cfg: Dictionary = _CreatureTypes.get_reproduction_profile(species_type)
	mating_comp.litter_size_min = repro_cfg.get("litter_size_min", 1)
	mating_comp.litter_size_max = repro_cfg.get("litter_size_max", 2)
	mating_comp.gestation_duration = repro_cfg.get("gestation_duration", 600)

	if creature_comp.gender == _CreatureTypes.Gender.FEMALE:
		var base_spawn_rate: float = repro_cfg.get("female_spawn_rate", 1.0) as float
		if trait_comp.has_genetic_trait(_TraitTypes.Type.HARDY):
			base_spawn_rate *= 1.15
		if trait_comp.has_genetic_trait(_TraitTypes.Type.FRAIL):
			base_spawn_rate *= 0.75
		mating_comp.spawn_rate = base_spawn_rate
		creature_comp.spawn_rate = base_spawn_rate
	else:
		mating_comp.spawn_rate = 0.0
		creature_comp.spawn_rate = 0.0

	# Trait matching preferences: select 1-2 traits preferred in a partner
	var p_pool: Array = spec_data.get("trait_pool", []).duplicate()
	p_pool.append_array(spec_data.get("innate_traits", []))
	if not p_pool.is_empty():
		p_pool.shuffle()
		mating_comp.preferred_traits.append(p_pool[0])
		if p_pool.size() > 1 and randf() < 0.5:
			mating_comp.preferred_traits.append(p_pool[1])

	world.add_component(creature_eid, mating_comp)

	return creature_eid


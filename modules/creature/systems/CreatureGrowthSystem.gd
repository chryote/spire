## CreatureGrowthSystem.gd
## Priority 223 -- runs right before TraitSystem (224).
##
## Manages creature lifecycle ontogeny and experiential trait acquisition:
## 1. Executes exclusively on rare ticks (every 20 ticks) for zero per-tick cost.
## 2. Advances growth progress based on nourishment (stalls if starving).
## 3. Handles stage transitions (Juvenile -> Adult -> Elder):
##    - Proportionally rescales physical anatomy (mass, blood, organs, stomach).
##    - Transitions stage-specific genetic traits (sheds vulnerability, gains maturity traits).
##    - Updates rendering glyphs (e.g. "g" -> "G").
## 4. Evaluates experiential conditioning milestones (e.g. surviving near-death grants Tough).
class_name CreatureGrowthSystem
extends "res://core/SystemBase.gd"

const _CreatureComponent = preload("res://modules/creature/components/CreatureComponent.gd")
const _BodyComponent     = preload("res://modules/creature/components/body/BodyComponent.gd")
const _GrowthComponent   = preload("res://modules/creature/components/GrowthComponent.gd")
const _TraitComponent    = preload("res://modules/creature/components/TraitComponent.gd")
const _MindComponent     = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent   = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _RenderComponent   = preload("res://modules/rendering/components/RenderComponent.gd")
const _CreatureTypes     = preload("res://modules/creature/data/CreatureTypes.gd")
const _TraitTypes        = preload("res://modules/creature/data/TraitTypes.gd")

func initialize() -> void:
	print("[CreatureGrowthSystem] Initialized. Priority 223.")

func tick(tick_number: int) -> void:
	if world == null:
		return

	# Zero per-tick cost: only process on rare tick intervals (~2s at 10 TPS)
	if not world.is_rare_tick(tick_number):
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var growth_store: Dictionary   = reg.get_store(&"CreatureGrowthComponent")
	var body_store: Dictionary     = reg.get_store(&"BodyComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")
	var render_store: Dictionary   = reg.get_store(&"RenderComponent")
	var mem_store: Dictionary      = reg.get_store(&"MemoryComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var growth: _GrowthComponent = growth_store.get(eid, null)
		if growth == null:
			continue

		var body: _BodyComponent     = body_store.get(eid, null)
		var traits: _TraitComponent  = trait_store.get(eid, null)
		var render: _RenderComponent = render_store.get(eid, null)
		var mem: _MemoryComponent    = mem_store.get(eid, null)

		var spec_growth: Dictionary = _CreatureTypes.get_growth_profile(creature.species_type)
		if spec_growth.is_empty():
			continue

		# -------------------------------------------------------------------
		# 1. Maturation & Nutritional Gating
		# -------------------------------------------------------------------
		var is_starving: bool = traits != null and traits.has_debuff(_TraitTypes.Type.STARVING)
		if is_starving or creature.stomach_fill <= 0.001:
			growth.is_stunted = true
		else:
			growth.is_stunted = false
			var rate: float = spec_growth.get("growth_rate_per_rare_tick", 0.015)
			if traits != null and traits.has_buff(_TraitTypes.Type.WELL_FED):
				rate *= 1.35
			growth.growth_progress = minf(1.0, growth.growth_progress + rate)

		# -------------------------------------------------------------------
		# 2. Lifecycle Stage Transitions
		# -------------------------------------------------------------------
		var stages: Dictionary = spec_growth.get("stages", {})

		if growth.current_stage == _CreatureTypes.GrowthStage.JUVENILE:
			var adult_cfg: Dictionary = stages.get(_CreatureTypes.GrowthStage.ADULT, {})
			var min_age: int = adult_cfg.get("min_age_ticks", 2400)
			if (creature.age_ticks >= min_age or growth.growth_progress >= 1.0) and not growth.is_stunted:
				_transition_stage(eid, reg, creature, growth, body, traits, render, _CreatureTypes.GrowthStage.ADULT, adult_cfg)

		elif growth.current_stage == _CreatureTypes.GrowthStage.ADULT:
			var elder_cfg: Dictionary = stages.get(_CreatureTypes.GrowthStage.ELDER, {})
			var min_elder_age: int = elder_cfg.get("min_age_ticks", 28800)
			if creature.age_ticks >= min_elder_age:
				_transition_stage(eid, reg, creature, growth, body, traits, render, _CreatureTypes.GrowthStage.ELDER, elder_cfg)

		# -------------------------------------------------------------------
		# 3. Experiential Conditioning Milestones
		# -------------------------------------------------------------------
		_evaluate_experiential_milestones(growth, creature, traits, mem)

func _transition_stage(
	eid: int,
	reg,
	creature: _CreatureComponent,
	growth: _GrowthComponent,
	body: _BodyComponent,
	traits: _TraitComponent,
	render: _RenderComponent,
	new_stage: int,
	stage_cfg: Dictionary
) -> void:
	var old_stage: int = growth.current_stage
	growth.current_stage = new_stage
	growth.growth_progress = 0.0

	var new_scale: float = stage_cfg.get("body_scale", 1.0)
	var old_scale: float = growth.current_scale

	# Rescale physical anatomy and vitals
	if body != null:
		body.rescale_anatomy(reg, new_scale, old_scale)

	creature.stomach_capacity = maxf(5.0, growth.base_stomach_capacity * new_scale)
	growth.current_scale = new_scale

	# Update visual representation
	var new_glyph: String = stage_cfg.get("glyph", "")
	if new_glyph != "" and render != null:
		render.glyph = new_glyph

	# Stage-specific trait shifts
	if traits != null:
		var lost: Array = stage_cfg.get("traits_lost", [])
		for tid in lost:
			traits.remove_genetic_trait(tid)

		var gained: Array = stage_cfg.get("traits_gained", [])
		for tid in gained:
			traits.add_genetic_trait(tid)

	world.mark_render_dirty()
	print("[CreatureGrowth] %s (eid=%d) matured from %s to %s (Scale: %.2f, Mass: %.1f kg)!" % [
		creature.creature_name,
		eid,
		_CreatureTypes.get_stage_name(old_stage),
		stage_cfg.get("name", _CreatureTypes.get_stage_name(new_stage)),
		new_scale,
		body.get_total_mass(reg) if body != null else 20.0
	])

func _evaluate_experiential_milestones(
	growth: _GrowthComponent,
	creature: _CreatureComponent,
	traits: _TraitComponent,
	mem: _MemoryComponent
) -> void:
	if traits == null:
		return

	# Milestone: Survived near-death experience -> Acquired Tough trait
	if creature.health <= 0.30 and not growth.has_milestone(&"near_death_experience"):
		growth.record_milestone(&"near_death_experience")

	if growth.has_milestone(&"near_death_experience") and creature.health >= 0.70:
		if not growth.has_milestone(&"tough_awarded"):
			growth.record_milestone(&"tough_awarded")
			traits.add_genetic_trait(_TraitTypes.Type.TOUGH)
			print("[CreatureGrowth] %s battle-hardened from near-death experience; acquired TOUGH trait!" % creature.creature_name)

	# Milestone: Evaded repeated dangers -> Acquired Vigilant trait
	if mem != null and not growth.has_milestone(&"vigilant_awarded"):
		var flee_count: int = 0
		for evt in mem.short_term_events:
			if evt.get("event") == &"fled" or evt.get("event") == &"panicked":
				flee_count += 1
		if flee_count >= 3 or (traits.has_buff(_TraitTypes.Type.ADRENALINE_RUSH) and traits.has_genetic_trait(_TraitTypes.Type.TIMID)):
			growth.record_milestone(&"vigilant_awarded")
			traits.add_genetic_trait(_TraitTypes.Type.VIGILANT)
			print("[CreatureGrowth] %s heightened alertness through survival; acquired VIGILANT trait!" % creature.creature_name)

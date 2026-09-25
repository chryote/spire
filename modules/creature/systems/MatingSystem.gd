## MatingSystem.gd
## Priority 226 -- runs between CreatureBodySystem (225) and CreatureAISystem (230).
##
## Manages creature reproduction lifecycle, mating drive dynamics, partner preference
## via trait matching, genital limb integrity checks, gestation, and birth spawning.
class_name MatingSystem
extends "res://core/SystemBase.gd"

const _CreatureComponent = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent     = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent     = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent   = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _TraitComponent    = preload("res://modules/creature/components/TraitComponent.gd")
const _MatingComponent   = preload("res://modules/creature/components/MatingComponent.gd")
const _SocialComponent   = preload("res://modules/creature/components/SocialComponent.gd")
const _GrowthComponent   = preload("res://modules/creature/components/GrowthComponent.gd")
const _CreatureTypes     = preload("res://modules/creature/data/CreatureTypes.gd")
const _TraitTypes        = preload("res://modules/creature/data/TraitTypes.gd")
const _MindEmbeddings    = preload("res://modules/creature/data/MindEmbeddings.gd")
const _TileAffordance    = preload("res://modules/signal/data/TileAffordance.gd")
const _CreatureFactory   = preload("res://modules/creature/systems/CreatureFactory.gd")

func initialize() -> void:
	print("[MatingSystem] Initialized. Priority 226.")

func tick(tick_number: int) -> void:
	if world == null:
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var mating_store: Dictionary   = reg.get_store(&"MatingComponent")
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")
	var growth_store: Dictionary   = reg.get_store(&"CreatureGrowthComponent")
	var pos_store: Dictionary      = reg.get_store(&"PositionComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var mating_comp: _MatingComponent = mating_store.get(eid, null)
		var mind: _MindComponent         = mind_store.get(eid, null)
		var growth: _GrowthComponent     = growth_store.get(eid, null)
		var pos_comp: _PositionComponent = pos_store.get(eid, null)
		var traits: _TraitComponent      = trait_store.get(eid, null)

		if mating_comp == null:
			continue

		# -------------------------------------------------------------------
		# 1. Cooldown Ticking
		# -------------------------------------------------------------------
		if mating_comp.mating_cooldown_ticks > 0:
			mating_comp.mating_cooldown_ticks -= 1

		# -------------------------------------------------------------------
		# 2. Mating Drive Accumulation
		# -------------------------------------------------------------------
		# Adults accumulate mating drive over time when nourished and not pregnant/cooldown
		var is_adult: bool = (growth == null or growth.current_stage >= _CreatureTypes.GrowthStage.ADULT)
		if is_adult and mind != null:
			if mating_comp.is_ready_to_mate():
				var inc: float = 0.002
				# Well-nourished creatures build libido faster
				if creature.stomach_fill > creature.stomach_capacity * 0.35:
					inc += 0.001
				if traits != null and traits.has_buff(_TraitTypes.Type.WELL_FED):
					inc += 0.001
				# Slothful slightly slower, Bold slightly faster
				if traits != null and traits.has_genetic_trait(_TraitTypes.Type.BOLD):
					inc += 0.0005
				mind.mating = clampf(mind.mating + inc, 0.0, 1.0)
			elif mating_comp.is_female() and mating_comp.is_pregnant:
				# Suppress mating drive during pregnancy
				mind.mating = minf(mind.mating, 0.05)

		# -------------------------------------------------------------------
		# 3. Gestation & Birth Spawning (Female only)
		# -------------------------------------------------------------------
		if mating_comp.is_female() and mating_comp.is_pregnant:
			mating_comp.gestation_ticks += 1
			if mating_comp.gestation_ticks >= mating_comp.gestation_duration:
				var birth_pos: Vector2i = pos_comp.position if pos_comp != null else Vector2i(64, 64)
				_give_birth(eid, creature, mating_comp, traits, birth_pos, tick_number)

# ---------------------------------------------------------------------------
# Compatibility & Trait Matching Preference Evaluation
# ---------------------------------------------------------------------------

## Calculates trait matching preference score [0.0, 1.0] of evaluator towards candidate.
func calculate_trait_matching_score(evaluator_eid: int, candidate_eid: int) -> float:
	if evaluator_eid == candidate_eid or world == null:
		return 0.0

	var reg = world.get_registry()
	if reg == null:
		return 0.0

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var mating_store: Dictionary   = reg.get_store(&"MatingComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")
	var body_store: Dictionary     = reg.get_store(&"BodyComponent")

	var cand_creature: _CreatureComponent = creature_store.get(candidate_eid, null)
	var eval_mating: _MatingComponent     = mating_store.get(evaluator_eid, null)
	var cand_mating: _MatingComponent     = mating_store.get(candidate_eid, null)
	var eval_traits: _TraitComponent     = trait_store.get(evaluator_eid, null)
	var cand_traits: _TraitComponent     = trait_store.get(candidate_eid, null)
	var cand_body: _BodyComponent         = body_store.get(candidate_eid, null)

	if cand_creature == null or eval_mating == null or cand_mating == null:
		return 0.0

	# 1. Genital limb integrity check: damaged or severed genital yields zero preference
	if cand_body != null and not cand_body.has_intact_genital(reg):
		return 0.0

	# 2. Base baseline preference
	var score: float = 0.50

	var cand_active_traits: Array[int] = cand_traits.get_all_active_traits() if cand_traits != null else []
	var cand_gen_traits: Array[int] = cand_traits.genetic_traits if cand_traits != null else []
	var eval_gen_traits: Array[int] = eval_traits.genetic_traits if eval_traits != null else []

	# 3. Preference matching: desired traits in candidate
	for desired_trait: int in eval_mating.preferred_traits:
		if cand_active_traits.has(desired_trait):
			score += 0.25
		else:
			score -= 0.05

	# 4. Homophily & complementary trait matching
	for gt: int in eval_gen_traits:
		if cand_gen_traits.has(gt):
			# Mutual shared strengths: Hardy, Fleet-Footed, Bold
			score += 0.15

	# 5. Attractive physical buffs
	if cand_traits != null:
		if cand_traits.has_buff(_TraitTypes.Type.WELL_FED):
			score += 0.10
		if cand_traits.has_buff(_TraitTypes.Type.RESTED):
			score += 0.10

		# 6. Unattractive debuffs & vulnerabilities
		if cand_traits.has_debuff(_TraitTypes.Type.STARVING):
			score -= 0.30
		if cand_traits.has_debuff(_TraitTypes.Type.DEHYDRATED):
			score -= 0.25
		if cand_traits.has_debuff(_TraitTypes.Type.EXHAUSTED):
			score -= 0.20
		if cand_traits.has_debuff(_TraitTypes.Type.PANICKED):
			score -= 0.30
		if cand_traits.has_genetic_trait(_TraitTypes.Type.FRAIL):
			score -= 0.20

	# 7. General health factor
	score *= (0.6 + cand_creature.health * 0.4)

	# 8. Pair-Bond Fidelity & Monogamy Preference
	var social_store: Dictionary = reg.get_store(&"SocialComponent")
	var eval_social: _SocialComponent = social_store.get(evaluator_eid, null)
	if eval_social != null:
		if candidate_eid == eval_social.bonded_partner_eid:
			# Loyalty bonus to bonded partner scaled by monogamy tendency
			score += 0.35 * eval_social.monogamy_tendency
		elif eval_social.has_bonded_partner() and eval_social.is_partner_alive(reg):
			# Infidelity aversion penalty scaled by monogamy tendency
			score -= 0.80 * eval_social.monogamy_tendency
			if eval_social.monogamy_tendency >= 0.70:
				score = 0.0

	return clampf(score, 0.0, 1.0)

## Validates whether two creatures can physically and biologically mate.
func can_mate(eid_a: int, eid_b: int) -> bool:
	if eid_a == eid_b or world == null:
		return false

	var reg = world.get_registry()
	if reg == null:
		return false

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var mating_store: Dictionary   = reg.get_store(&"MatingComponent")
	var body_store: Dictionary     = reg.get_store(&"BodyComponent")
	var growth_store: Dictionary   = reg.get_store(&"CreatureGrowthComponent")

	var ca: _CreatureComponent = creature_store.get(eid_a, null)
	var cb: _CreatureComponent = creature_store.get(eid_b, null)
	var ma: _MatingComponent   = mating_store.get(eid_a, null)
	var mb: _MatingComponent   = mating_store.get(eid_b, null)
	var ba: _BodyComponent     = body_store.get(eid_a, null)
	var bb: _BodyComponent     = body_store.get(eid_b, null)
	var ga: _GrowthComponent   = growth_store.get(eid_a, null)
	var gb: _GrowthComponent   = growth_store.get(eid_b, null)

	if ca == null or cb == null or ma == null or mb == null:
		return false

	# Must be alive and same species
	if not ca.is_alive or not cb.is_alive:
		return false
	if ca.species_type != cb.species_type:
		return false

	# Opposite sexes required
	if ma.gender == mb.gender:
		return false

	# Must be Adult or Elder (not Juvenile)
	if ga != null and ga.current_stage < _CreatureTypes.GrowthStage.ADULT:
		return false
	if gb != null and gb.current_stage < _CreatureTypes.GrowthStage.ADULT:
		return false

	# Both must have functional, intact genital limbs
	if ba != null and not ba.has_intact_genital(reg):
		return false
	if bb != null and not bb.has_intact_genital(reg):
		return false

	# Must be ready (not on cooldown, female not pregnant)
	if not ma.is_ready_to_mate() or not mb.is_ready_to_mate():
		return false

	# Pair-Bond Fidelity / Monogamy checks: reject extra-pair mating if faithful to living partner
	if _is_bonded_and_faithful_to_other(eid_a, eid_b, reg):
		return false
	if _is_bonded_and_faithful_to_other(eid_b, eid_a, reg):
		return false

	return true

## Checks whether a creature has an alive bonded partner and is socially/biologically
## faithful enough to reject mating with an outside candidate.
func _is_bonded_and_faithful_to_other(eid: int, candidate_eid: int, reg) -> bool:
	if reg == null:
		return false
	var social_store: Dictionary = reg.get_store(&"SocialComponent")
	var social: _SocialComponent = social_store.get(eid, null)
	if social == null or not social.has_bonded_partner():
		return false

	# Mating with own bonded partner is always allowed
	if social.bonded_partner_eid == candidate_eid:
		return false

	# If bonded partner is deceased, creature is free to mate
	if not social.is_partner_alive(reg):
		return false

	# 1. High fidelity (monogamy_tendency >= 0.70): strict lifetime fidelity, blocks outside suitor
	if social.monogamy_tendency >= 0.70:
		return true

	# 2. Moderate fidelity (monogamy_tendency >= 0.35): faithful if partner is alive and nearby within social radius
	if social.monogamy_tendency >= 0.35 and world != null:
		var pos_store: Dictionary = reg.get_store(&"PositionComponent")
		var my_pos: _PositionComponent = pos_store.get(eid, null)
		var partner_pos: _PositionComponent = pos_store.get(social.bonded_partner_eid, null)
		if my_pos != null and partner_pos != null:
			var dist: float = my_pos.position.distance_to(partner_pos.position)
			if dist <= float(social.social_radius):
				return true

	return false

## Attempts physical mating between two creatures with mutual trait preference evaluation.
func attempt_mating(eid_a: int, eid_b: int) -> bool:
	if not can_mate(eid_a, eid_b):
		return false

	var reg = world.get_registry()
	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var mating_store: Dictionary   = reg.get_store(&"MatingComponent")
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")
	var pos_store: Dictionary      = reg.get_store(&"PositionComponent")
	var mem_store: Dictionary      = reg.get_store(&"MemoryComponent")

	var ma: _MatingComponent = mating_store[eid_a]
	var mb: _MatingComponent = mating_store[eid_b]

	# Mutual trait matching preference check
	var pref_a: float = calculate_trait_matching_score(eid_a, eid_b)
	var pref_b: float = calculate_trait_matching_score(eid_b, eid_a)

	if pref_a < ma.preference_threshold or pref_b < mb.preference_threshold:
		return false

	# Identify roles
	var male_eid: int   = eid_a if ma.is_male() else eid_b
	var female_eid: int = eid_b if ma.is_male() else eid_a
	var male_mating: _MatingComponent   = ma if ma.is_male() else mb
	var female_mating: _MatingComponent = mb if ma.is_male() else ma
	var male_mind: _MindComponent       = mind_store.get(male_eid, null)
	var female_mind: _MindComponent     = mind_store.get(female_eid, null)
	var male_traits: _TraitComponent    = trait_store.get(male_eid, null)
	var male_creature: _CreatureComponent = creature_store.get(male_eid, null)
	var female_creature: _CreatureComponent = creature_store.get(female_eid, null)
	var pos_comp: _PositionComponent    = pos_store.get(female_eid, null)

	# Conception & Pregnancy
	female_mating.is_pregnant = true
	female_mating.gestation_ticks = 0
	female_mating.partner_father_eid = male_eid
	female_mating.partner_father_species = male_creature.species_type if male_creature != null else 0
	female_mating.partner_father_traits = male_traits.genetic_traits.duplicate() if male_traits != null else []

	# Cooldowns
	male_mating.mating_cooldown_ticks = 200
	female_mating.mating_cooldown_ticks = female_mating.gestation_duration + 200

	# Satiate mating drives
	if male_mind != null:
		male_mind.mating = 0.0
	if female_mind != null:
		female_mind.mating = 0.0

	# Pair Bonding Evaluation based on pair_bond_tendency & monogamy_tendency
	var male_social: _SocialComponent = reg.get_component(male_eid, &"SocialComponent")
	var female_social: _SocialComponent = reg.get_component(female_eid, &"SocialComponent")
	if male_social != null and female_social != null:
		# If already bonded to each other, bond is reinforced
		if male_social.bonded_partner_eid == female_eid and female_social.bonded_partner_eid == male_eid:
			pass
		else:
			# Preserve existing living bonds: an individual will only form a new bond
			# if they have no living partner, or if their monogamy tendency is very low (< 0.20)
			var male_has_living_partner: bool = male_social.has_bonded_partner() and male_social.is_partner_alive(reg)
			var female_has_living_partner: bool = female_social.has_bonded_partner() and female_social.is_partner_alive(reg)

			var male_open: bool = not male_has_living_partner or (male_social.monogamy_tendency < 0.20 and randf() > male_social.monogamy_tendency)
			var female_open: bool = not female_has_living_partner or (female_social.monogamy_tendency < 0.20 and randf() > female_social.monogamy_tendency)

			if male_open and female_open:
				var bond_prob: float = (male_social.pair_bond_tendency + female_social.pair_bond_tendency) * 0.5
				if randf() < bond_prob:
					male_social.bonded_partner_eid = female_eid
					female_social.bonded_partner_eid = male_eid

	var mate_pos: Vector2i = pos_comp.position if pos_comp != null else Vector2i.ZERO
	if world.signals != null:
		world.signals.emit_sound(mate_pos, 0.25, 2)

	var mem_a: _MemoryComponent = mem_store.get(eid_a, null)
	var mem_b: _MemoryComponent = mem_store.get(eid_b, null)
	if mem_a != null:
		mem_a.record_event(mate_pos, &"mated", world.tick_count, 1.0)
	if mem_b != null:
		mem_b.record_event(mate_pos, &"mated", world.tick_count, 1.0)

	print("[Mating] %s and %s successfully mated at %s! Trait match: %.2f / %.2f." % [
		male_creature.creature_name if male_creature != null else "Male",
		female_creature.creature_name if female_creature != null else "Female",
		mate_pos,
		pref_a, pref_b
	])

	return true

# ---------------------------------------------------------------------------
# Birth & Offspring Generation
# ---------------------------------------------------------------------------

func _give_birth(
	mother_eid: int,
	mother_creature: _CreatureComponent,
	female_mating: _MatingComponent,
	mother_traits: _TraitComponent,
	mother_pos: Vector2i,
	_tick_number: int
) -> void:
	# Calculate litter size scaled by female spawn_rate
	var base_roll: float = randf_range(float(female_mating.litter_size_min), float(female_mating.litter_size_max))
	var litter_size: int = maxi(1, int(round(base_roll * female_mating.spawn_rate)))

	var mother_species: int = mother_creature.species_type
	var spec_data: Dictionary = _CreatureTypes.get_data(mother_species)
	var trait_pool: Array = spec_data.get("trait_pool", [])

	var mother_gen_traits: Array[int] = mother_traits.genetic_traits if mother_traits != null else []
	var father_gen_traits: Array[int] = female_mating.partner_father_traits

	for i in range(litter_size):
		var child_pos: Vector2i = _find_spawn_tile_around(mother_pos)

		# Genetic inheritance: inherit 50% from mother, 50% from father
		var child_traits: Array[int] = []
		for t: int in mother_gen_traits:
			if randf() < 0.60 and not child_traits.has(t):
				child_traits.append(t)
		for t: int in father_gen_traits:
			if randf() < 0.60 and not child_traits.has(t):
				child_traits.append(t)

		# Small chance (10%) to mutate a trait from species pool
		if not trait_pool.is_empty() and randf() < 0.10:
			var rolled: int = trait_pool[randi() % trait_pool.size()]
			if not child_traits.has(rolled):
				child_traits.append(rolled)

		var child_eid: int = _CreatureFactory.create(
			world,
			mother_species,
			child_pos,
			"",
			child_traits,
			_CreatureTypes.GrowthStage.JUVENILE
		)
		if child_eid != -1:
			female_mating.total_offspring_spawned += 1
			# Establish Kinship Bond between mother and offspring
			if world != null:
				var reg = world.get_registry()
				if reg != null:
					var mother_social: _SocialComponent = reg.get_component(mother_eid, &"SocialComponent")
					var child_social: _SocialComponent  = reg.get_component(child_eid, &"SocialComponent")
					if child_social != null:
						child_social.mother_eid = mother_eid
					if mother_social != null:
						mother_social.add_offspring(child_eid)

	female_mating.is_pregnant = false
	female_mating.gestation_ticks = 0
	female_mating.total_litters_produced += 1
	female_mating.partner_father_eid = -1
	female_mating.partner_father_traits.clear()

	if world.signals != null:
		world.signals.emit_sound(mother_pos, 0.40, 3)

	world.mark_render_dirty()
	print("[Birth] %s gave birth to %d offspring at %s (Spawnrate: %.2f, Total Offspring: %d)!" % [
		mother_creature.creature_name,
		litter_size,
		mother_pos,
		female_mating.spawn_rate,
		female_mating.total_offspring_spawned
	])

func _find_spawn_tile_around(center: Vector2i) -> Vector2i:
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	offsets.shuffle()
	for offset in offsets:
		var p: Vector2i = center + offset
		if world.is_valid_position(p) and world.signals != null:
			if world.signals.has_affordance(p, _TileAffordance.WALKABLE) and not world.signals.has_affordance(p, _TileAffordance.HAZARD_LETHAL):
				return p
	return center

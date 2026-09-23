## CreatureBodySystem.gd
## Priority 225 -- runs right after SignalSystem (220).
##
## Simulates internal biological processes:
## - Digestion and hunger/thirst drive accumulation.
## - Blood circulation, bleeding, and blood scent emission.
## - Limb wear and mobility calculation.
## - Vital signs check and mortality.
class_name CreatureBodySystem
extends "res://core/SystemBase.gd"

const _CreatureComponent = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent     = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent     = preload("res://modules/creature/components/mind/MindComponent.gd")
const _TraitComponent    = preload("res://modules/creature/components/TraitComponent.gd")
const _CreatureTypes     = preload("res://modules/creature/data/CreatureTypes.gd")
const _SignalTypes       = preload("res://modules/signal/data/SignalTypes.gd")

func initialize() -> void:
	print("[CreatureBodySystem] Initialized. Priority 225.")

func tick(_tick_number: int) -> void:
	if world == null:
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var body_store: Dictionary     = reg.get_store(&"BodyComponent")
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")
	var pos_store: Dictionary      = reg.get_store(&"PositionComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		creature.age_ticks += 1
		var body: _BodyComponent = body_store.get(eid, null)
		var mind: _MindComponent = mind_store.get(eid, null)
		var pos_comp: _PositionComponent = pos_store.get(eid, null)
		var traits: _TraitComponent = trait_store.get(eid, null)

		var spec_data: Dictionary = _CreatureTypes.get_data(creature.species_type)
		var metab_rate: float = spec_data.get("metabolism_rate", 0.004)
		var thirst_rate: float = spec_data.get("thirst_rate", 0.003)

		if traits != null:
			metab_rate *= traits.get_stat_multiplier(&"metabolism_mult", 1.0)
			thirst_rate *= traits.get_stat_multiplier(&"thirst_mult", 1.0)

		# 1. Digestion & Hunger
		if creature.stomach_fill > 0.0:
			var digested: float = minf(creature.stomach_fill, 0.1)
			creature.stomach_fill -= digested
			if mind != null:
				mind.hunger = maxf(0.0, mind.hunger - digested * 0.02)
		else:
			if mind != null:
				mind.hunger = minf(1.0, mind.hunger + metab_rate)

		# 2. Thirst & Fatigue
		if mind != null:
			mind.thirst = minf(1.0, mind.thirst + thirst_rate)
			# Natural fatigue recovery if not moving
			var fat_gain_mult: float = traits.get_stat_multiplier(&"fatigue_gain_mult", 1.0) if traits != null else 1.0
			var fat_rec_mult: float = traits.get_stat_multiplier(&"fatigue_rec_mult", 1.0) if traits != null else 1.0

			if pos_comp != null and pos_comp.move_cooldown_ticks > 0:
				mind.fatigue = minf(1.0, mind.fatigue + 0.005 * fat_gain_mult)
			else:
				mind.fatigue = maxf(0.0, mind.fatigue - 0.002 * fat_rec_mult)

		# 3. Circulatory & Bleeding
		if body != null:
			if body.bleed_rate > 0.0:
				var bleed_mult: float = traits.get_stat_multiplier(&"bleed_rate_mult", 1.0) if traits != null else 1.0
				var actual_bleed: float = body.bleed_rate * bleed_mult
				body.blood_volume = maxf(0.0, body.blood_volume - actual_bleed)
				if mind != null:
					mind.pain = minf(1.0, mind.pain + 0.02)

				# Emit blood scent into atmosphere
				if pos_comp != null and world.signals != null:
					world.signals.emit_scent(_SignalTypes.SCENT_BLOOD, pos_comp.position, 0.6, 2)

			# 4. Mobility calculation from leg health
			creature.mobility_factor = body.get_mobility(reg)

			# 5. Health & Vital checks
			var blood_ratio: float = body.blood_volume / maxf(0.1, body.max_blood_volume)
			creature.health = blood_ratio

			if blood_ratio <= 0.2 or not body.are_vitals_functional(reg):
				creature.is_alive = false
				print("[Creature] %s (eid=%d) died." % [creature.creature_name, eid])

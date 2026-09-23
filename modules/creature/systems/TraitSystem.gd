## TraitSystem.gd
## Priority 224 -- runs right before CreatureBodySystem (225).
##
## Manages the lifecycle of temporary buffs and debuffs:
## 1. Decrements duration counters and prunes expired status effects.
## 2. Continuously monitors biological thresholds (hunger, thirst, fatigue, fear)
##    to dynamically trigger and clear contextual buffs & debuffs.
## 3. Applies tick-level status effects (e.g. passive healing from Well-Fed, starvation damage).
class_name TraitSystem
extends "res://core/SystemBase.gd"

const _CreatureComponent = preload("res://modules/creature/components/CreatureComponent.gd")
const _MindComponent     = preload("res://modules/creature/components/mind/MindComponent.gd")
const _TraitComponent    = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes        = preload("res://modules/creature/data/TraitTypes.gd")

func initialize() -> void:
	print("[TraitSystem] Initialized. Priority 224.")

func tick(_tick_number: int) -> void:
	if world == null:
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var traits: _TraitComponent = trait_store.get(eid, null)
		if traits == null:
			continue

		var mind: _MindComponent = mind_store.get(eid, null)

		# -------------------------------------------------------------------
		# 1. Decrement and Prune Expired Buffs & Debuffs
		# -------------------------------------------------------------------
		var expired_buffs: Array[int] = []
		for bid: int in traits.active_buffs:
			var b = traits.active_buffs[bid]
			b["duration"] -= 1
			if b["duration"] <= 0:
				expired_buffs.append(bid)

		var expired_debuffs: Array[int] = []
		for did: int in traits.active_debuffs:
			var d = traits.active_debuffs[did]
			d["duration"] -= 1
			if d["duration"] <= 0:
				expired_debuffs.append(did)

		for bid in expired_buffs:
			traits.remove_buff(bid)

		for did in expired_debuffs:
			traits.remove_debuff(did)

		# -------------------------------------------------------------------
		# 2. Contextual / Threshold-Driven Buffs and Debuffs
		# -------------------------------------------------------------------
		if mind != null:
			# --- Hunger & Starvation ---
			if mind.hunger >= 0.85:
				traits.add_debuff(_TraitTypes.Type.STARVING, 10)
			elif mind.hunger < 0.60 and traits.has_debuff(_TraitTypes.Type.STARVING):
				traits.remove_debuff(_TraitTypes.Type.STARVING)

			# --- Well-Fed (Stomach > 70% capacity) ---
			var stomach_ratio: float = creature.stomach_fill / maxf(1.0, creature.stomach_capacity)
			if stomach_ratio >= 0.70:
				traits.add_buff(_TraitTypes.Type.WELL_FED, 15)
			elif stomach_ratio < 0.40 and traits.has_buff(_TraitTypes.Type.WELL_FED):
				traits.remove_buff(_TraitTypes.Type.WELL_FED)

			# --- Thirst & Dehydration ---
			if mind.thirst >= 0.85:
				traits.add_debuff(_TraitTypes.Type.DEHYDRATED, 10)
			elif mind.thirst < 0.50 and traits.has_debuff(_TraitTypes.Type.DEHYDRATED):
				traits.remove_debuff(_TraitTypes.Type.DEHYDRATED)

			# --- Hydrated (Thirst <= 20%) ---
			if mind.thirst <= 0.20:
				traits.add_buff(_TraitTypes.Type.HYDRATED, 15)
			elif mind.thirst > 0.40 and traits.has_buff(_TraitTypes.Type.HYDRATED):
				traits.remove_buff(_TraitTypes.Type.HYDRATED)

			# --- Fatigue & Exhaustion ---
			if mind.fatigue >= 0.85:
				traits.add_debuff(_TraitTypes.Type.EXHAUSTED, 10)
			elif mind.fatigue < 0.50 and traits.has_debuff(_TraitTypes.Type.EXHAUSTED):
				traits.remove_debuff(_TraitTypes.Type.EXHAUSTED)

			# --- Rested (Fatigue <= 15%) ---
			if mind.fatigue <= 0.15:
				traits.add_buff(_TraitTypes.Type.RESTED, 15)
			elif mind.fatigue > 0.35 and traits.has_buff(_TraitTypes.Type.RESTED):
				traits.remove_buff(_TraitTypes.Type.RESTED)

			# --- Fear, Panic & Adrenaline ---
			if mind.fear >= 0.70:
				traits.add_debuff(_TraitTypes.Type.PANICKED, 8)
				traits.add_buff(_TraitTypes.Type.ADRENALINE_RUSH, 25)
			elif mind.fear < 0.35 and traits.has_debuff(_TraitTypes.Type.PANICKED):
				traits.remove_debuff(_TraitTypes.Type.PANICKED)

		# -------------------------------------------------------------------
		# 3. Status Effect Continuous Physiology (Healing / Damage)
		# -------------------------------------------------------------------
		if traits.has_buff(_TraitTypes.Type.WELL_FED) and creature.health < 1.0:
			creature.health = minf(1.0, creature.health + 0.002)

		if traits.has_debuff(_TraitTypes.Type.STARVING) or traits.has_debuff(_TraitTypes.Type.DEHYDRATED):
			creature.health = maxf(0.0, creature.health - 0.002)
			if creature.health <= 0.05:
				creature.is_alive = false
				print("[Creature] %s died of severe starvation/dehydration." % creature.creature_name)

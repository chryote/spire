## TraitComponent.gd
## Holds a creature's permanent genetic profile as well as active temporary buffs and debuffs.
## Caches pre-computed action utility weights and physiological stat modifiers for zero-overhead queries.
class_name TraitComponent
extends Resource

const _TraitTypes      = preload("res://modules/creature/data/TraitTypes.gd")
const _MindEmbeddings = preload("res://modules/creature/data/MindEmbeddings.gd")

## Permanent genetic trait IDs (TraitTypes.Type).
var genetic_traits: Array[int] = []

## Active temporary buffs: { int(TraitTypes.Type) -> { "duration": int, "stacks": int } }
var active_buffs: Dictionary = {}

## Active temporary debuffs: { int(TraitTypes.Type) -> { "duration": int, "stacks": int } }
var active_debuffs: Dictionary = {}

## Cached action utility adjustments: { int(Action) -> { "mult": float, "add": float } }
var _action_weights: Dictionary = {}

## Cached stat multipliers & offsets: { StringName -> float }
var _stat_multipliers: Dictionary = {}
var _stat_offsets: Dictionary = {}

var _dirty: bool = true

func _init() -> void:
	rebuild_cache()

# ---------------------------------------------------------------------------
# Query & Accessors
# ---------------------------------------------------------------------------

func has_trait(trait_id: int) -> bool:
	return genetic_traits.has(trait_id) or active_buffs.has(trait_id) or active_debuffs.has(trait_id)

func has_genetic_trait(trait_id: int) -> bool:
	return genetic_traits.has(trait_id)

func has_buff(buff_id: int) -> bool:
	return active_buffs.has(buff_id)

func has_debuff(debuff_id: int) -> bool:
	return active_debuffs.has(debuff_id)

func get_all_active_traits() -> Array[int]:
	var result: Array[int] = []
	for t: int in genetic_traits:
		if not result.has(t):
			result.append(t)
	for b: int in active_buffs:
		if not result.has(b):
			result.append(b)
	for d: int in active_debuffs:
		if not result.has(d):
			result.append(d)
	return result

# ---------------------------------------------------------------------------
# Mutators
# ---------------------------------------------------------------------------

func add_genetic_trait(trait_id: int) -> void:
	if not genetic_traits.has(trait_id):
		genetic_traits.append(trait_id)
		_dirty = true
		rebuild_cache()

func remove_genetic_trait(trait_id: int) -> void:
	if genetic_traits.has(trait_id):
		genetic_traits.erase(trait_id)
		_dirty = true
		rebuild_cache()

func add_buff(buff_id: int, duration_ticks: int, stacks: int = 1) -> void:
	var existing = active_buffs.get(buff_id, null)
	if existing != null:
		existing["duration"] = maxi(existing["duration"], duration_ticks)
		existing["stacks"] = mini(existing["stacks"] + stacks, 5)
	else:
		active_buffs[buff_id] = {
			"duration": duration_ticks,
			"stacks": stacks
		}
	_dirty = true
	rebuild_cache()

func remove_buff(buff_id: int) -> void:
	if active_buffs.erase(buff_id):
		_dirty = true
		rebuild_cache()

func add_debuff(debuff_id: int, duration_ticks: int, stacks: int = 1) -> void:
	var existing = active_debuffs.get(debuff_id, null)
	if existing != null:
		existing["duration"] = maxi(existing["duration"], duration_ticks)
		existing["stacks"] = mini(existing["stacks"] + stacks, 5)
	else:
		active_debuffs[debuff_id] = {
			"duration": duration_ticks,
			"stacks": stacks
		}
	_dirty = true
	rebuild_cache()

func remove_debuff(debuff_id: int) -> void:
	if active_debuffs.erase(debuff_id):
		_dirty = true
		rebuild_cache()

func clear_effect(effect_id: int) -> void:
	var erased: bool = active_buffs.erase(effect_id) or active_debuffs.erase(effect_id)
	if erased:
		_dirty = true
		rebuild_cache()

# ---------------------------------------------------------------------------
# Cache & Calculations
# ---------------------------------------------------------------------------

func rebuild_cache() -> void:
	_action_weights.clear()
	_stat_multipliers.clear()
	_stat_offsets.clear()

	# Defaults for actions: mult = 1.0, add = 0.0
	for act: int in [
		_MindEmbeddings.Action.IDLE,
		_MindEmbeddings.Action.EAT,
		_MindEmbeddings.Action.DRINK,
		_MindEmbeddings.Action.FLEE,
		_MindEmbeddings.Action.REST,
		_MindEmbeddings.Action.WANDER
	]:
		_action_weights[act] = { "mult": 1.0, "add": 0.0 }

	# Process all traits, buffs, debuffs
	var all_traits: Array[int] = get_all_active_traits()
	for tid: int in all_traits:
		var data: Dictionary = _TraitTypes.get_data(tid)
		if data.is_empty():
			continue

		# Action weight adjustments
		var act_cfg: Dictionary = data.get("action_weights", {})
		for act_key: int in act_cfg:
			var aw: Dictionary = act_cfg[act_key]
			var entry: Dictionary = _action_weights.get(act_key, { "mult": 1.0, "add": 0.0 })
			entry["mult"] *= aw.get("mult", 1.0)
			entry["add"] += aw.get("add", 0.0)
			_action_weights[act_key] = entry

		# Stat modifiers
		var stat_cfg: Dictionary = data.get("stat_modifiers", {})
		for s_key: String in stat_cfg:
			var s_val = stat_cfg[s_key]
			if s_key.ends_with("_mult"):
				var cur_mult: float = _stat_multipliers.get(StringName(s_key), 1.0)
				_stat_multipliers[StringName(s_key)] = cur_mult * float(s_val)
			elif s_key.ends_with("_mod") or s_key == "move_cooldown":
				var cur_off: int = _stat_offsets.get(StringName(s_key), 0)
				_stat_offsets[StringName(s_key)] = cur_off + int(s_val)
			else:
				# General multiplier or value override
				var cur_val: float = _stat_multipliers.get(StringName(s_key), 1.0)
				_stat_multipliers[StringName(s_key)] = cur_val * float(s_val)

	_dirty = false

func get_action_weight(action: int) -> Dictionary:
	if _dirty:
		rebuild_cache()
	return _action_weights.get(action, { "mult": 1.0, "add": 0.0 })

func apply_action_weight(action: int, base_utility: float) -> float:
	if _dirty:
		rebuild_cache()
	var w: Dictionary = _action_weights.get(action, { "mult": 1.0, "add": 0.0 })
	return clampf((base_utility * w["mult"]) + w["add"], 0.0, 1.0)

func get_stat_multiplier(stat_name: StringName, default_value: float = 1.0) -> float:
	if _dirty:
		rebuild_cache()
	return _stat_multipliers.get(stat_name, default_value)

func get_stat_offset(stat_name: StringName, default_value: int = 0) -> int:
	if _dirty:
		rebuild_cache()
	return _stat_offsets.get(stat_name, default_value)

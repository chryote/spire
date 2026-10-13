## BodyComponent.gd
## Container component for a creature's physical anatomy.
## Holds references to discrete item/matter entities for limbs, organs,
## and maintains the creature's blood volume reservoir and thermodynamic state.
class_name BodyComponent
extends Resource

const _ItemComponent      = preload("res://modules/item/components/ItemComponent.gd")
const _MatterComponent    = preload("res://modules/matter/components/MatterComponent.gd")
const _InventoryComponent = preload("res://modules/item/components/InventoryComponent.gd")
const _SignalTypes        = preload("res://modules/signal/data/SignalTypes.gd")

## Map of limb_name (String) -> entity_id (int)
var limbs: Dictionary = {}

## Map of organ_name (String) -> entity_id (int)
var organs: Dictionary = {}

## Names of limbs considered vital to life (severing / loss results in instant death).
var vital_limbs: Array[String] = ["head", "torso"]

## Circulatory fluid volume in liters.
var blood_volume: float = 2.5

## Maximum blood volume in liters.
var max_blood_volume: float = 2.5

## Blood loss rate per tick (L/tick).
var bleed_rate: float = 0.0

## Internal core body temperature in Celsius.
var body_temperature_c: float = 38.0

## Computes total anatomical mass (flesh, bones, organs, blood) in kilograms.
func get_total_mass(reg) -> float:
	var mass: float = blood_volume * 1.06  # Blood density ~1.06 kg/L
	if reg == null:
		return mass

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	for eid: int in limbs.values():
		var item = item_store.get(eid, null)
		if item != null:
			mass += item.total_mass
	for eid: int in organs.values():
		var item = item_store.get(eid, null)
		if item != null:
			mass += item.total_mass
	return maxf(0.5, mass)

## Computes mobility factor [0.0, 1.0] based on leg condition.
func get_mobility(reg) -> float:
	if reg == null:
		return 1.0

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	var standard_legs: Array[String] = ["left_foreleg", "right_foreleg", "left_hindleg", "right_hindleg"]
	var expected_leg_count: int = standard_legs.size()
	var leg_health_sum: float = 0.0

	for limb_name: String in standard_legs:
		if limbs.has(limb_name):
			var eid: int = limbs[limb_name]
			var item = item_store.get(eid, null)
			if item != null:
				var flesh_wear: float = item.parts.get("flesh", {}).get("wear", 0.0) as float
				var bone_wear: float  = item.parts.get("bone", {}).get("wear", 0.0) as float
				var limb_health: float = 1.0 - clampf(maxf(flesh_wear, bone_wear), 0.0, 1.0)
				leg_health_sum += limb_health
			else:
				leg_health_sum += 1.0

	return clampf(leg_health_sum / float(expected_leg_count), 0.1, 1.0)

## Checks whether all critical vital organs (heart, lungs, brain) and vital limbs (head, torso) remain functional.
func are_vitals_functional(reg) -> bool:
	if reg == null:
		return true
	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	
	# 1. Check vital organs
	for organ_name in ["heart", "lungs", "brain"]:
		var eid: int = organs.get(organ_name, -1)
		if eid == -1:
			return false
		var item = item_store.get(eid, null)
		if item == null:
			return false
		var wear: float = item.parts.get("tissue", {}).get("wear", 0.0) as float
		if wear >= 1.0:
			return false

	# 2. Check vital limbs (head, torso)
	for limb_name in vital_limbs:
		var eid: int = limbs.get(limb_name, -1)
		if eid == -1:
			return false
		var item = item_store.get(eid, null)
		if item == null:
			return false
		var flesh_wear: float = item.parts.get("flesh", {}).get("wear", 0.0) as float
		var bone_wear: float  = item.parts.get("bone", {}).get("wear", 0.0) as float
		if maxf(flesh_wear, bone_wear) >= 1.0:
			return false

	return true

## Severs a limb from the creature and drops it into the ground tile's InventoryComponent.
## Returns the severed limb entity ID (-1 if limb not found).
func sever_limb(world: Node, creature_eid: int, limb_name: String, reg) -> int:
	if not limbs.has(limb_name):
		return -1

	var limb_eid: int = limbs[limb_name]
	limbs.erase(limb_name)

	if reg == null or world == null:
		return limb_eid

	var pos_comp = reg.get_component(creature_eid, &"PositionComponent")
	var creature_comp = reg.get_component(creature_eid, &"CreatureComponent")
	var mind_comp = reg.get_component(creature_eid, &"MindComponent")
	var item_comp = reg.get_component(limb_eid, &"ItemComponent")

	var pos: Vector2i = pos_comp.position if pos_comp != null else Vector2i.ZERO
	var tile_eid: int = world.get_entity_at(pos)

	if tile_eid != -1:
		var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
		if inv == null:
			inv = _InventoryComponent.new()
			inv.container_id = tile_eid
			reg.add(tile_eid, inv)

		if item_comp != null:
			item_comp.container_id = tile_eid
			if not item_comp.display_name.begins_with("Severed "):
				item_comp.display_name = "Severed " + item_comp.display_name

		inv.items.append(limb_eid)
		inv.update_cache(reg)

		if world.signals != null:
			world.signals.register_active_inventory(tile_eid)
			world.signals.emit_scent(_SignalTypes.SCENT_BLOOD, pos, 0.8, 2)

	# Apply severe physiological trauma
	var is_vital: bool = vital_limbs.has(limb_name)
	if is_vital:
		if mind_comp != null:
			mind_comp.pain = 1.0
			mind_comp.is_in_shock = true
		bleed_rate = 0.5
		if creature_comp != null:
			creature_comp.is_alive = false
			creature_comp.health = 0.0
	else:
		if mind_comp != null:
			mind_comp.pain = minf(1.0, mind_comp.pain + 0.40)
			if mind_comp.pain >= mind_comp.shock_pain_threshold:
				mind_comp.is_in_shock = true
		bleed_rate = minf(0.5, bleed_rate + 0.15)

	world.mark_render_dirty()
	print("[Creature] Limb '%s' (eid=%d) severed from %s at %s. (vital=%s)" % [
		limb_name,
		limb_eid,
		creature_comp.creature_name if creature_comp != null else "Creature",
		pos,
		is_vital
	])
	return limb_eid

## Proportionally rescales blood volume and anatomical parts (limbs and organs).
func rescale_anatomy(reg, new_scale: float, old_scale: float) -> void:
	if old_scale <= 0.001 or new_scale <= 0.001:
		return
	var factor: float = new_scale / old_scale

	# Rescale blood volume
	max_blood_volume = maxf(0.1, max_blood_volume * factor)
	blood_volume = clampf(blood_volume * factor, 0.0, max_blood_volume)

	if reg == null:
		return

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	for eid: int in limbs.values():
		var item = item_store.get(eid, null)
		if item != null:
			item.total_volume *= factor
			item.total_mass *= factor
			for p_name in item.parts:
				var part = item.parts[p_name]
				if part.has("volume"):
					part["volume"] *= factor
				if part.has("mass"):
					part["mass"] *= factor

	for eid: int in organs.values():
		var item = item_store.get(eid, null)
		if item != null:
			item.total_volume *= factor
			item.total_mass *= factor
			for p_name in item.parts:
				var part = item.parts[p_name]
				if part.has("volume"):
					part["volume"] *= factor
				if part.has("mass"):
					part["mass"] *= factor

## Returns the name of the genital limb ("male_genital", "female_genital"), or empty string if none.
func get_genital_limb_name() -> String:
	for limb_name: String in limbs:
		if limb_name.ends_with("genital"):
			return limb_name
	return ""

## Checks whether the creature has an intact, functional genital limb.
func has_intact_genital(reg, genital_name: String = "") -> bool:
	var g_name: String = genital_name if genital_name != "" else get_genital_limb_name()
	if g_name == "" or not limbs.has(g_name):
		return false
	if reg == null:
		return true

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	var eid: int = limbs.get(g_name, -1)
	if eid == -1:
		return false

	var item = item_store.get(eid, null)
	if item != null:
		var flesh_wear: float = item.parts.get("flesh", {}).get("wear", 0.0) as float
		var bone_wear: float  = item.parts.get("bone", {}).get("wear", 0.0) as float
		return maxf(flesh_wear, bone_wear) < 1.0
	return true

## Returns the physical wear factor [0.0, 1.0] of the genital limb.
func get_genital_wear(reg, genital_name: String = "") -> float:
	var g_name: String = genital_name if genital_name != "" else get_genital_limb_name()
	if g_name == "" or not limbs.has(g_name):
		return 1.0
	if reg == null:
		return 0.0

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	var eid: int = limbs.get(g_name, -1)
	if eid == -1:
		return 1.0

	var item = item_store.get(eid, null)
	if item != null:
		var flesh_wear: float = item.parts.get("flesh", {}).get("wear", 0.0) as float
		var bone_wear: float  = item.parts.get("bone", {}).get("wear", 0.0) as float
		return clampf(maxf(flesh_wear, bone_wear), 0.0, 1.0)
	return 0.0


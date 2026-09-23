## BodyComponent.gd
## Container component for a creature's physical anatomy.
## Holds references to discrete item/matter entities for limbs, organs,
## and maintains the creature's blood volume reservoir and thermodynamic state.
class_name BodyComponent
extends Resource

const _ItemComponent   = preload("res://modules/item/components/ItemComponent.gd")
const _MatterComponent = preload("res://modules/matter/components/MatterComponent.gd")

## Map of limb_name (String) -> entity_id (int)
var limbs: Dictionary = {}

## Map of organ_name (String) -> entity_id (int)
var organs: Dictionary = {}

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
	if reg == null or limbs.is_empty():
		return 1.0

	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	var leg_count: int = 0
	var leg_health_sum: float = 0.0

	for limb_name: String in limbs:
		if limb_name.ends_with("leg"):
			leg_count += 1
			var eid: int = limbs[limb_name]
			var item = item_store.get(eid, null)
			if item != null:
				var flesh_wear: float = item.parts.get("flesh", {}).get("wear", 0.0) as float
				var bone_wear: float  = item.parts.get("bone", {}).get("wear", 0.0) as float
				var limb_health: float = 1.0 - clampf(maxf(flesh_wear, bone_wear), 0.0, 1.0)
				leg_health_sum += limb_health
			else:
				leg_health_sum += 1.0

	if leg_count == 0:
		return 1.0
	return clampf(leg_health_sum / float(leg_count), 0.1, 1.0)

## Checks whether all critical vital organs (heart, lungs, brain) remain functional.
func are_vitals_functional(reg) -> bool:
	if reg == null:
		return true
	var item_store: Dictionary = reg.get_store(&"ItemComponent")
	for organ_name in ["heart", "lungs", "brain"]:
		var eid: int = organs.get(organ_name, -1)
		if eid != -1:
			var item = item_store.get(eid, null)
			if item != null:
				var wear: float = item.parts.get("tissue", {}).get("wear", 0.0) as float
				if wear >= 1.0:
					return false
	return true

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

## ItemComponent.gd
## Tags an entity as a world item.
## Holds what the item IS (archetype + mold + composite matter parts) and its computed display name.
class_name ItemComponent
extends Resource

## One of ItemTypes.Type — the base item archetype mold.
var item_type: int = 0

## Primary material type — maintained for backwards compatibility and high-level queries.
var material_type: int = 0

## Name of the primary contact part (e.g. "blade", "head", "main").
var primary_part: String = "main"

## Breakdown of individual parts making up this composite item.
## Key: part_name (String) -> Dictionary:
##   "material_id": int (MaterialTypes.Type)
##   "role": int (ItemTypes.PartRole)
##   "volume": float (m3)
##   "mass": float (kg)
##   "wear": float (0.0 = pristine, 1.0 = broken)
var parts: Dictionary = {}

## Total aggregated mass of all composite parts in kilograms.
var total_mass: float = 0.0

## Total aggregated volume of all composite parts in cubic meters.
var total_volume: float = 0.0

## Computed at creation time: e.g. "Steel Sword (Hard Wood Hilt)".
## Never re-computed at runtime — set once by ItemFactory.
var display_name: String = ""

## Stack count — 1 for a single item, >1 for bundles.
var quantity: int = 1

## Maximum units in a single stack (-1 = unstackable, default 100).
var max_stack: int = 100

## Entity ID of the container or tile currently holding this item (-1 = none / uncontained).
var container_id: int = -1

## Helper to retrieve the material ID of a specific part, falling back to primary material_type.
func get_part_material(part_name: String) -> int:
	if parts.has(part_name):
		return parts[part_name].get("material_id", material_type)
	return material_type

## Checks whether this item can accept additional units of the given archetype.
func can_stack_with(other_item_type: int, other_mat_id: int, other_parts: Dictionary = {}) -> bool:
	if max_stack <= 1 or quantity >= max_stack:
		return false
	if item_type != other_item_type or material_type != other_mat_id:
		return false

	# Disallow stacking if this item has incurred wear/damage
	for p_name in parts:
		if (parts[p_name].get("wear", 0.0) as float) > 0.001:
			return false

	# If other parts are specified, ensure materials match
	if not other_parts.is_empty():
		for p_name in other_parts:
			var mat_val = other_parts[p_name]
			var check_mat: int = mat_val["material_id"] if (mat_val is Dictionary and mat_val.has("material_id")) else (mat_val as int)
			if get_part_material(p_name) != check_mat:
				return false

	return true

## Increase quantity by amount, scaling mass and volume proportionately.
## Returns how many units could not be accepted (overflow).
func add_quantity(amount: int) -> int:
	if amount <= 0 or max_stack <= 1:
		return amount
	var space: int = max_stack - quantity
	var added: int = clampi(amount, 0, space)
	if added > 0:
		var per_unit_mass: float = total_mass / maxf(1.0, float(quantity))
		var per_unit_vol: float  = total_volume / maxf(1.0, float(quantity))
		quantity += added
		total_mass = per_unit_mass * float(quantity)
		total_volume = per_unit_vol * float(quantity)
	return amount - added



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

## Entity ID of the container or tile currently holding this item (-1 = none / uncontained).
var container_id: int = -1

## Helper to retrieve the material ID of a specific part, falling back to primary material_type.
func get_part_material(part_name: String) -> int:
	if parts.has(part_name):
		return parts[part_name].get("material_id", material_type)
	return material_type



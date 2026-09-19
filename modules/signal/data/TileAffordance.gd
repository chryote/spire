## TileAffordance.gd
## 64-bit bitmask flags representing what an actor can DO or MUST AVOID on a tile.
## Packed into a single PackedInt64Array per world map for O(1) candidate filtering.
class_name TileAffordance
extends RefCounted

enum {
	## Ground is solid and traversable by standard walking locomotion.
	WALKABLE        = 1 << 0,

	## Fluid is deep enough for swimming locomotion (volume >= 0.4).
	SWIMMABLE       = 1 << 1,

	## Active fire, deadly acid, toxic gas concentration, or extreme heat/cold.
	HAZARD_LETHAL   = 1 << 2,

	## Mud, thick briars, or shallow water that reduces movement speed.
	HAZARD_SLOW     = 1 << 3,

	## Clean, uncontaminated water source suitable for drinking.
	DRINKABLE       = 1 << 4,

	## Living plant matter edible by grazing herbivores (grass, shrubs, flowers).
	GRAZEABLE       = 1 << 5,

	## Raw meat, carcasses, or food items on the ground edible by carnivores/scavengers.
	CARNIVORE_FOOD  = 1 << 6,

	## Dense foliage (tall grass, shrubs, trees) providing concealment / hiding.
	COVER           = 1 << 7,

	## Naturally enclosed or covered area sheltered from weather and wind.
	SHELTER         = 1 << 8,
}

## Returns a comma-separated list of flag names active in the given mask.
static func mask_to_string(mask: int) -> String:
	var active: Array[String] = []
	if mask & WALKABLE:       active.append("WALKABLE")
	if mask & SWIMMABLE:      active.append("SWIMMABLE")
	if mask & HAZARD_LETHAL:  active.append("HAZARD_LETHAL")
	if mask & HAZARD_SLOW:    active.append("HAZARD_SLOW")
	if mask & DRINKABLE:      active.append("DRINKABLE")
	if mask & GRAZEABLE:      active.append("GRAZEABLE")
	if mask & CARNIVORE_FOOD: active.append("CARNIVORE_FOOD")
	if mask & COVER:          active.append("COVER")
	if mask & SHELTER:        active.append("SHELTER")
	return ", ".join(active) if not active.is_empty() else "NONE"

## ItemTypes.gd
## Static archetype table for all item base types.
##
## DATA keys per item type:
##   base_name      String         — display name root, e.g. "Grass"
##   valid_matters  Array[int]     — MaterialTypes.Type ints accepted for this archetype
##   stackable      bool           — whether items of this type merge into stacks
##   max_stack      int            — maximum stack size (only relevant when stackable=true)
##
## Naming convention: ItemFactory combines matter display_name + base_name.
##   Example: MaterialTypes.ORGANIC ("Organic") + ItemTypes.GRASS ("Grass") → "Organic Grass"
class_name ItemTypes
extends RefCounted

const _MaterialTypes = preload("res://modules/matter/data/MaterialTypes.gd")

enum Type {
	GRASS  = 0,
	STICK  = 1,
	STONE  = 2,
	LOG    = 3,
}

const DATA: Dictionary = {
	Type.GRASS: {
		"base_name":     "Grass",
		"valid_matters": [
			20,  # MaterialTypes.Type.ORGANIC
			5,   # MaterialTypes.Type.KINDLING
		],
		"stackable":  true,
		"max_stack":  64,
	},
	Type.STICK: {
		"base_name":     "Stick",
		"valid_matters": [
			6,   # MaterialTypes.Type.WOOD_SOFT
			7,   # MaterialTypes.Type.WOOD_HARD
		],
		"stackable":  true,
		"max_stack":  32,
	},
	Type.STONE: {
		"base_name":     "Stone",
		"valid_matters": [
			0,   # MaterialTypes.Type.STONE
			10,  # MaterialTypes.Type.OBSIDIAN
		],
		"stackable":  true,
		"max_stack":  16,
	},
	Type.LOG: {
		"base_name":     "Log",
		"valid_matters": [
			7,   # MaterialTypes.Type.WOOD_HARD
			6,   # MaterialTypes.Type.WOOD_SOFT
		],
		"stackable":  true,
		"max_stack":  8,
	},
}

static func get_data(item_type: int) -> Dictionary:
	return DATA.get(item_type, DATA[Type.GRASS])

## True when the given material_type is a valid composition for this archetype.
static func is_valid_combination(item_type: int, material_type: int) -> bool:
	return material_type in get_data(item_type).get("valid_matters", [])

## Compose the display name from material + archetype.
## E.g. ORGANIC (20) + GRASS (0) → "Organic Grass"
static func build_name(item_type: int, material_type: int) -> String:
	var mat_name: String = _MaterialTypes.get_display_name(material_type)
	var base:     String = get_data(item_type).get("base_name", "Item")
	return mat_name + " " + base


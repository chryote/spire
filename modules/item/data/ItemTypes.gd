## ItemTypes.gd
## Static archetype table for all item base types.
## Acts as the physical "mold" that shapes raw matter into items.
##
## DATA keys per item type:
##   base_name      String         — display name root, e.g. "Sword"
##   valid_matters  Array[int]     — MaterialTypes.Type ints accepted for primary part
##   stackable      bool           — whether items of this type merge into stacks
##   max_stack      int            — maximum stack size
##   parts          Dictionary     — Part definitions:
##                                    role: PartRole (PRIMARY_CONTACT, HANDLE, SECONDARY, CONTAINER)
##                                    volume: float (m3)
##                                    valid_matters: Array[int]
##                                    default_matter: int
##                                    contact_area: float (m2)
##                                    form: ImpactTypes.Form
##                                    alt_form: ImpactTypes.Form (optional)
##                                    sharpness: float
##                                    thickness: float (meters)
class_name ItemTypes
extends RefCounted

const _MaterialTypes = preload("res://modules/matter/data/MaterialTypes.gd")
const _ImpactTypes   = preload("res://modules/matter/data/ImpactTypes.gd")

enum Type {
	GRASS     = 0,
	STICK     = 1,
	STONE     = 2,
	LOG       = 3,
	SWORD     = 4,
	SPEAR     = 5,
	WARHAMMER = 6,
	PICKAXE   = 7,
	TORCH     = 8,
	DAGGER    = 9,
	LIMB      = 10,
	ORGAN     = 11,
}

## Functional role of an item part within the mold.
enum PartRole {
	PRIMARY_CONTACT = 0,  ## Delivers cuts/strikes/piercing; contacts targets directly
	HANDLE          = 1,  ## Grip or shaft; provides leverage, absorbs shock, contributes mass
	SECONDARY       = 2,  ## Fittings, guards, pommels, or wraps
	CONTAINER       = 3,  ## Enclosure or vessel holding fluids or loose items
	COATING         = 4,  ## Surface liquid/paste coating (venom, acid, grease, oil)
	PAYLOAD         = 5,  ## Internal or socketed chemical/explosive charge
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
		"parts": {
			"main": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.00006,  # 0.06 liters plant fiber
				"valid_matters":  [20, 5],
				"default_matter": 20,
				"contact_area":   0.001,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.005,
			},
			"water": {
				"role":           PartRole.CONTAINER,
				"volume":         0.00004,  # 0.04 liters water / sap
				"valid_matters":  [8],      # MaterialTypes.Type.WATER
				"default_matter": 8,
				"optional":       true,
			}
		}
	},
	Type.STICK: {
		"base_name":     "Stick",
		"valid_matters": [
			6,   # MaterialTypes.Type.WOOD_SOFT
			7,   # MaterialTypes.Type.WOOD_HARD
		],
		"stackable":  true,
		"max_stack":  32,
		"parts": {
			"main": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0004,  # 0.4 liters
				"valid_matters":  [6, 7],
				"default_matter": 6,
				"contact_area":   0.002,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.8,
				"thickness":      0.02,
			}
		}
	},
	Type.STONE: {
		"base_name":     "Stone",
		"valid_matters": [
			0,   # MaterialTypes.Type.STONE
			10,  # MaterialTypes.Type.OBSIDIAN
		],
		"stackable":  true,
		"max_stack":  16,
		"parts": {
			"main": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0005,  # 0.5 liters
				"valid_matters":  [0, 10],
				"default_matter": 0,
				"contact_area":   0.005,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      1.0,
				"thickness":      0.05,
			}
		}
	},
	Type.LOG: {
		"base_name":     "Log",
		"valid_matters": [
			7,   # MaterialTypes.Type.WOOD_HARD
			6,   # MaterialTypes.Type.WOOD_SOFT
		],
		"stackable":  true,
		"max_stack":  8,
		"parts": {
			"main": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.025,   # 25 liters
				"valid_matters":  [7, 6],
				"default_matter": 7,
				"contact_area":   0.05,
				"form":           _ImpactTypes.Form.CRUSH,
				"sharpness":      0.5,
				"thickness":      0.2,
			}
		}
	},
	Type.SWORD: {
		"base_name":     "Sword",
		"valid_matters": [
			9,   # MaterialTypes.Type.STEEL
			0,   # MaterialTypes.Type.STONE
			10,  # MaterialTypes.Type.OBSIDIAN
			7,   # MaterialTypes.Type.WOOD_HARD
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"blade": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0008,  # 0.8 liters metal
				"valid_matters":  [9, 0, 10, 7],
				"default_matter": 9,
				"contact_area":   0.0002,  # 2 cm2 blade edge
				"form":           _ImpactTypes.Form.SLASH,
				"alt_form":       _ImpactTypes.Form.PIERCE,
				"sharpness":      1.5,
				"thickness":      0.015,
			},
			"hilt": {
				"role":           PartRole.HANDLE,
				"volume":         0.0003,  # 0.3 liters
				"valid_matters":  [7, 6, 9],
				"default_matter": 7,       # Wood Hard
				"contact_area":   0.002,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.035,
			},
			"coating": {
				"role":           PartRole.COATING,
				"volume":         0.00003,
				"valid_matters":  [8, 12, 14, 15, 16, 17, 19, 20],
				"optional":       true,
			}
		}
	},
	Type.SPEAR: {
		"base_name":     "Spear",
		"valid_matters": [
			9,   # MaterialTypes.Type.STEEL
			10,  # MaterialTypes.Type.OBSIDIAN
			0,   # MaterialTypes.Type.STONE
			7,   # MaterialTypes.Type.WOOD_HARD
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"head": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0003,  # 0.3 liters tip
				"valid_matters":  [9, 10, 0, 7],
				"default_matter": 9,
				"contact_area":   0.00005, # needle point
				"form":           _ImpactTypes.Form.PIERCE,
				"sharpness":      1.8,
				"thickness":      0.01,
			},
			"shaft": {
				"role":           PartRole.HANDLE,
				"volume":         0.0018,  # 1.8 liters pole
				"valid_matters":  [7, 6, 9],
				"default_matter": 7,       # Wood Hard
				"contact_area":   0.003,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.03,
			},
			"coating": {
				"role":           PartRole.COATING,
				"volume":         0.00003,
				"valid_matters":  [8, 12, 14, 15, 16, 17, 19, 20],
				"optional":       true,
			},
			"payload": {
				"role":           PartRole.PAYLOAD,
				"volume":         0.0001,
				"valid_matters":  [14, 16, 17, 18],
				"optional":       true,
			}
		}
	},
	Type.WARHAMMER: {
		"base_name":     "Warhammer",
		"valid_matters": [
			9,   # MaterialTypes.Type.STEEL
			0,   # MaterialTypes.Type.STONE
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"head": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0016,  # 1.6 liters heavy head
				"valid_matters":  [9, 0],
				"default_matter": 9,
				"contact_area":   0.006,  # broad face
				"form":           _ImpactTypes.Form.BLUNT,
				"alt_form":       _ImpactTypes.Form.CRUSH,
				"sharpness":      0.8,
				"thickness":      0.07,
			},
			"shaft": {
				"role":           PartRole.HANDLE,
				"volume":         0.0012,
				"valid_matters":  [7, 9],
				"default_matter": 7,
				"contact_area":   0.003,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.035,
			},
			"payload": {
				"role":           PartRole.PAYLOAD,
				"volume":         0.0002,  # 0.2 liters explosive chamber
				"valid_matters":  [14, 16, 17, 18],
				"optional":       true,
			},
			"coating": {
				"role":           PartRole.COATING,
				"volume":         0.00005,
				"valid_matters":  [8, 12, 14, 15, 16, 17, 19, 20],
				"optional":       true,
			}
		}
	},
	Type.PICKAXE: {
		"base_name":     "Pickaxe",
		"valid_matters": [
			9,   # MaterialTypes.Type.STEEL
			0,   # MaterialTypes.Type.STONE
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"head": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0010,
				"valid_matters":  [9, 0],
				"default_matter": 9,
				"contact_area":   0.00008, # pick point
				"form":           _ImpactTypes.Form.PIERCE,
				"sharpness":      1.4,
				"thickness":      0.025,
			},
			"shaft": {
				"role":           PartRole.HANDLE,
				"volume":         0.0012,
				"valid_matters":  [7, 6],
				"default_matter": 7,
				"contact_area":   0.003,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.035,
			},
			"coating": {
				"role":           PartRole.COATING,
				"volume":         0.00003,
				"valid_matters":  [8, 12, 14, 15, 16, 17, 19, 20],
				"optional":       true,
			}
		}
	},
	Type.TORCH: {
		"base_name":     "Torch",
		"valid_matters": [
			5,   # MaterialTypes.Type.KINDLING
			20,  # MaterialTypes.Type.ORGANIC
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"wrapping": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.0002,
				"valid_matters":  [5, 20],
				"default_matter": 5,
				"contact_area":   0.002,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.02,
			},
			"shaft": {
				"role":           PartRole.HANDLE,
				"volume":         0.0008,
				"valid_matters":  [7, 6],
				"default_matter": 6,
				"contact_area":   0.002,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.025,
			}
		}
	},
	Type.DAGGER: {
		"base_name":     "Dagger",
		"valid_matters": [
			9,   # MaterialTypes.Type.STEEL
			0,   # MaterialTypes.Type.STONE
			10,  # MaterialTypes.Type.OBSIDIAN
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"blade": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.00015,  # 0.15 liters
				"valid_matters":  [9, 0, 10, 7],
				"default_matter": 9,
				"contact_area":   0.00004,  # ultra-fine point/edge
				"form":           _ImpactTypes.Form.PIERCE,
				"alt_form":       _ImpactTypes.Form.SLASH,
				"sharpness":      1.6,
				"thickness":      0.008,
			},
			"hilt": {
				"role":           PartRole.HANDLE,
				"volume":         0.0001,
				"valid_matters":  [7, 6, 9],
				"default_matter": 7,
				"contact_area":   0.001,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.02,
			},
			"coating": {
				"role":           PartRole.COATING,
				"volume":         0.00002,
				"valid_matters":  [8, 12, 14, 15, 16, 17, 19, 20],
				"optional":       true,
			},
			"payload": {
				"role":           PartRole.PAYLOAD,
				"volume":         0.00005,
				"valid_matters":  [14, 16, 17, 18],
				"optional":       true,
			}
		}
	},
	Type.LIMB: {
		"base_name":     "Limb",
		"valid_matters": [
			12,  # MaterialTypes.Type.RAW_MEAT
			21,  # MaterialTypes.Type.BONE
			20,  # MaterialTypes.Type.ORGANIC
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"flesh": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.005,
				"valid_matters":  [12, 20],
				"default_matter": 12,
				"contact_area":   0.02,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.2,
				"thickness":      0.05,
			},
			"bone": {
				"role":           PartRole.HANDLE,
				"volume":         0.002,
				"valid_matters":  [21],
				"default_matter": 21,
				"contact_area":   0.01,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.5,
				"thickness":      0.03,
			}
		}
	},
	Type.ORGAN: {
		"base_name":     "Organ",
		"valid_matters": [
			12,  # MaterialTypes.Type.RAW_MEAT
			20,  # MaterialTypes.Type.ORGANIC
		],
		"stackable":  false,
		"max_stack":  1,
		"parts": {
			"tissue": {
				"role":           PartRole.PRIMARY_CONTACT,
				"volume":         0.001,
				"valid_matters":  [12, 20],
				"default_matter": 12,
				"contact_area":   0.01,
				"form":           _ImpactTypes.Form.BLUNT,
				"sharpness":      0.1,
				"thickness":      0.03,
			}
		}
	},
}

static func get_data(item_type: int) -> Dictionary:
	return DATA.get(item_type, DATA[Type.GRASS])

## Returns the dictionary of parts defined for this archetype mold.
static func get_parts_data(item_type: int) -> Dictionary:
	return get_data(item_type).get("parts", {})

## Returns the name of the primary contact part (e.g. "blade", "head", "main").
static func get_primary_part_name(item_type: int) -> String:
	var parts: Dictionary = get_parts_data(item_type)
	for part_name: String in parts:
		if parts[part_name].get("role", PartRole.PRIMARY_CONTACT) == PartRole.PRIMARY_CONTACT:
			return part_name
	if not parts.is_empty():
		return parts.keys()[0]
	return "main"

## True when the given material_type is a valid composition for this archetype.
static func is_valid_combination(item_type: int, material_type: int) -> bool:
	var root_valid: Array = get_data(item_type).get("valid_matters", [])
	if material_type in root_valid:
		return true
	var primary_name: String = get_primary_part_name(item_type)
	var parts: Dictionary = get_parts_data(item_type)
	if parts.has(primary_name):
		return material_type in parts[primary_name].get("valid_matters", [])
	return false

## True when all specified parts exist and have valid materials.
static func is_valid_composite(item_type: int, parts_materials: Dictionary) -> bool:
	var mold_parts: Dictionary = get_parts_data(item_type)
	if mold_parts.is_empty():
		return false
	for part_name: String in parts_materials:
		if not mold_parts.has(part_name):
			return false
		var mat_type: int = parts_materials[part_name]
		var valid_list: Array = mold_parts[part_name].get("valid_matters", [])
		if not valid_list.is_empty() and not mat_type in valid_list:
			return false
	return true

## Compose the display name from material + archetype.
## E.g. ORGANIC (20) + GRASS (0) → "Organic Grass"
static func build_name(item_type: int, material_type: int) -> String:
	var mat_name: String = _MaterialTypes.get_display_name(material_type)
	var base:     String = get_data(item_type).get("base_name", "Item")
	return mat_name + " " + base

## Compose rich display name for a composite item.
## E.g. {"blade": STEEL, "hilt": WOOD_HARD} → "Steel Sword (Hard Wood Hilt)"
## E.g. {"head": STEEL, "shaft": STEEL, "payload": GREEK_FIRE} -> "Blasting Steel Warhammer"
## E.g. {"head": OBSIDIAN, "shaft": WOOD_HARD, "coating": ECTOPLASM} -> "Venomous Obsidian Spear (Hard Wood Shaft)"
## E.g. {"blade": STONE, "hilt": WOOD_SOFT, "coating": CHLORINE} -> "Caustic Stone Dagger (Soft Wood Hilt)"
static func build_composite_name(item_type: int, parts_materials: Dictionary) -> String:
	var base: String = get_data(item_type).get("base_name", "Item")
	var primary_name: String = get_primary_part_name(item_type)
	var primary_mat: int = parts_materials.get(primary_name, -1)
	
	if primary_mat == -1:
		var mold_parts: Dictionary = get_parts_data(item_type)
		primary_mat = mold_parts.get(primary_name, {}).get("default_matter", 0)

	var primary_mat_name: String = _MaterialTypes.get_display_name(primary_mat)

	# Check for emergent descriptive prefixes from coating, payload, or matter properties
	var prefix: String = ""
	for part_name: String in parts_materials:
		var p_mat: int = parts_materials[part_name]
		var p_data: Dictionary = _MaterialTypes.get_data(p_mat)
		
		# Caustic / acidic coating or material
		if (p_data.get("corrosiveness", 0.0) >= 0.50 or (p_data.get("acidity_ph", 7.0) as float) <= 3.5) and part_name == "coating":
			prefix = "Caustic "
			break
		# Explosive / combustible payload
		elif p_data.get("flammability", 0.0) >= 0.90 and part_name in ["payload", "cartridge"]:
			prefix = "Blasting "
			break
		# Toxic / venomous coating or material
		elif p_data.get("toxicity", 0.0) >= 0.40 and part_name == "coating":
			prefix = "Venomous "
			break
		# Hydrated plant with water material
		elif item_type == Type.GRASS and part_name == "water" and p_mat == _MaterialTypes.Type.WATER:
			prefix = "Fresh "
			break

	# Check secondary/handle parts
	var other_descriptors: Array[String] = []
	for part_name: String in parts_materials:
		if part_name == primary_name:
			continue
		# If coating/payload produced an emergent prefix, do not clutter with parenthetical description
		if prefix != "" and part_name in ["coating", "payload"]:
			continue
		if item_type == Type.GRASS and part_name == "water" and prefix == "Fresh ":
			continue
		var other_mat: int = parts_materials[part_name]
		if other_mat != primary_mat:
			var other_mat_name: String = _MaterialTypes.get_display_name(other_mat)
			if other_mat_name.to_lower() == part_name.to_lower():
				other_descriptors.append(other_mat_name)
			else:
				other_descriptors.append("%s %s" % [other_mat_name, part_name.capitalize()])

	var full_base: String = primary_mat_name + " " + base
	if prefix != "":
		full_base = prefix + full_base

	if other_descriptors.is_empty():
		return full_base
	return "%s (%s)" % [full_base, ", ".join(other_descriptors)]

## Builds ImpactParams for an attack or collision using this item entity.
## Combines the item's total mass and kinetic energy with the contact mold geometry.
static func build_impact_params(
	item_comp,
	matter_comp,
	velocity: Vector2,
	use_alt_form: bool = false
) -> _ImpactTypes.ImpactParams:
	var mold_parts: Dictionary = get_parts_data(item_comp.item_type)
	var prim_name: String = item_comp.primary_part if item_comp.primary_part != "" else get_primary_part_name(item_comp.item_type)
	var prim_part: Dictionary = mold_parts.get(prim_name, {})

	var mass: float = maxf(0.05, item_comp.total_mass)
	var speed: float = velocity.length()
	var energy: float = 0.5 * mass * speed * speed
	if energy <= 0.0 and speed > 0.0:
		energy = 10.0

	var params = _ImpactTypes.ImpactParams.new()
	params.mass = mass
	params.velocity = velocity
	params.kinetic_energy = maxf(0.1, energy)

	if use_alt_form and prim_part.has("alt_form"):
		params.form = prim_part.get("alt_form", _ImpactTypes.Form.BLUNT)
		params.contact_area = prim_part.get("contact_area", 0.001) * 0.3
	else:
		params.form = prim_part.get("form", _ImpactTypes.Form.BLUNT)
		params.contact_area = prim_part.get("contact_area", 0.001)

	# Sharpness scaled by material hardness (harder material maintains sharper edge)
	var base_sharpness: float = prim_part.get("sharpness", 1.0)
	var hardness_ratio: float = clampf(matter_comp.hardness / 5.0, 0.2, 2.0)
	params.sharpness = base_sharpness * hardness_ratio
	params.temperature_c = matter_comp.temperature_c

	return params




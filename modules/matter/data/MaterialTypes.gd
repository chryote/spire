## MaterialTypes.gd
## Static data table for all matter archetypes.
##
## DATA keys per material:
##   display_name     String human-readable name used by ItemTypes.build_name()
##   state            int    MatterComponent state enum (0=SOLID,1=LIQUID,2=GAS,3=COLLOID)
##   density          float  kg/m3
##   melting_point_c  float  degrees C — INF = does not melt
##   boiling_point_c  float  degrees C — INF = does not boil
##   ignition_temp_c  float  degrees C — INF = non-flammable
##   conductivity     float  heat transfer coefficient
##   specific_heat    float  J/kg
##   flammability     float  0.0–1.0
##   acidity_ph       float  0.0–14.0
##   corrosiveness    float  0.0–1.0
##   moisture         float  0.0–1.0
##   rot_rate         float  0.0–1.0
##   toxicity         float  0.0–1.0
##   hardness         float
##   yield_strength   float  MPa
##   elasticity       float  0.0–1.0
##   nutritional_value int   calories/kg — 0 for non-food materials
##
## TILE_MATERIAL_MAP  : TileTypes.Type int  → MaterialTypes.Type int
## VEG_MATERIAL_MAP   : VegetationTypes.Type int → MaterialTypes.Type int
class_name MaterialTypes
extends RefCounted

enum Type {
	STONE          = 0,
	GROUND         = 1,
	GRASS_TURF     = 2,
	DIRT           = 3,
	MUD            = 4,
	KINDLING       = 5,   ## dry grass, tumbleweed
	WOOD_SOFT      = 6,   ## shrubs, wildflowers
	WOOD_HARD      = 7,   ## pine, oak
	WATER          = 8,
	STEEL          = 9,
	OBSIDIAN       = 10,
	SILICA_AEROGEL = 11,
	RAW_MEAT       = 12,
	SPIDER_SILK    = 13,
	GREEK_FIRE     = 14,
	OOBLECK        = 15,
	CAVE_METHANE   = 16,
	CHLORINE       = 17,
	ICOSIDODECAHEDRON = 18,
	ECTOPLASM      = 19,
	ORGANIC        = 20,  ## generic living plant matter — grass, leaves, shoots
}

## Tile type int → material type int
## TileTypes.Type: GROUND=0, GRASS=1, DIRT=2, STONE=3, MUD=4
const TILE_MATERIAL_MAP: Dictionary = {
	0: Type.GROUND,
	1: Type.GRASS_TURF,
	2: Type.DIRT,
	3: Type.STONE,
	4: Type.MUD,
}

## Vegetation type int → material type int
## VegetationTypes.Type: GRASS_PATCH=0, TALL_GRASS=1, SHRUB=2, WILDFLOWER=3, PINE_TREE=4, OAK_TREE=5
const VEG_MATERIAL_MAP: Dictionary = {
	0: Type.KINDLING,    ## GRASS_PATCH
	1: Type.KINDLING,    ## TALL_GRASS
	2: Type.WOOD_SOFT,   ## SHRUB
	3: Type.WOOD_SOFT,   ## WILDFLOWER
	4: Type.WOOD_HARD,   ## PINE_TREE
	5: Type.WOOD_HARD,   ## OAK_TREE
}

## Set of material IDs that belong to vegetation (for revert detection).
const VEG_MATERIAL_IDS: Array = [Type.KINDLING, Type.WOOD_SOFT, Type.WOOD_HARD]

const DATA: Dictionary = {
	# -----------------------------------------------------------------------
	# Terrain-mapped materials
	# -----------------------------------------------------------------------
	Type.STONE: {
		"display_name": "Stone",
		"state": 0, "density": 2700.0,
		"melting_point_c": 1650.0, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 2.0, "specific_heat": 840.0,
		"flammability": 0.0, "acidity_ph": 7.5, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 7.0, "yield_strength": 200.0, "elasticity": 0.05,
		"nutritional_value": 0,
	},
	Type.GROUND: {
		"display_name": "Ground",
		"state": 0, "density": 1400.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 1.5, "specific_heat": 800.0,
		"flammability": 0.0, "acidity_ph": 6.8, "corrosiveness": 0.0,
		"moisture": 0.25, "rot_rate": 0.02, "toxicity": 0.0,
		"hardness": 2.5, "yield_strength": 20.0, "elasticity": 0.2,
		"nutritional_value": 0,
	},
	Type.GRASS_TURF: {
		"display_name": "Grass Turf",
		"state": 0, "density": 400.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 200.0, "conductivity": 0.5, "specific_heat": 900.0,
		"flammability": 0.55, "acidity_ph": 6.5, "corrosiveness": 0.0,
		"moisture": 0.40, "rot_rate": 0.15, "toxicity": 0.0,
		"hardness": 1.0, "yield_strength": 5.0, "elasticity": 0.7,
		"nutritional_value": 2,
	},
	Type.DIRT: {
		"display_name": "Dirt",
		"state": 0, "density": 1300.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 1.2, "specific_heat": 820.0,
		"flammability": 0.0, "acidity_ph": 6.5, "corrosiveness": 0.0,
		"moisture": 0.20, "rot_rate": 0.01, "toxicity": 0.0,
		"hardness": 2.0, "yield_strength": 15.0, "elasticity": 0.15,
		"nutritional_value": 0,
	},
	Type.MUD: {
		"display_name": "Mud",
		"state": 0, "density": 1800.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 1.0, "specific_heat": 1200.0,
		"flammability": 0.0, "acidity_ph": 6.8, "corrosiveness": 0.0,
		"moisture": 0.80, "rot_rate": 0.05, "toxicity": 0.0,
		"hardness": 1.5, "yield_strength": 8.0, "elasticity": 0.4,
		"nutritional_value": 0,
	},
	# -----------------------------------------------------------------------
	# Vegetation-mapped materials
	# -----------------------------------------------------------------------
	Type.KINDLING: {  ## dry grass / tumbleweed
		"display_name": "Kindling",
		"state": 0, "density": 80.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 155.0, "conductivity": 0.15, "specific_heat": 1300.0,
		"flammability": 0.85, "acidity_ph": 6.0, "corrosiveness": 0.0,
		"moisture": 0.30, "rot_rate": 0.40, "toxicity": 0.0,
		"hardness": 0.5, "yield_strength": 4.0, "elasticity": 0.6,
		"nutritional_value": 1,
	},
	Type.WOOD_SOFT: {  ## shrubs, wildflowers
		"display_name": "Soft Wood",
		"state": 0, "density": 280.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 190.0, "conductivity": 0.35, "specific_heat": 1700.0,
		"flammability": 0.65, "acidity_ph": 6.2, "corrosiveness": 0.0,
		"moisture": 0.42, "rot_rate": 0.25, "toxicity": 0.0,
		"hardness": 1.5, "yield_strength": 15.0, "elasticity": 0.5,
		"nutritional_value": 0,
	},
	Type.WOOD_HARD: {  ## pine, oak
		"display_name": "Hard Wood",
		"state": 0, "density": 620.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 245.0, "conductivity": 0.60, "specific_heat": 1700.0,
		"flammability": 0.52, "acidity_ph": 5.8, "corrosiveness": 0.0,
		"moisture": 0.46, "rot_rate": 0.08, "toxicity": 0.0,
		"hardness": 3.5, "yield_strength": 50.0, "elasticity": 0.4,
		"nutritional_value": 0,
	},
	# -----------------------------------------------------------------------
	# Other archetypes (metals, liquids, gases, exotic)
	# -----------------------------------------------------------------------
	Type.WATER: {
		"display_name": "Water",
		"state": 1, "density": 1000.0,
		"melting_point_c": 0.0, "boiling_point_c": 100.0,
		"ignition_temp_c": INF, "conductivity": 0.6, "specific_heat": 4184.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 1.0, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 0.0, "yield_strength": 0.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.STEEL: {
		"display_name": "Steel",
		"state": 0, "density": 7850.0,
		"melting_point_c": 1500.0, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 45.0, "specific_heat": 490.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 6.5, "yield_strength": 850.0, "elasticity": 0.3,
		"nutritional_value": 0,
	},
	Type.OBSIDIAN: {
		"display_name": "Obsidian",
		"state": 0, "density": 2500.0,
		"melting_point_c": 1000.0, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 1.2, "specific_heat": 840.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 5.5, "yield_strength": 40.0, "elasticity": 0.01,
		"nutritional_value": 0,
	},
	Type.SILICA_AEROGEL: {
		"display_name": "Silica Aerogel",
		"state": 0, "density": 1.5,
		"melting_point_c": 1200.0, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 0.01, "specific_heat": 1000.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 1.0, "yield_strength": 0.1, "elasticity": 0.1,
		"nutritional_value": 0,
	},
	Type.RAW_MEAT: {
		"display_name": "Raw Meat",
		"state": 0, "density": 1050.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 0.5, "specific_heat": 3500.0,
		"flammability": 0.0, "acidity_ph": 5.5, "corrosiveness": 0.0,
		"moisture": 0.75, "rot_rate": 0.50, "toxicity": 0.2,
		"hardness": 1.5, "yield_strength": 10.0, "elasticity": 0.8,
		"nutritional_value": 250,
	},
	Type.SPIDER_SILK: {
		"display_name": "Spider Silk",
		"state": 0, "density": 1300.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 280.0, "conductivity": 0.3, "specific_heat": 1500.0,
		"flammability": 0.2, "acidity_ph": 6.5, "corrosiveness": 0.0,
		"moisture": 0.10, "rot_rate": 0.02, "toxicity": 0.0,
		"hardness": 2.0, "yield_strength": 1100.0, "elasticity": 0.9,
		"nutritional_value": 0,
	},
	Type.GREEK_FIRE: {
		"display_name": "Greek Fire",
		"state": 1, "density": 800.0,
		"melting_point_c": INF, "boiling_point_c": 300.0,
		"ignition_temp_c": 40.0, "conductivity": 0.2, "specific_heat": 2000.0,
		"flammability": 1.0, "acidity_ph": 5.0, "corrosiveness": 0.3,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.4,
		"hardness": 0.0, "yield_strength": 0.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.OOBLECK: {
		"display_name": "Oobleck",
		"state": 1, "density": 1100.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 0.4, "specific_heat": 3000.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.5, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 0.0, "yield_strength": 0.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.CAVE_METHANE: {
		"display_name": "Cave Methane",
		"state": 2, "density": 0.65,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 500.0, "conductivity": 0.03, "specific_heat": 2200.0,
		"flammability": 0.95, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.50,
		"hardness": 0.0, "yield_strength": 0.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.CHLORINE: {
		"display_name": "Chlorine",
		"state": 2, "density": 3.2,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 0.01, "specific_heat": 480.0,
		"flammability": 0.0, "acidity_ph": 2.0, "corrosiveness": 0.8,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 1.0,
		"hardness": 0.0, "yield_strength": 0.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.ICOSIDODECAHEDRON: {
		"display_name": "Icosidodecahedron",
		"state": 0, "density": 3500.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 80.0, "conductivity": 0.5, "specific_heat": 700.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 0.0, "toxicity": 0.0,
		"hardness": 9.0, "yield_strength": 10.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.ECTOPLASM: {
		"display_name": "Ectoplasm",
		"state": 3, "density": 0.1,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": INF, "conductivity": 0.0, "specific_heat": -500.0,
		"flammability": 0.0, "acidity_ph": 7.0, "corrosiveness": 0.0,
		"moisture": 0.0, "rot_rate": 1.0, "toxicity": 0.8,
		"hardness": 0.0, "yield_strength": 0.0, "elasticity": 0.0,
		"nutritional_value": 0,
	},
	Type.ORGANIC: {  ## generic living plant matter — grass, leaves, shoots
		"display_name": "Organic",
		"state": 0, "density": 200.0,
		"melting_point_c": INF, "boiling_point_c": INF,
		"ignition_temp_c": 220.0, "conductivity": 0.3, "specific_heat": 1800.0,
		"flammability": 0.60, "acidity_ph": 6.0, "corrosiveness": 0.0,
		"moisture": 0.55, "rot_rate": 0.45, "toxicity": 0.0,
		"hardness": 0.5, "yield_strength": 3.0, "elasticity": 0.7,
		"nutritional_value": 8,
	},
}

static func get_data(material_type: int) -> Dictionary:
	return DATA.get(material_type, DATA[Type.GROUND])

static func get_display_name(material_type: int) -> String:
	return DATA.get(material_type, DATA[Type.GROUND]).get("display_name", "Unknown")

## Populates a MatterComponent instance with the archetypal properties of material_type.
static func apply_to(matter, material_type: int) -> void:
	var d: Dictionary = get_data(material_type)
	matter.material_id     = material_type
	matter.state           = d.get("state",           0) as int
	matter.density         = d.get("density",         1000.0) as float
	matter.melting_point_c = d.get("melting_point_c", INF) as float
	matter.boiling_point_c = d.get("boiling_point_c", INF) as float
	matter.ignition_temp_c = d.get("ignition_temp_c", INF) as float
	matter.conductivity    = d.get("conductivity",    1.0) as float
	matter.specific_heat   = d.get("specific_heat",   1000.0) as float
	matter.flammability    = d.get("flammability",    0.0) as float
	matter.acidity_ph      = d.get("acidity_ph",      7.0) as float
	matter.corrosiveness   = d.get("corrosiveness",   0.0) as float
	matter.moisture        = d.get("moisture",        0.0) as float
	matter.rot_rate        = d.get("rot_rate",        0.0) as float
	matter.toxicity        = d.get("toxicity",        0.0) as float
	matter.hardness        = d.get("hardness",        5.0) as float
	matter.yield_strength  = d.get("yield_strength",  100.0) as float
	matter.elasticity      = d.get("elasticity",      0.3) as float


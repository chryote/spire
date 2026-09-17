## VegetationTypes.gd
## Enum and data tables for all vegetation species.
##
## Data keys per species:
##   growth_glyphs    Array[String]  — glyph per growth stage (0–3)
##   sway_glyphs      Array[String]  — glyph shown during wind sway peak
##   sway_factor      float          — 0.0 (no sway) → 1.0 (full sway)
##   fg_colors        Array[Color]   — foreground color per stage
##   bg_color         Color          — background cell color
##   spawn_biomes     Array[int]     — BiomeTypes.Type int values
##   min_moisture     float          — moisture threshold for spawning
##   spawn_chance     float          — 0.0–1.0 probability per eligible tile
##   ticks_per_stage  int            — ticks to advance one growth stage
##   spread_chance    float          — per-tick chance to attempt spreading
##   spread_radius    int            — max tile offset for a spread attempt
##   spread_tiles     Array[int]     — TileTypes.Type ints that can receive this plant
##   z_layer          int            — render layer (trees = 1, ground cover = 0)
##   initial_stage_max int           — max starting growth stage at spawn time
##   initial_age_max  int            — max starting age (ticks) at spawn time
##
## Biome int constants (BiomeTypes.Type): PLAINS=0, FOREST_EDGE=1, WETLAND=2, BARREN=3
## Tile int constants  (TileTypes.Type):  GROUND=0, GRASS=1, DIRT=2, STONE=3, MUD=4
class_name VegetationTypes
extends RefCounted

enum Type {
	GRASS_PATCH  = 0,
	TALL_GRASS   = 1,
	SHRUB        = 2,
	WILDFLOWER   = 3,
	PINE_TREE    = 4,
	OAK_TREE     = 5,
}

const DATA: Dictionary = {
	# -----------------------------------------------------------------------
	# Ground cover
	# -----------------------------------------------------------------------
	Type.GRASS_PATCH: {
		"growth_glyphs":   [",",  ".",  "'",  "\""],
		"sway_glyphs":     ["'",  "`",  "`",  "'"],   # bent by breeze
		"sway_factor":     1.0,
		"fg_colors": [
			Color(0.20, 0.55, 0.10),
			Color(0.25, 0.68, 0.12),
			Color(0.28, 0.78, 0.14),
			Color(0.32, 0.88, 0.16),
		],
		"bg_color":         Color(0.03, 0.08, 0.02),
		"spawn_biomes":     [0, 1],         # PLAINS, FOREST_EDGE
		"min_moisture":     0.28,
		"spawn_chance":     0.62,
		"ticks_per_stage":  40,
		"spread_chance":    0.04,
		"spread_radius":    2,
		"spread_tiles":     [1],            # GRASS only
		"z_layer":          0,
		"initial_stage_max": 2,
		"initial_age_max":   60,
	},
	Type.TALL_GRASS: {
		"growth_glyphs":   ["'",  "|",  "\"", "!"],
		"sway_glyphs":     ["/",  "/",  "'",  "|"],   # bends noticeably
		"sway_factor":     0.90,
		"fg_colors": [
			Color(0.18, 0.58, 0.10),
			Color(0.22, 0.72, 0.12),
			Color(0.26, 0.82, 0.14),
			Color(0.28, 0.92, 0.15),
		],
		"bg_color":         Color(0.03, 0.09, 0.02),
		"spawn_biomes":     [0, 1],         # PLAINS, FOREST_EDGE
		"min_moisture":     0.42,
		"spawn_chance":     0.22,
		"ticks_per_stage":  60,
		"spread_chance":    0.015,
		"spread_radius":    2,
		"spread_tiles":     [1],            # GRASS only
		"z_layer":          0,
		"initial_stage_max": 2,
		"initial_age_max":   60,
	},
	Type.SHRUB: {
		"growth_glyphs":   [".",  ";",  "*",  "%"],
		"sway_glyphs":     [".",  ";",  ";",  "*"],   # barely moves (woody)
		"sway_factor":     0.45,
		"fg_colors": [
			Color(0.14, 0.42, 0.08),
			Color(0.17, 0.54, 0.10),
			Color(0.19, 0.60, 0.11),
			Color(0.22, 0.66, 0.13),
		],
		"bg_color":         Color(0.03, 0.07, 0.02),
		"spawn_biomes":     [1],            # FOREST_EDGE only
		"min_moisture":     0.46,
		"spawn_chance":     0.12,
		"ticks_per_stage":  100,
		"spread_chance":    0.005,
		"spread_radius":    1,
		"spread_tiles":     [1],            # GRASS only
		"z_layer":          0,
		"initial_stage_max": 2,
		"initial_age_max":   60,
	},
	Type.WILDFLOWER: {
		"growth_glyphs":   [".",  "^",  "*",  "@"],
		"sway_glyphs":     [".",  "~",  "~",  "*"],   # petals flutter
		"sway_factor":     0.85,
		"fg_colors": [
			Color(0.70, 0.60, 0.20),
			Color(0.90, 0.40, 0.50),
			Color(0.95, 0.45, 0.55),
			Color(1.00, 0.52, 0.62),
		],
		"bg_color":         Color(0.04, 0.08, 0.02),
		"spawn_biomes":     [0],            # PLAINS only
		"min_moisture":     0.33,
		"spawn_chance":     0.07,
		"ticks_per_stage":  50,
		"spread_chance":    0.010,
		"spread_radius":    3,
		"spread_tiles":     [1],            # GRASS only
		"z_layer":          0,
		"initial_stage_max": 2,
		"initial_age_max":   60,
	},
	# -----------------------------------------------------------------------
	# Trees — seeded first, high z_layer, very slow growth
	# -----------------------------------------------------------------------
	Type.PINE_TREE: {
		"growth_glyphs":   [".",  "|",  "T",  "T"],
		"sway_glyphs":     [".",  "/",  "T",  "T"],   # crown barely moves
		"sway_factor":     0.20,                        # stiff trunk
		"fg_colors": [
			Color(0.12, 0.38, 0.08),
			Color(0.14, 0.46, 0.09),
			Color(0.16, 0.52, 0.10),
			Color(0.18, 0.58, 0.11),
		],
		"bg_color":         Color(0.03, 0.05, 0.01),
		"spawn_biomes":     [1],            # FOREST_EDGE only
		"min_moisture":     0.50,
		"spawn_chance":     0.10,
		"ticks_per_stage":  200,
		"spread_chance":    0.002,
		"spread_radius":    4,
		"spread_tiles":     [0, 1, 2],      # GROUND, GRASS, DIRT
		"z_layer":          1,
		"initial_stage_max": 1,
		"initial_age_max":   40,
	},
	Type.OAK_TREE: {
		"growth_glyphs":   [".",  "t",  "T",  "Y"],
		"sway_glyphs":     [".",  "/",  "T",  "Y"],   # canopy sways slightly
		"sway_factor":     0.28,
		"fg_colors": [
			Color(0.18, 0.50, 0.10),
			Color(0.22, 0.58, 0.12),
			Color(0.27, 0.65, 0.14),
			Color(0.32, 0.72, 0.16),
		],
		"bg_color":         Color(0.03, 0.06, 0.01),
		"spawn_biomes":     [0, 1],         # PLAINS + FOREST_EDGE
		"min_moisture":     0.42,
		"spawn_chance":     0.06,
		"ticks_per_stage":  180,
		"spread_chance":    0.003,
		"spread_radius":    5,
		"spread_tiles":     [0, 1, 2],      # GROUND, GRASS, DIRT
		"z_layer":          1,
		"initial_stage_max": 1,
		"initial_age_max":   40,
	},
}

static func get_data(veg_type: int) -> Dictionary:
	return DATA.get(veg_type, DATA[Type.GRASS_PATCH])

static func get_glyph(veg_type: int, growth_stage: int) -> String:
	var glyphs: Array = get_data(veg_type).get("growth_glyphs", ["."])
	return glyphs[clampi(growth_stage, 0, glyphs.size() - 1)]

static func get_fg_color(veg_type: int, growth_stage: int) -> Color:
	var colors: Array = get_data(veg_type).get("fg_colors", [Color.GREEN])
	return colors[clampi(growth_stage, 0, colors.size() - 1)]

static func get_sway_glyph(veg_type: int, growth_stage: int) -> String:
	var sway: Array = get_data(veg_type).get("sway_glyphs", [])
	if sway.is_empty():
		return get_glyph(veg_type, growth_stage)
	return sway[clampi(growth_stage, 0, sway.size() - 1)]

static func is_tree(veg_type: int) -> bool:
	return veg_type == Type.PINE_TREE or veg_type == Type.OAK_TREE

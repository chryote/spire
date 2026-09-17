## TileTypes.gd
## Enum and metadata for terrain tile types.
## Adding a new tile: add an entry to Type and a matching entry in DATA.
class_name TileTypes
extends RefCounted

enum Type {
	GROUND,   ## Bare earth — transition zone
	GRASS,    ## Lush grass — primary vegetation host
	DIRT,     ## Dry/disturbed soil
	STONE,    ## Rocky elevation
	MUD,      ## Wet lowland
}

## Visual and semantic metadata per tile type.
## Keys: glyph (String), fg_color (Color), bg_color (Color)
const DATA: Dictionary = {
	Type.GROUND: {
		"glyph":    "\u00B7",                             # middle dot ·
		"fg_color": Color(0.46, 0.38, 0.26),
		"bg_color": Color(0.06, 0.05, 0.03),
	},
	Type.GRASS: {
		"glyph":    ".",
		"fg_color": Color(0.28, 0.70, 0.18),
		"bg_color": Color(0.03, 0.08, 0.02),
	},
	Type.DIRT: {
		"glyph":    ",",
		"fg_color": Color(0.52, 0.37, 0.18),
		"bg_color": Color(0.07, 0.05, 0.02),
	},
	Type.STONE: {
		"glyph":    "#",
		"fg_color": Color(0.55, 0.54, 0.52),
		"bg_color": Color(0.09, 0.09, 0.09),
	},
	Type.MUD: {
		"glyph":    "~",
		"fg_color": Color(0.42, 0.32, 0.16),
		"bg_color": Color(0.05, 0.04, 0.02),
	},
}

static func get_data(tile_type: int) -> Dictionary:
	return DATA.get(tile_type, DATA[Type.GROUND])

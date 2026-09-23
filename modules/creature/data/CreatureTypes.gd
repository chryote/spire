## CreatureTypes.gd
## Static archetype and species definitions for data-driven creatures.
## Defines anatomy blueprints (limbs, organs, blood), metabolic rates,
## locomotion speeds, and sensory parameters.
class_name CreatureTypes
extends RefCounted

const _MaterialTypes = preload("res://modules/matter/data/MaterialTypes.gd")
const _TraitTypes    = preload("res://modules/creature/data/TraitTypes.gd")

enum Type {
	GRAZER = 0,
	HARE   = 1,
	DEER   = 2,
}

enum GrowthStage {
	JUVENILE = 0,
	ADULT    = 1,
	ELDER    = 2,
}

const DATA: Dictionary = {
	Type.GRAZER: {
		"display_name":      "Grazer",
		"glyph":             "g",
		"fg_color":          Color(0.88, 0.78, 0.45, 1.0),
		"bg_color":          Color(0.0, 0.0, 0.0, 0.0),
		"base_mass":         22.0,       # kg
		"move_cooldown":     2,          # ticks between moves
		"metabolism_rate":   0.004,      # hunger increase per tick
		"thirst_rate":       0.003,      # thirst increase per tick
		"sight_radius":      10,         # tiles
		"stomach_capacity":  50.0,       # nutrition points
		"blood_volume":      2.2,        # liters
		"graze_amount":      1,          # growth stages or grass items per bite
		"graze_satiation":   0.25,       # hunger reduction per bite (0.0 to 1.0)
		"innate_traits":     [ _TraitTypes.Type.HARDY ],
		"trait_pool":        [ _TraitTypes.Type.GLUTTONOUS, _TraitTypes.Type.SLOTHFUL, _TraitTypes.Type.TIMID ],
		"growth_profile": {
			"stages": {
				GrowthStage.JUVENILE: {
					"name": "Juvenile",
					"min_age_ticks": 0,
					"body_scale": 0.40,
					"glyph": "g",
					"traits_gained": [ _TraitTypes.Type.TIMID ],
					"traits_lost": [ _TraitTypes.Type.HARDY ],
				},
				GrowthStage.ADULT: {
					"name": "Adult",
					"min_age_ticks": 2400,
					"body_scale": 1.00,
					"glyph": "G",
					"traits_gained": [ _TraitTypes.Type.HARDY ],
					"traits_lost": [ _TraitTypes.Type.TIMID ],
				},
				GrowthStage.ELDER: {
					"name": "Elder",
					"min_age_ticks": 28800,
					"body_scale": 0.90,
					"glyph": "G",
					"traits_gained": [ _TraitTypes.Type.FRAIL, _TraitTypes.Type.VIGILANT ],
					"traits_lost": [],
				}
			},
			"growth_rate_per_rare_tick": 0.015,
		},
		"anatomy": {
			"limbs": {
				"head":          { "volume": 0.0025, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.0 },
				"torso":         { "volume": 0.0120, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.0 },
				"left_foreleg":  { "volume": 0.0020, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"right_foreleg": { "volume": 0.0020, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"left_hindleg":  { "volume": 0.0025, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"right_hindleg": { "volume": 0.0025, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
			},
			"organs": {
				"heart":   { "volume": 0.0004, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
				"lungs":   { "volume": 0.0008, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
				"stomach": { "volume": 0.0010, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": false },
				"brain":   { "volume": 0.0003, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
			}
		}
	},
	Type.HARE: {
		"display_name":      "Hare",
		"glyph":             "r",
		"fg_color":          Color(0.80, 0.70, 0.55, 1.0),
		"bg_color":          Color(0.0, 0.0, 0.0, 0.0),
		"base_mass":         4.5,
		"move_cooldown":     1,          # very fast
		"metabolism_rate":   0.006,
		"thirst_rate":       0.004,
		"sight_radius":      8,
		"stomach_capacity":  20.0,
		"blood_volume":      0.5,
		"graze_amount":      1,
		"graze_satiation":   0.35,
		"innate_traits":     [ _TraitTypes.Type.TIMID, _TraitTypes.Type.FLEET_FOOTED ],
		"trait_pool":        [ _TraitTypes.Type.CURIOUS ],
		"growth_profile": {
			"stages": {
				GrowthStage.JUVENILE: {
					"name": "Leveret",
					"min_age_ticks": 0,
					"body_scale": 0.35,
					"glyph": "r",
					"traits_gained": [ _TraitTypes.Type.CURIOUS ],
					"traits_lost": [ _TraitTypes.Type.FLEET_FOOTED ],
				},
				GrowthStage.ADULT: {
					"name": "Adult",
					"min_age_ticks": 1200,
					"body_scale": 1.00,
					"glyph": "R",
					"traits_gained": [ _TraitTypes.Type.FLEET_FOOTED ],
					"traits_lost": [],
				},
				GrowthStage.ELDER: {
					"name": "Elder",
					"min_age_ticks": 14400,
					"body_scale": 0.85,
					"glyph": "R",
					"traits_gained": [ _TraitTypes.Type.VIGILANT ],
					"traits_lost": [ _TraitTypes.Type.FLEET_FOOTED ],
				}
			},
			"growth_rate_per_rare_tick": 0.025,
		},
		"anatomy": {
			"limbs": {
				"head":          { "volume": 0.0006, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.0 },
				"torso":         { "volume": 0.0030, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.0 },
				"left_foreleg":  { "volume": 0.0004, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"right_foreleg": { "volume": 0.0004, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"left_hindleg":  { "volume": 0.0006, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"right_hindleg": { "volume": 0.0006, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
			},
			"organs": {
				"heart":   { "volume": 0.0001, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
				"lungs":   { "volume": 0.0002, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
				"stomach": { "volume": 0.0003, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": false },
				"brain":   { "volume": 0.0001, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
			}
		}
	},
	Type.DEER: {
		"display_name":      "Deer",
		"glyph":             "d",
		"fg_color":          Color(0.85, 0.60, 0.35, 1.0),
		"bg_color":          Color(0.0, 0.0, 0.0, 0.0),
		"base_mass":         65.0,
		"move_cooldown":     2,
		"metabolism_rate":   0.003,
		"thirst_rate":       0.0025,
		"sight_radius":      12,
		"stomach_capacity":  120.0,
		"blood_volume":      5.5,
		"graze_amount":      1,
		"graze_satiation":   0.20,
		"innate_traits":     [ _TraitTypes.Type.CURIOUS, _TraitTypes.Type.FLEET_FOOTED ],
		"trait_pool":        [ _TraitTypes.Type.BOLD, _TraitTypes.Type.HARDY ],
		"growth_profile": {
			"stages": {
				GrowthStage.JUVENILE: {
					"name": "Fawn",
					"min_age_ticks": 0,
					"body_scale": 0.35,
					"glyph": "d",
					"traits_gained": [ _TraitTypes.Type.TIMID ],
					"traits_lost": [ _TraitTypes.Type.FLEET_FOOTED ],
				},
				GrowthStage.ADULT: {
					"name": "Adult",
					"min_age_ticks": 3600,
					"body_scale": 1.00,
					"glyph": "D",
					"traits_gained": [ _TraitTypes.Type.FLEET_FOOTED ],
					"traits_lost": [ _TraitTypes.Type.TIMID ],
				},
				GrowthStage.ELDER: {
					"name": "Elder",
					"min_age_ticks": 36000,
					"body_scale": 0.95,
					"glyph": "D",
					"traits_gained": [ _TraitTypes.Type.HARDY ],
					"traits_lost": [],
				}
			},
			"growth_rate_per_rare_tick": 0.010,
		},
		"anatomy": {
			"limbs": {
				"head":          { "volume": 0.006, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.0 },
				"torso":         { "volume": 0.035, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.0 },
				"left_foreleg":  { "volume": 0.005, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"right_foreleg": { "volume": 0.005, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"left_hindleg":  { "volume": 0.006, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
				"right_hindleg": { "volume": 0.006, "flesh": _MaterialTypes.Type.RAW_MEAT, "bone": _MaterialTypes.Type.BONE, "mobility": 0.25 },
			},
			"organs": {
				"heart":   { "volume": 0.0010, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
				"lungs":   { "volume": 0.0020, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
				"stomach": { "volume": 0.0030, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": false },
				"brain":   { "volume": 0.0008, "matter": _MaterialTypes.Type.RAW_MEAT, "vital": true },
			}
		}
	}
}

static func get_data(species_type: int) -> Dictionary:
	return DATA.get(species_type, DATA[Type.GRAZER])

static func get_growth_profile(species_type: int) -> Dictionary:
	var d: Dictionary = get_data(species_type)
	return d.get("growth_profile", {})

static func get_stage_name(stage: int) -> String:
	match stage:
		GrowthStage.JUVENILE: return "Juvenile"
		GrowthStage.ADULT:    return "Adult"
		GrowthStage.ELDER:    return "Elder"
		_:                    return "Unknown"

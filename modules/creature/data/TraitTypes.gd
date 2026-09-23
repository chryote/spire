## TraitTypes.gd
## Static definitions and metadata for data-driven creature traits.
## Categorizes traits into Genetic Profiles (innate, inheritable), Buffs (positive temporary states),
## and Debuffs (negative temporary states). Provides action utility weights and physiological modifiers.
class_name TraitTypes
extends RefCounted

const _MindEmbeddings = preload("res://modules/creature/data/MindEmbeddings.gd")

enum Category {	
	GENETIC = 0,
	BUFF    = 1,
	DEBUFF  = 2,
}

enum Type {
	# --- Genetic Profiles (0 - 99) ---
	TIMID        = 0,
	BOLD         = 1,
	GLUTTONOUS   = 2,
	SLOTHFUL     = 3,
	CURIOUS      = 4,
	FLEET_FOOTED = 5,
	HARDY        = 6,
	VIGILANT     = 7,
	TOUGH        = 8,
	FRAIL        = 9,

	# --- Buffs (100 - 199) ---
	WELL_FED        = 100,
	HYDRATED        = 101,
	RESTED          = 102,
	ADRENALINE_RUSH = 103,

	# --- Debuffs (200 - 299) ---
	STARVING   = 200,
	DEHYDRATED = 201,
	EXHAUSTED  = 202,
	PANICKED   = 203,
}

const DATA: Dictionary = {
	Type.TIMID: {
		"name": "Timid",
		"description": "Easily startled; flees at the slightest sign of danger.",
		"category": Category.GENETIC,
		"color": Color(0.70, 0.85, 1.0, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.FLEE: { "add": 0.05, "mult": 1.30 },
		},
		"stat_modifiers": {
			"hazard_sensitivity": 1.6,
			"sight_radius_mod": 2,
		}
	},
	Type.BOLD: {
		"name": "Bold",
		"description": "Courageous and steadfast; slow to panic and eager to explore.",
		"category": Category.GENETIC,
		"color": Color(1.0, 0.65, 0.40, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.FLEE:   { "add": -0.30, "mult": 0.60 },
			_MindEmbeddings.Action.WANDER: { "add": 0.15, "mult": 1.15 },
		},
		"stat_modifiers": {
			"hazard_sensitivity": 0.5,
		}
	},
	Type.GLUTTONOUS: {
		"name": "Gluttonous",
		"description": "Insatiable appetite; strongly prefers eating and digests rapidly.",
		"category": Category.GENETIC,
		"color": Color(0.55, 0.90, 0.55, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.GRAZE: { "add": 0.30, "mult": 1.35 },
		},
		"stat_modifiers": {
			"metabolism_mult": 1.35,
			"stomach_capacity_mult": 1.25,
		}
	},
	Type.SLOTHFUL: {
		"name": "Slothful",
		"description": "Lethargic demeanor; tires quickly and loves to rest.",
		"category": Category.GENETIC,
		"color": Color(0.75, 0.70, 0.85, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.REST: { "add": 0.30, "mult": 1.30 },
			_MindEmbeddings.Action.IDLE: { "add": 0.10, "mult": 1.20 },
		},
		"stat_modifiers": {
			"move_cooldown": 1,
			"fatigue_gain_mult": 1.40,
		}
	},
	Type.CURIOUS: {
		"name": "Curious",
		"description": "Naturally inquisitive; inclined to wander and investigate new surroundings.",
		"category": Category.GENETIC,
		"color": Color(0.95, 0.85, 0.45, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.WANDER: { "add": 0.35, "mult": 1.40 },
		},
		"stat_modifiers": {
			"sight_radius_mod": 1,
		}
	},
	Type.FLEET_FOOTED: {
		"name": "Fleet-Footed",
		"description": "Nimble and swift; covers ground rapidly with lower exertion.",
		"category": Category.GENETIC,
		"color": Color(0.45, 0.95, 0.90, 1.0),
		"action_weights": {},
		"stat_modifiers": {
			"move_cooldown": -1,
			"fatigue_gain_mult": 0.80,
		}
	},
	Type.HARDY: {
		"name": "Hardy",
		"description": "Robust constitution; resists starvation, dehydration, and blood loss.",
		"category": Category.GENETIC,
		"color": Color(0.85, 0.75, 0.60, 1.0),
		"action_weights": {},
		"stat_modifiers": {
			"metabolism_mult": 0.80,
			"thirst_mult": 0.80,
			"bleed_rate_mult": 0.70,
		}
	},
	Type.VIGILANT: {
		"name": "Vigilant",
		"description": "Extraordinary awareness; perceives hazards early and reacts decisively.",
		"category": Category.GENETIC,
		"color": Color(0.95, 0.70, 0.30, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.FLEE: { "add": 0.15, "mult": 1.20 },
		},
		"stat_modifiers": {
			"hazard_sensitivity": 1.4,
			"sight_radius_mod": 2,
		}
	},
	Type.TOUGH: {
		"name": "Tough",
		"description": "Battle-hardened resilience; reduced pain perception and greater kinetic fortitude.",
		"category": Category.GENETIC,
		"color": Color(0.80, 0.55, 0.40, 1.0),
		"action_weights": {},
		"stat_modifiers": {
			"bleed_rate_mult": 0.80,
			"pain_gain_mult": 0.70,
		}
	},
	Type.FRAIL: {
		"name": "Frail",
		"description": "Aging constitution; reduced mobility and slower stamina recovery.",
		"category": Category.GENETIC,
		"color": Color(0.60, 0.60, 0.65, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.REST: { "add": 0.20, "mult": 1.20 },
		},
		"stat_modifiers": {
			"move_cooldown": 1,
			"fatigue_gain_mult": 1.30,
		}
	},

	# --- Buffs ---
	Type.WELL_FED: {
		"name": "Well-Fed",
		"description": "Stomach is comfortably full; metabolism is sated and body heals gradually.",
		"category": Category.BUFF,
		"color": Color(0.40, 0.90, 0.40, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.GRAZE: { "add": -0.25, "mult": 0.50 },
		},
		"stat_modifiers": {
			"metabolism_mult": 0.60,
			"health_recovery": 0.005,
		}
	},
	Type.HYDRATED: {
		"name": "Hydrated",
		"description": "Thirst is quenched; muscles function smoothly.",
		"category": Category.BUFF,
		"color": Color(0.35, 0.75, 1.0, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.DRINK: { "add": -0.30, "mult": 0.40 },
		},
		"stat_modifiers": {
			"thirst_mult": 0.60,
		}
	},
	Type.RESTED: {
		"name": "Rested",
		"description": "Full of energy; movement is swift and fatigue accumulates slowly.",
		"category": Category.BUFF,
		"color": Color(0.90, 0.90, 0.40, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.REST: { "add": -0.20, "mult": 0.50 },
		},
		"stat_modifiers": {
			"fatigue_gain_mult": 0.70,
		}
	},
	Type.ADRENALINE_RUSH: {
		"name": "Adrenaline Rush",
		"description": "Flight-or-fight response activated; increases movement speed and numbs exhaustion.",
		"category": Category.BUFF,
		"color": Color(1.0, 0.30, 0.30, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.FLEE: { "add": 0.40, "mult": 1.50 },
		},
		"stat_modifiers": {
			"move_cooldown": -1,
			"fatigue_gain_mult": 0.0,
		}
	},

	# --- Debuffs ---
	Type.STARVING: {
		"name": "Starving",
		"description": "Severe lack of sustenance; eating takes supreme priority.",
		"category": Category.DEBUFF,
		"color": Color(0.95, 0.45, 0.20, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.GRAZE:  { "add": 0.50, "mult": 1.60 },
			_MindEmbeddings.Action.WANDER: { "add": -0.30, "mult": 0.30 },
		},
		"stat_modifiers": {
			"health_loss": 0.002,
		}
	},
	Type.DEHYDRATED: {
		"name": "Dehydrated",
		"description": "Critically parched; seeking hydration overrides normal tasks.",
		"category": Category.DEBUFF,
		"color": Color(0.80, 0.50, 0.30, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.DRINK:  { "add": 0.55, "mult": 1.60 },
			_MindEmbeddings.Action.WANDER: { "add": -0.30, "mult": 0.30 },
		},
		"stat_modifiers": {
			"move_cooldown": 1,
			"health_loss": 0.003,
		}
	},
	Type.EXHAUSTED: {
		"name": "Exhausted",
		"description": "Physical exhaustion; movement is sluggish and resting is imperative.",
		"category": Category.DEBUFF,
		"color": Color(0.65, 0.65, 0.65, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.REST:   { "add": 0.50, "mult": 1.70 },
			_MindEmbeddings.Action.WANDER: { "add": -0.40, "mult": 0.20 },
		},
		"stat_modifiers": {
			"move_cooldown": 2,
		}
	},
	Type.PANICKED: {
		"name": "Panicked",
		"description": "Terrorized by immediate threat; incapable of peaceful grazing or resting.",
		"category": Category.DEBUFF,
		"color": Color(1.0, 0.20, 0.50, 1.0),
		"action_weights": {
			_MindEmbeddings.Action.FLEE:   { "add": 0.60, "mult": 2.00 },
			_MindEmbeddings.Action.GRAZE:  { "add": -0.80, "mult": 0.00 },
			_MindEmbeddings.Action.DRINK:  { "add": -0.80, "mult": 0.00 },
			_MindEmbeddings.Action.REST:   { "add": -0.80, "mult": 0.00 },
		},
		"stat_modifiers": {
			"sight_radius_mod": -2,
		}
	},
}

static func get_data(trait_type: int) -> Dictionary:
	return DATA.get(trait_type, {})

static func get_category_name(category: int) -> String:
	match category:
		Category.GENETIC: return "Genetic"
		Category.BUFF:    return "Buff"
		Category.DEBUFF:  return "Debuff"
		_:                return "Unknown"

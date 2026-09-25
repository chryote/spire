## SocialTypes.gd
## Data definitions, relationship types, and sociality framework constants.
class_name SocialTypes
extends RefCounted

enum BondType {
	NONE         = 0,
	PAIR         = 1,
	PARENT_CHILD = 2,
	PACK_MATE    = 3,
}

## Default baseline social parameters for creature species archetypes.
const DEFAULT_SOCIAL_PROFILE: Dictionary = {
	"sociality":           0.50, # baseline drive to seek company (0.0 = solitary, 1.0 = obligate herd)
	"pair_bond_tendency":  0.30, # chance/strength of forming enduring mate bond (0.0 to 1.0)
	"monogamy_tendency":   0.50, # pair-bond fidelity / exclusivity (0.0 = promiscuous, 1.0 = strict lifetime fidelity)
	"kinship_tendency":    0.60, # affinity between parent and offspring (0.0 to 1.0)
	"social_radius":       12,   # maximum tile distance to sense and benefit from herd peers
	"comfort_dist_min":    2,    # minimum desired distance (tiles) to prevent overcrowding
	"comfort_dist_max":    6,    # maximum desired distance (tiles) before feeling separated
	"parental_duration":   2400, # duration in ticks that offspring strongly shadows mother
}

## Converts bond type to human-readable string.
static func get_bond_name(bond_type: int) -> String:
	match bond_type:
		BondType.PAIR:         return "Pair Bond"
		BondType.PARENT_CHILD: return "Parent-Child"
		BondType.PACK_MATE:    return "Pack Mate"
		_:                     return "None"

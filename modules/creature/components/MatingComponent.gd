## MatingComponent.gd
## Reproduction and mating status component for living creatures.
## Holds biological sex, female spawnrate and gestation data, preferred traits
## for mating partner evaluation, and active pregnancy/cooldown state.
class_name MatingComponent
extends Resource

const _CreatureTypes = preload("res://modules/creature/data/CreatureTypes.gd")

## Biological sex: CreatureTypes.Gender (0=FEMALE, 1=MALE).
var gender: int = _CreatureTypes.Gender.FEMALE

# ---------------------------------------------------------------------------
# Female Reproduction & Spawnrate Data
# ---------------------------------------------------------------------------
## Reproduction and fecundity multiplier for females (e.g. 1.0 = base, 2.5 = high).
## Determines litter size scaling upon giving birth. (0.0 for males).
var spawn_rate: float = 1.0

## Range of offspring per birth before spawn_rate multiplier.
var litter_size_min: int = 1
var litter_size_max: int = 2

## Gestation duration in simulation ticks required to give birth.
var gestation_duration: int = 600

## Current ticks elapsed in active pregnancy.
var gestation_ticks: int = 0

## Whether female is currently pregnant.
var is_pregnant: bool = false

## Refractory ticks remaining before this creature can mate again.
var mating_cooldown_ticks: int = 0

# ---------------------------------------------------------------------------
# Trait Matching & Partner Preference
# ---------------------------------------------------------------------------
## List of genetic trait IDs (TraitTypes.Type) preferred in a mating partner.
var preferred_traits: Array[int] = []

## Minimum compatibility / preference score required to accept a partner [0.0, 1.0].
var preference_threshold: float = 0.20

# ---------------------------------------------------------------------------
# Lineage & Paternity (recorded upon successful conception)
# ---------------------------------------------------------------------------
var partner_father_eid: int = -1
var partner_father_species: int = 0
var partner_father_traits: Array[int] = []

# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
var total_litters_produced: int = 0
var total_offspring_spawned: int = 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func is_female() -> bool:
	return gender == _CreatureTypes.Gender.FEMALE

func is_male() -> bool:
	return gender == _CreatureTypes.Gender.MALE

func is_ready_to_mate() -> bool:
	if mating_cooldown_ticks > 0:
		return false
	if is_female() and is_pregnant:
		return false
	return true

func get_pregnancy_progress() -> float:
	if not is_pregnant or gestation_duration <= 0:
		return 0.0
	return clampf(float(gestation_ticks) / float(gestation_duration), 0.0, 1.0)

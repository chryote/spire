## GrowthComponent.gd
## Holds creature life stage (Juvenile, Adult, Elder), maturation progress,
## body scale factor, and achieved experiential conditioning milestones.
class_name CreatureGrowthComponent
extends Resource

const _CreatureTypes = preload("res://modules/creature/data/CreatureTypes.gd")

## Current life stage from CreatureTypes.GrowthStage.
var current_stage: int = _CreatureTypes.GrowthStage.ADULT

## Progress through current life stage [0.0, 1.0].
var growth_progress: float = 0.0

## Current anatomical body scale relative to species baseline (e.g. 0.40 for juvenile, 1.00 for adult).
var current_scale: float = 1.0

## Unscaled species baseline physical metrics.
var base_mass: float = 20.0
var base_blood_volume: float = 2.5
var base_stomach_capacity: float = 50.0

## Flag indicating severe malnutrition has temporarily halted growth.
var is_stunted: bool = false

## Set of recorded experiential milestones to prevent duplicate trait awards.
var achieved_milestones: Array[StringName] = []

func has_milestone(milestone_name: StringName) -> bool:
	return achieved_milestones.has(milestone_name)

func record_milestone(milestone_name: StringName) -> void:
	if not achieved_milestones.has(milestone_name):
		achieved_milestones.append(milestone_name)

func get_stage_name() -> String:
	return _CreatureTypes.get_stage_name(current_stage)

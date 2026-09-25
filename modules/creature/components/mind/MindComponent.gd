## MindComponent.gd
## Holds biological imperative drives as a normalized state-space vector embedding
## and caches the latest Utility AI decision and environmental perception.
class_name MindComponent
extends Resource

const _MindEmbeddings = preload("res://modules/creature/data/MindEmbeddings.gd")

## 9-dimensional normalized state vector representing biological imperatives.
## Indices defined in MindEmbeddings.Drive.
var drives: PackedFloat32Array = PackedFloat32Array()

## Current selected action candidate (MindEmbeddings.Action).
var current_action: int = _MindEmbeddings.Action.IDLE

## Evaluated utility scores per action: { int(Action) -> float }
var action_utilities: Dictionary = {}

## Cached environmental signals sampled at the creature's current tile.
var perceived_signals: Dictionary = {}

func _init() -> void:
	drives.resize(_MindEmbeddings.DIMENSIONS)
	drives.fill(0.0)
	# Initial comfortable baseline
	drives[_MindEmbeddings.Drive.HUNGER]    = 0.2
	drives[_MindEmbeddings.Drive.THIRST]    = 0.1
	drives[_MindEmbeddings.Drive.CURIOSITY] = 0.5
	drives[_MindEmbeddings.Drive.COMFORT]   = 0.8
	drives[_MindEmbeddings.Drive.MATING]    = 0.3

## Convenience drive property accessors
var hunger: float:
	get: return drives[_MindEmbeddings.Drive.HUNGER] if drives.size() > 0 else 0.0
	set(v): if drives.size() > 0: drives[_MindEmbeddings.Drive.HUNGER] = clampf(v, 0.0, 1.0)

var thirst: float:
	get: return drives[_MindEmbeddings.Drive.THIRST] if drives.size() > 1 else 0.0
	set(v): if drives.size() > 1: drives[_MindEmbeddings.Drive.THIRST] = clampf(v, 0.0, 1.0)

var fear: float:
	get: return drives[_MindEmbeddings.Drive.FEAR] if drives.size() > 2 else 0.0
	set(v): if drives.size() > 2: drives[_MindEmbeddings.Drive.FEAR] = clampf(v, 0.0, 1.0)

var fatigue: float:
	get: return drives[_MindEmbeddings.Drive.FATIGUE] if drives.size() > 3 else 0.0
	set(v): if drives.size() > 3: drives[_MindEmbeddings.Drive.FATIGUE] = clampf(v, 0.0, 1.0)

var curiosity: float:
	get: return drives[_MindEmbeddings.Drive.CURIOSITY] if drives.size() > 4 else 0.0
	set(v): if drives.size() > 4: drives[_MindEmbeddings.Drive.CURIOSITY] = clampf(v, 0.0, 1.0)

var pain: float:
	get: return drives[_MindEmbeddings.Drive.PAIN] if drives.size() > 5 else 0.0
	set(v): if drives.size() > 5: drives[_MindEmbeddings.Drive.PAIN] = clampf(v, 0.0, 1.0)

var mating: float:
	get: return drives[_MindEmbeddings.Drive.MATING] if drives.size() > _MindEmbeddings.Drive.MATING else 0.0
	set(v): if drives.size() > _MindEmbeddings.Drive.MATING: drives[_MindEmbeddings.Drive.MATING] = clampf(v, 0.0, 1.0)


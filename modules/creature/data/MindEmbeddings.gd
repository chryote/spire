## MindEmbeddings.gd
## Mathematical state-space vector embeddings for Creature Utility AI.
## Maps biological imperatives (drives) and environmental perceptions into
## an 8-dimensional normalized embedding space for fast dot-product / cosine
## utility evaluation.
class_name MindEmbeddings
extends RefCounted

const DIMENSIONS: int = 8

enum Drive {
	HUNGER      = 0,
	THIRST      = 1,
	FEAR        = 2,
	FATIGUE     = 3,
	CURIOSITY   = 4,
	PAIN        = 5,
	COMFORT     = 6,
	SOCIABILITY = 7,
}

enum Action {
	IDLE   = 0,
	GRAZE  = 1,
	DRINK  = 2,
	FLEE   = 3,
	REST   = 4,
	WANDER = 5,
	ATTACK = 6,
}

## Action prototype vectors in R^8 representing optimal drive alignment.
## [HUNGER, THIRST, FEAR, FATIGUE, CURIOSITY, PAIN, COMFORT, SOCIABILITY]
const ACTION_PROTOTYPES: Dictionary = {
	Action.GRAZE:  [1.00, 0.10, 0.00, 0.00, 0.10, 0.00, 0.10, 0.00],
	Action.DRINK:  [0.10, 1.00, 0.00, 0.00, 0.10, 0.00, 0.10, 0.00],
	Action.FLEE:   [0.00, 0.00, 1.00, 0.00, 0.00, 0.80, 0.00, 0.00],
	Action.REST:   [0.05, 0.05, 0.00, 1.00, 0.00, 0.20, 0.50, 0.00],
	Action.WANDER: [0.20, 0.10, 0.00, 0.00, 0.90, 0.00, 0.20, 0.10],
	Action.IDLE:   [0.05, 0.05, 0.00, 0.10, 0.10, 0.00, 0.20, 0.00],
	Action.ATTACK: [0.30, 0.00, 0.35, 0.00, 0.10, 0.65, 0.00, 0.00],
}

## Create a blank zeroed embedding vector.
static func create_vector() -> PackedFloat32Array:
	var vec := PackedFloat32Array()
	vec.resize(DIMENSIONS)
	vec.fill(0.0)
	return vec

## Dot product of two R^8 vectors.
static func dot(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var sum: float = 0.0
	var n: int = mini(a.size(), b.size())
	for i in range(n):
		sum += a[i] * b[i]
	return sum

## Magnitude (L2 norm) of an R^8 vector.
static func norm(a: PackedFloat32Array) -> float:
	var sum_sq: float = 0.0
	for i in range(a.size()):
		sum_sq += a[i] * a[i]
	return sqrt(sum_sq)

## Cosine similarity between two vectors in [-1.0, 1.0].
static func cosine_similarity(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n_a: float = norm(a)
	var n_b: float = norm(b)
	if n_a < 0.0001 or n_b < 0.0001:
		return 0.0
	return dot(a, b) / (n_a * n_b)

## Evaluates utility score in [0.0, 1.0] for an action candidate given
## current drive vector and perceived affordances.
static func evaluate_utility(
	drives: PackedFloat32Array,
	perception: Dictionary,
	action: int
) -> float:
	var raw_proto = ACTION_PROTOTYPES.get(action, null)
	if raw_proto == null:
		return 0.0

	var proto := PackedFloat32Array()
	proto.resize(DIMENSIONS)
	for i in range(DIMENSIONS):
		proto[i] = raw_proto[i]

	# Base alignment via dot product
	var base_score: float = dot(drives, proto)

	# Modulate by environmental perception affordances
	match action:
		Action.FLEE:
			var hazard: float = perception.get(&"hazard", 0.0) as float
			var fear: float   = drives[Drive.FEAR]
			if hazard > 0.2 or fear > 0.35:
				return clampf(fear * 1.5 + hazard * 1.5, 0.0, 1.0)
			return 0.0

		Action.GRAZE:
			var food_avail: float = perception.get(&"food_plant", 0.0) as float
			var hunger: float     = drives[Drive.HUNGER]
			var thirst: float     = drives[Drive.THIRST] if drives.size() > Drive.THIRST else 0.0
			var hunger_curve: float = pow(hunger, 1.3)
			# Hunger strongly drives seeking food; thirst also provides secondary motivation
			var drive_factor: float = hunger_curve + pow(thirst, 1.5) * 0.20
			return clampf(drive_factor * (0.75 + food_avail * 0.45), 0.0, 1.0)

		Action.DRINK:
			var water_avail: float = perception.get(&"hydration", 0.0) as float
			var thirst: float      = drives[Drive.THIRST]
			var thirst_curve: float = pow(thirst, 1.3)
			return clampf(thirst_curve * (0.75 + water_avail * 0.45), 0.0, 1.0)

		Action.REST:
			var fatigue: float = drives[Drive.FATIGUE]
			var cover: float   = perception.get(&"cover", 0.0) as float
			return clampf(pow(fatigue, 1.5) * (0.8 + cover * 0.4), 0.0, 1.0)

		Action.WANDER:
			var curiosity: float = drives[Drive.CURIOSITY]
			var hunger: float    = drives[Drive.HUNGER]
			var fear: float      = drives[Drive.FEAR]
			# Wander when not hungry and not in danger
			var inhibition: float = maxf(hunger, fear)
			return clampf(curiosity * 0.4 * (1.0 - inhibition), 0.05, 0.6)

		Action.IDLE:
			return 0.08

		Action.ATTACK:
			var pain: float = drives[Drive.PAIN]
			var fear: float = drives[Drive.FEAR]
			var hazard: float = perception.get(&"hazard", 0.0) as float
			if pain > 0.3 or (fear > 0.5 and hazard > 0.4):
				return clampf(pain * 0.7 + fear * 0.5, 0.0, 1.0)
			return 0.0

	return clampf(base_score, 0.0, 1.0)

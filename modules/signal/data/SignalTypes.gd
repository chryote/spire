## SignalTypes.gd
## Standardized constants for signal channels and propagation behaviors.
class_name SignalTypes
extends RefCounted

## How a signal channel propagates across time and space.
enum PropagationType {
	## Snapshot refreshed from ECS components (fire, water, plants, terrain).
	STATIC_SNAPSHOT = 0,

	## Instant impulse (e.g. acoustic noise, shockwave) that is cleared at the end of each tick.
	TRANSIENT = 1,

	## Lingering signal (scents, smoke, pheromones) that decays exponentially and drifts with wind.
	DIFFUSE_DRIFT = 2,
}

# ---------------------------------------------------------------------------
# Standard Built-in Channel Names
# ---------------------------------------------------------------------------
## Danger level 0.0 (safe) to 1.0 (lethal fire, toxic gas, acid, extreme heat).
const HAZARD: StringName         = &"hazard"

## Clean drinkable water quality and volume 0.0 to 1.0.
const HYDRATION: StringName      = &"hydration"

## Grazing food quality for herbivores (living grass, shrubs, flowers) 0.0 to 1.0.
const FOOD_PLANT: StringName     = &"food_plant"

## Meat/carrion food quality for carnivores/scavengers 0.0 to 1.0.
const FOOD_MEAT: StringName      = &"food_meat"

## Foliage concealment level for stealth / hiding 0.0 to 1.0.
const COVER: StringName          = &"cover"

## Movement speed multiplier (1.0 = normal, <1.0 = mud/slowdown, 0.0 = impassable).
const TRAVERSABILITY: StringName = &"traversability"

## Acoustic noise level (footsteps, breaking branches, combustion crackle, cries).
const SOUND: StringName          = &"sound"

## Olfactory channels
const SCENT_PREDATOR: StringName = &"scent_predator"
const SCENT_PREY: StringName     = &"scent_prey"
const SCENT_BLOOD: StringName    = &"scent_blood"
const SCENT_SMOKE: StringName    = &"scent_smoke"

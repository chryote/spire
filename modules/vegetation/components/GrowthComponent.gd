## GrowthComponent.gd
## Controls how quickly vegetation matures and how aggressively it spreads.
## Initialised from VegetationTypes.DATA at spawn time.
class_name GrowthComponent
extends Resource

## Ticks required to advance one growth stage.
var ticks_per_stage: int = 40

## Probability per tick that this plant tries to spread to a neighbour (0.0–1.0).
var spread_chance: float = 0.03

## Maximum tile radius for a spread attempt.
var spread_radius: int = 2

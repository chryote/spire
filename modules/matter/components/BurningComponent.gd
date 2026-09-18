## BurningComponent.gd
## Marker + state component for entities that are currently on fire.
## Seeded ONLY by external game events (lightning, torches, debug key, etc.)
## CombustionSystem handles spread, fuel depletion, and burnout.
class_name BurningComponent
extends Resource

## How aggressively the fire burns (0.0–1.0). Drives heat output and spread.
var intensity: float = 1.0

## Remaining fuel (1.0 = full, 0.0 = burned out). Depletes each cycle.
var fuel: float = 1.0

## Degrees Celsius added to each adjacent tile per combustion cycle.
var heat_output: float = 25.0

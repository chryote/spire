## SignalEmitterComponent.gd
## ECS Component: marks an entity as an active continuous or pulsed signal emitter.
## Attached to actors (predator musks, herbivore scent trails), dynamic props (torches, campfires),
## or corpses to broadcast into any SignalGrid channel.
class_name SignalEmitterComponent
extends Resource

## The channel this entity writes to (e.g. SignalTypes.SCENT_PREDATOR, SignalTypes.HAZARD).
var channel: StringName = &""

## Emission intensity at center position (0.0 to 1.0).
var intensity: float = 0.5

## Radial splash radius in tiles (0 = only the occupant tile).
var radius: int = 0

## How frequently to emit in simulation ticks (1 = every tick, 5 = every 5 ticks).
var interval_ticks: int = 1

## Toggle emission on or off.
var enabled: bool = true

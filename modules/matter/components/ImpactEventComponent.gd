## ImpactEventComponent.gd
## Marker and event component for queued asynchronous collisions in the ECS.
## Attach this component to a striking entity (projectile, falling debris, creature claw)
## with target entity ID and impact parameters. ImpactSolverSystem processes it during tick().
class_name ImpactEventComponent
extends Resource

const _ImpactTypes = preload("res://modules/matter/data/ImpactTypes.gd")

## The target entity that is being struck.
var target_eid: int = -1

## Impact parameters (kinetic energy, contact area, velocity, form).
var params: _ImpactTypes.ImpactParams = null

## The resolved outcome populated after ImpactSolverSystem processes this event.
var result: _ImpactTypes.ImpactResult = null

## Whether the impact has been resolved.
var processed: bool = false

## If true, ImpactSolverSystem will automatically remove this component after processing.
var remove_on_resolve: bool = true

## PositionComponent.gd
## Spatial coordinates and movement timing for dynamic actors.
class_name PositionComponent
extends Resource

## Discrete grid position on the world map.
var position: Vector2i = Vector2i.ZERO

## Cardinal direction the actor is currently oriented towards.
var facing: Vector2i = Vector2i(1, 0)

## Remaining ticks before the creature can take another step.
var move_cooldown_ticks: int = 0

## Base ticks required between consecutive steps.
var base_move_interval: int = 2

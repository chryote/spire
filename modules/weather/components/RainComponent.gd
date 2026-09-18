## RainComponent.gd
## Marks a tile entity as currently receiving rainfall.
## Added and removed dynamically each tick by RainSystem.
## AsciiRenderSystem reads intensity to tint bg/fg colors blue-grey.
class_name RainComponent
extends Resource

## Rain intensity on this tile: 0.0 = dry, 1.0 = heavy downpour.
var intensity: float = 0.0


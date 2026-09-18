## FluidComponent.gd
## Represents fluid on a tile (water, Greek fire, melted material, etc.).
class_name FluidComponent
extends Resource

## 0.0–1.0 continuous volume.
var volume: float = 1.0

## Tracks MaterialTypes.Type int.
var material_id: int = 0

## True when no flow occurred last tick (settled fluid saves CPU).
var settled: bool = false

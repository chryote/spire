## GasComponent.gd
## Represents airborne gas or vapor over a tile.
class_name GasComponent
extends Resource

## 0.0–1.0 — decreases as gas disperses over time.
var concentration: float = 1.0

## Tracks MaterialTypes.Type int.
var material_id: int = 0

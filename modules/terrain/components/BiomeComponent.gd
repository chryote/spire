## BiomeComponent.gd
## Biome metadata for a terrain tile.
## Drives vegetation spawn probabilities and future weather/ecology systems.
class_name BiomeComponent
extends Resource

## One of BiomeTypes.Type.
var biome: int = 0        # BiomeTypes.Type.PLAINS

## Moisture level 0.0 (arid) → 1.0 (saturated).
var moisture: float = 0.5

## Temperature level 0.0 (freezing) → 1.0 (scorching).
var temperature: float = 0.5

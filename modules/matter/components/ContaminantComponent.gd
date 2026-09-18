## ContaminantComponent.gd
## Tracks environmental contamination (toxicity, corrosion, miasma) on a tile.
class_name ContaminantComponent
extends Resource

## Accumulated toxic dose on this tile.
var toxicity: float = 0.0

## Accumulated corrosive dose on this tile.
var corrosion: float = 0.0

## Which material caused this contamination (-1 = unspecified).
var source_mat_id: int = -1

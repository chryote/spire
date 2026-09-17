## TileComponent.gd
## Marks an entity as a world tile.  Every terrain cell has exactly one.
class_name TileComponent
extends Resource

## Grid position in tile coordinates.
var position: Vector2i = Vector2i.ZERO

## One of TileTypes.Type — determines base visuals and vegetation eligibility.
var tile_type: int = 0  # TileTypes.Type.GROUND

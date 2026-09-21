## ItemYieldComponent.gd
## Drives ongoing item production on a vegetation entity.
## Attach to any plant that should periodically generate a harvestable item
## on its tile's InventoryComponent.
##
## Decoupled from VegetationComponent — any entity can be a producer.
class_name ItemYieldComponent
extends Resource

## One of ItemTypes.Type — the base archetype to produce.
var item_type: int = 0       # ItemTypes.Type.GRASS

## One of MaterialTypes.Type — matter of the yielded item.
var material_type: int = 20  # MaterialTypes.Type.ORGANIC

## How many simulation ticks between each item deposit.
## Tune per-species in VegetationSpawnSystem.
var ticks_per_yield: int = 60

## Internal counter: ticks elapsed since the last deposit.
## Managed exclusively by VegetationYieldSystem.
var ticks_since_yield: int = 0

## Maximum items of this archetype this plant can have on the tile at once.
## Production pauses when the cap is reached. -1 = unlimited.
## Fallback when the item type is not defined in VegetationYieldSystem.MAX_YIELD_PER_TILE.
var max_yield: int = 5

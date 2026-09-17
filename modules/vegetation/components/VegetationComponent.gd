## VegetationComponent.gd
## Tags an entity as hosting vegetation.  Added on top of terrain tile entities.
## The AsciiRenderSystem prioritises this component's data over the base tile render.
class_name VegetationComponent
extends Resource

## One of VegetationTypes.Type.
var veg_type: int = 0        # VegetationTypes.Type.GRASS_PATCH

## Current visual maturity: 0 = seedling, 1 = young, 2 = established, 3 = mature.
var growth_stage: int = 0

## Accumulated simulation ticks since this plant appeared.
var age: float = 0.0

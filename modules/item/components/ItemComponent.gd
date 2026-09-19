## ItemComponent.gd
## Tags an entity as a world item.
## Holds what the item IS (archetype + matter) and its computed display name.
class_name ItemComponent
extends Resource

## One of ItemTypes.Type — the base item archetype.
var item_type: int = 0

## One of MaterialTypes.Type — the matter this item is made of.
var material_type: int = 0

## Computed at creation time: e.g. "Organic Grass".
## Never re-computed at runtime — set once by ItemFactory.
var display_name: String = ""

## Stack count — 1 for a single item, >1 for bundles.
var quantity: int = 1

## Entity ID of the container or tile currently holding this item (-1 = none / uncontained).
var container_id: int = -1


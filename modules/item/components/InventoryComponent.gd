## InventoryComponent.gd
## Generic item-bag component.  Can be attached to any entity:
##   - Tile entities       → items lying on the ground
##   - Actor entities      → carried inventory
##   - Container entities  → chests, barrels, sacks
##
## Items are stored as entity IDs referencing entities with ItemComponent.
class_name InventoryComponent
extends Resource

## Entity IDs of items currently held.
var items: Array[int] = []

## Maximum number of item stacks allowed (-1 = unlimited).
var capacity: int = -1

## Return true when another item can be added.
func has_space() -> bool:
	return capacity < 0 or items.size() < capacity

## Remove an item by entity ID.  Returns true on success, false if not found.
func remove_item(item_entity_id: int) -> bool:
	var idx: int = items.find(item_entity_id)
	if idx == -1:
		return false
	items.remove_at(idx)
	return true

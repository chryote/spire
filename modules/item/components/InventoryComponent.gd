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

# ---------------------------------------------------------------------------
# Cached Summary Flags for Spatial Perception / Signal System
# (Updated on item add/remove, NOT recomputed on every tick!)
# ---------------------------------------------------------------------------
var has_carnivore_food: bool = false
var max_calories: int = 0
var has_blood_scent: bool = false

## Return true when another item stack can be added.
func has_space() -> bool:
	return capacity < 0 or items.size() < capacity

## Find an existing item entity in this inventory that can accept incoming units.
## Returns entity_id, or -1 if no compatible stack has available capacity.
func find_stackable_item(reg, item_type: int, material_type: int, parts: Dictionary = {}) -> int:
	if reg == null:
		return -1
	for item_id: int in items:
		var item = reg.get_component(item_id, &"ItemComponent")
		if item != null and item.can_stack_with(item_type, material_type, parts):
			return item_id
	return -1

## Sum of all quantities for a specific archetype in this inventory.
func get_total_quantity_of_type(reg, item_type: int) -> int:
	if reg == null:
		return 0
	var total: int = 0
	for item_id: int in items:
		var item = reg.get_component(item_id, &"ItemComponent")
		if item != null and item.item_type == item_type:
			total += item.quantity
	return total

## Remove an item by entity ID. Returns true on success, false if not found.
func remove_item(item_entity_id: int) -> bool:
	var idx: int = items.find(item_entity_id)
	if idx == -1:
		return false
	items.remove_at(idx)
	return true

## Clears all held item IDs and resets cached flags, returning the list of entity IDs.
func clear_items() -> Array[int]:
	var old_items: Array[int] = items.duplicate()
	items.clear()
	has_carnivore_food = false
	max_calories = 0
	has_blood_scent = false
	return old_items

## Recalculates cached spatial perception flags for this inventory.
func update_cache(reg) -> void:
	has_carnivore_food = false
	max_calories = 0
	has_blood_scent = false
	if reg == null or items.is_empty():
		return

	var mat_types = preload("res://modules/matter/data/MaterialTypes.gd")
	for item_id: int in items:
		var item = reg.get_component(item_id, &"ItemComponent")
		if item == null:
			continue
		var mat_data: Dictionary = mat_types.get_data(item.material_type)
		var cal: int = mat_data.get("nutritional_value", 0) as int
		if cal > 0:
			has_carnivore_food = true
			if cal > max_calories:
				max_calories = cal
		if item.material_type == mat_types.Type.RAW_MEAT:
			has_blood_scent = true

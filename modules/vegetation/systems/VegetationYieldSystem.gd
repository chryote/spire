## VegetationYieldSystem.gd
## Priority 210 — runs every tick, after VegetationGrowthSystem (200).
##
## For each vegetation entity that has an ItemYieldComponent:
##   1. Advance ticks_since_yield.
##   2. When ticks_per_yield is reached, attempt to deposit one item on the tile.
##   3. Skip deposit if the tile's inventory already holds max_yield items of this type.
##
## Burning plants stop yielding (fire destroys the plant shortly after anyway).
class_name VegetationYieldSystem
extends "res://core/SystemBase.gd"

const _ItemYieldComponent  = preload("res://modules/item/components/ItemYieldComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")

func tick(_tick_number: int) -> void:
	var entities: Array = world.query() \
		.with_all([&"VegetationComponent", &"ItemYieldComponent", &"TileComponent"]) \
		.run()

	var reg = world.get_registry()

	for entity_id: int in entities:
		# Burning plants don't produce
		if reg.has(entity_id, &"BurningComponent"):
			continue

		var yield_comp = reg.get_component(entity_id, &"ItemYieldComponent")
		yield_comp.ticks_since_yield += 1

		if yield_comp.ticks_since_yield < yield_comp.ticks_per_yield:
			continue

		# Reset the counter before the deposit so a failed deposit still resets
		yield_comp.ticks_since_yield = 0

		# Tile's InventoryComponent is on the same entity (tile = vegetation host)
		var inv = reg.get_component(entity_id, &"InventoryComponent")
		if inv == null:
			continue

		# Enforce max_yield cap: count items of this archetype already on the tile
		if yield_comp.max_yield >= 0:
			var existing: int = _count_items(inv, yield_comp.item_type, reg)
			if existing >= yield_comp.max_yield:
				continue

		# Deposit one item
		_ItemFactory.create_and_deposit(
			world,
			yield_comp.item_type,
			yield_comp.material_type,
			entity_id
		)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Count how many items in an inventory match a given item_type.
func _count_items(inv: _InventoryComponent, item_type: int, reg) -> int:
	var count: int = 0
	for item_id: int in inv.items:
		var item_comp = reg.get_component(item_id, &"ItemComponent")
		if item_comp != null and item_comp.item_type == item_type:
			count += 1
	return count

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
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")

## Maximum number of items of a specific archetype allowed to exist simultaneously across the entire world.
## Prevents wild vegetation (like 12,000 grass tiles) from generating tens of thousands of loose items.
const GLOBAL_ITEM_CAPS: Dictionary = {
	_ItemTypes.Type.GRASS: 16384,
}
const DEFAULT_GLOBAL_ITEM_CAP: int = 100000

const SLICE_COUNT: int = 20
var _slice_buckets: Array[PackedInt32Array] = []
var _cached_store_size: int = -1

func _rebuild_buckets(yield_store: Dictionary) -> void:
	_slice_buckets.clear()
	for i in range(SLICE_COUNT):
		_slice_buckets.append(PackedInt32Array())
	for entity_id: int in yield_store:
		_slice_buckets[entity_id % SLICE_COUNT].append(entity_id)
	_cached_store_size = yield_store.size()

func tick(tick_number: int) -> void:
	var reg = world.get_registry()
	var yield_store: Dictionary = reg.get_store(&"ItemYieldComponent")
	if yield_store.is_empty():
		return

	if _cached_store_size != yield_store.size():
		_rebuild_buckets(yield_store)

	var slice_mod: int = tick_number % SLICE_COUNT
	var slice: PackedInt32Array = _slice_buckets[slice_mod]

	var burn_store: Dictionary = reg.get_store(&"BurningComponent")
	var inv_store:  Dictionary = reg.get_store(&"InventoryComponent")

	for entity_id: int in slice:
		# Burning plants don't produce
		if burn_store.has(entity_id):
			continue

		var yield_comp = yield_store.get(entity_id, null)
		if yield_comp == null:
			continue
		yield_comp.ticks_since_yield += SLICE_COUNT

		if yield_comp.ticks_since_yield < yield_comp.ticks_per_yield:
			continue

		# Reset the counter before the deposit so a failed deposit still resets
		yield_comp.ticks_since_yield = 0

		# Enforce global hard cap across the world in O(1) time
		var max_global: int = GLOBAL_ITEM_CAPS.get(yield_comp.item_type, DEFAULT_GLOBAL_ITEM_CAP)
		if max_global >= 0 and _ItemFactory.get_global_count(yield_comp.item_type) >= max_global:
			continue

		# Tile's InventoryComponent is on the same entity (tile = vegetation host)
		var inv: _InventoryComponent = inv_store.get(entity_id, null)
		if inv == null:
			continue

		# Enforce local tile max_yield cap: count total units of this archetype already on the tile
		if yield_comp.max_yield >= 0:
			var existing_qty: int = inv.get_total_quantity_of_type(reg, yield_comp.item_type)
			if existing_qty >= yield_comp.max_yield:
				continue

		# Deposit one item (ItemFactory handles stacking and O(1) global count updates)
		_ItemFactory.create_and_deposit(
			world,
			yield_comp.item_type,
			yield_comp.material_type,
			entity_id
		)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Count how many units of an archetype exist in an inventory.
func _count_items(inv: _InventoryComponent, item_type: int, reg) -> int:
	if inv == null:
		return 0
	return inv.get_total_quantity_of_type(reg, item_type)

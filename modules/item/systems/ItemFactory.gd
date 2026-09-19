## ItemFactory.gd
## Stateless item-creation utility.  NOT a simulation system — has no tick().
## Call its static methods from any system that needs to spawn item entities.
##
## Usage:
##   # Create a standalone item entity
##   var id := ItemFactory.create(world, ItemTypes.Type.GRASS, MaterialTypes.Type.ORGANIC)
##
##   # Create and immediately add to a tile's inventory
##   ItemFactory.create_and_deposit(world, ItemTypes.Type.GRASS, MaterialTypes.Type.ORGANIC, tile_entity_id)
class_name ItemFactory
extends RefCounted

const _MatterComponent    = preload("res://modules/matter/components/MatterComponent.gd")
const _MaterialTypes      = preload("res://modules/matter/data/MaterialTypes.gd")
const _ItemComponent      = preload("res://modules/item/components/ItemComponent.gd")
const _ItemTypes          = preload("res://modules/item/data/ItemTypes.gd")
const _InventoryComponent = preload("res://modules/item/components/InventoryComponent.gd")

## Create a new item entity and return its entity_id.
## Asserts that (item_type, material_type) is a valid combination.
static func create(world: Node, item_type: int, material_type: int, quantity: int = 1) -> int:
	assert(
		_ItemTypes.is_valid_combination(item_type, material_type),
		"ItemFactory: invalid combo item_type=%d material_type=%d" % [item_type, material_type]
	)

	var entity_id: int = world.create_entity()
	var comp := _ItemComponent.new()
	comp.item_type     = item_type
	comp.material_type = material_type
	comp.display_name  = _ItemTypes.build_name(item_type, material_type)
	comp.quantity      = quantity
	world.add_component(entity_id, comp)

	var matter := _MatterComponent.new()
	_MaterialTypes.apply_to(matter, material_type)
	world.add_component(entity_id, matter)

	return entity_id

## Create an item entity and push it into target_entity's InventoryComponent.
## Returns the new item entity_id, or -1 if the target has no inventory or is full.
## Inherits initial temperature from the target entity (tile, container, or creature).
static func create_and_deposit(
		world: Node,
		item_type: int,
		material_type: int,
		target_entity: int,
		quantity: int = 1) -> int:

	var inv: _InventoryComponent = world.get_component(target_entity, &"InventoryComponent")
	if inv == null or not inv.has_space():
		return -1

	var item_id: int = create(world, item_type, material_type, quantity)
	var item_comp: _ItemComponent = world.get_component(item_id, &"ItemComponent")
	if item_comp != null:
		item_comp.container_id = target_entity

	# Inherit initial temperature from container entity
	var target_matter = world.get_component(target_entity, &"MatterComponent")
	var item_matter   = world.get_component(item_id, &"MatterComponent")
	if target_matter != null and item_matter != null:
		item_matter.temperature_c = target_matter.temperature_c

	inv.items.append(item_id)
	return item_id



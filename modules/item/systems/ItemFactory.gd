## ItemFactory.gd
## Stateless item-creation utility. NOT a simulation system — has no tick().
## Call its static methods from any system that needs to spawn item entities.
##
## Usage:
##   # Create a single-material item (backward compatible)
##   var id := ItemFactory.create(world, ItemTypes.Type.SWORD, MaterialTypes.Type.STEEL)
##
##   # Create a multi-part composite item
##   var id := ItemFactory.create_composite(world, ItemTypes.Type.SWORD, {
##       "blade": MaterialTypes.Type.STEEL,
##       "hilt":  MaterialTypes.Type.WOOD_HARD,
##   })
##
##   # Create and deposit into inventory
##   ItemFactory.create_and_deposit(world, ItemTypes.Type.GRASS, MaterialTypes.Type.ORGANIC, tile_entity_id)
class_name ItemFactory
extends RefCounted

const _MatterComponent    = preload("res://modules/matter/components/MatterComponent.gd")
const _MaterialTypes      = preload("res://modules/matter/data/MaterialTypes.gd")
const _ItemComponent      = preload("res://modules/item/components/ItemComponent.gd")
const _ItemTypes          = preload("res://modules/item/data/ItemTypes.gd")
const _InventoryComponent = preload("res://modules/item/components/InventoryComponent.gd")

## O(1) Synchronous global item count tracking by archetype (item_type -> int)
static var _global_counts: Dictionary = {}

static func get_global_count(item_type: int) -> int:
	return _global_counts.get(item_type, 0)

static func get_total_quantity() -> int:
	var total: int = 0
	for count in _global_counts.values():
		total += count as int
	return total

static func get_all_global_counts() -> Dictionary:
	return _global_counts.duplicate()

static func notify_item_created(item_type: int, qty: int = 1) -> void:
	_global_counts[item_type] = _global_counts.get(item_type, 0) + qty

static func notify_item_destroyed(item_type: int, qty: int = 1) -> void:
	var cur: int = _global_counts.get(item_type, 0)
	_global_counts[item_type] = maxi(0, cur - qty)

static func reset_global_counts() -> void:
	_global_counts.clear()

## Create a new single-material item entity (100% backwards compatible).
## Automatically maps material_type to compatible parts, using archetype defaults for others.
static func create(world: Node, item_type: int, material_type: int, quantity: int = 1) -> int:
	var mold_parts: Dictionary = _ItemTypes.get_parts_data(item_type)
	var parts_map: Dictionary = {}

	for part_name: String in mold_parts:
		var part_def: Dictionary = mold_parts[part_name]
		var valid: Array = part_def.get("valid_matters", [])
		if material_type in valid:
			parts_map[part_name] = material_type
		elif part_def.get("optional", false):
			continue
		else:
			parts_map[part_name] = part_def.get("default_matter", material_type)

	return create_composite(world, item_type, parts_map, quantity)

## Create a multi-material composite item entity.
## Computes individual part masses, total mass, contact geometry, and synthesizes
## composite physical, thermodynamic, and mechanical stats onto MatterComponent.
static func create_composite(
	world: Node,
	item_type: int,
	parts_materials: Dictionary,
	quantity: int = 1
) -> int:
	var mold_parts: Dictionary = _ItemTypes.get_parts_data(item_type)
	var primary_name: String = _ItemTypes.get_primary_part_name(item_type)

	# 1. Resolve and complete parts map
	var resolved_parts: Dictionary = {}
	var total_mass: float = 0.0
	var total_volume: float = 0.0

	var sum_c_mass: float = 0.0
	var min_ignition_c: float = INF
	var max_rot_rate: float = 0.0
	var sum_cond_vol: float = 0.0
	var sum_moisture_mass: float = 0.0

	var primary_mat_id: int = 0
	var primary_mat_data: Dictionary = {}
	var primary_thickness: float = 0.05
	var handle_yield_cap: float = INF

	for part_name: String in mold_parts:
		var part_def: Dictionary = mold_parts[part_name]
		if part_def.get("optional", false) and not parts_materials.has(part_name):
			continue

		var mat_id: int = parts_materials.get(part_name, part_def.get("default_matter", 0))
		var mat_data: Dictionary = _MaterialTypes.get_data(mat_id)
		var vol: float = part_def.get("volume", 0.0005)
		var density: float = mat_data.get("density", 1000.0)
		var mass: float = maxf(0.001, vol * density)
		var role: int = part_def.get("role", _ItemTypes.PartRole.PRIMARY_CONTACT)
		var thickness: float = part_def.get("thickness", 0.05)

		resolved_parts[part_name] = {
			"material_id": mat_id,
			"role":        role,
			"volume":      vol,
			"mass":        mass,
			"wear":        0.0,
		}

		total_mass += mass
		total_volume += vol

		# Weighted thermodynamics
		var spec_heat: float = mat_data.get("specific_heat", 1000.0)
		sum_c_mass += mass * spec_heat
		sum_cond_vol += vol * (mat_data.get("conductivity", 1.0) as float)
		sum_moisture_mass += mass * (mat_data.get("moisture", 0.0) as float)

		var ign: float = mat_data.get("ignition_temp_c", INF)
		if ign < min_ignition_c:
			min_ignition_c = ign

		var rot: float = mat_data.get("rot_rate", 0.0)
		if rot > max_rot_rate:
			max_rot_rate = rot

		if role == _ItemTypes.PartRole.PRIMARY_CONTACT or part_name == primary_name:
			primary_mat_id = mat_id
			primary_mat_data = mat_data
			primary_thickness = thickness
		elif role == _ItemTypes.PartRole.HANDLE:
			var h_yield: float = mat_data.get("yield_strength", 100.0)
			handle_yield_cap = h_yield * (thickness / 0.035) * 1.5

	if primary_mat_data.is_empty():
		primary_mat_data = _MaterialTypes.get_data(primary_mat_id)

	total_volume = maxf(0.00001, total_volume)
	total_mass = maxf(0.001, total_mass)

	# 2. Instantiate ECS Entity
	var entity_id: int = world.create_entity()

	# 3. Populate ItemComponent
	var comp := _ItemComponent.new()
	comp.item_type     = item_type
	comp.material_type = primary_mat_id
	comp.primary_part  = primary_name
	comp.parts         = resolved_parts
	comp.total_mass    = total_mass
	comp.total_volume  = total_volume
	comp.display_name  = _ItemTypes.build_composite_name(item_type, parts_materials)
	comp.quantity      = quantity
	var mold_data: Dictionary = _ItemTypes.get_data(item_type)
	if mold_data.has("max_stack"):
		comp.max_stack = mold_data["max_stack"]
	world.add_component(entity_id, comp)

	# 4. Synthesize composite physical stats into MatterComponent
	var matter := _MatterComponent.new()
	matter.material_id     = primary_mat_id
	matter.state           = 0  # Solid
	matter.density         = total_mass / total_volume

	# Surface properties are dictated by the primary striking/contact part
	matter.hardness        = primary_mat_data.get("hardness", 5.0)
	matter.acidity_ph      = primary_mat_data.get("acidity_ph", 7.0)
	matter.corrosiveness   = primary_mat_data.get("corrosiveness", 0.0)
	matter.toxicity        = primary_mat_data.get("toxicity", 0.0)
	matter.elasticity      = primary_mat_data.get("elasticity", 0.3)
	matter.melting_point_c = primary_mat_data.get("melting_point_c", INF)
	matter.boiling_point_c = primary_mat_data.get("boiling_point_c", INF)

	# If the item has a surface coating, its chemical properties transfer to the striking surface
	if resolved_parts.has("coating"):
		var coat_mat = _MaterialTypes.get_data(resolved_parts["coating"]["material_id"])
		if coat_mat.get("toxicity", 0.0) > 0.0:
			matter.toxicity = maxf(matter.toxicity, coat_mat.get("toxicity", 0.0))
		if coat_mat.get("corrosiveness", 0.0) > 0.0:
			matter.corrosiveness = maxf(matter.corrosiveness, coat_mat.get("corrosiveness", 0.0))
		if (coat_mat.get("acidity_ph", 7.0) as float) < matter.acidity_ph:
			matter.acidity_ph = coat_mat.get("acidity_ph", 7.0)

	# Structural strength: primary part scaled by thickness, limited by handle strength
	var base_yield: float = primary_mat_data.get("yield_strength", 100.0)
	var scaled_yield: float = base_yield * (primary_thickness / 0.02)
	matter.yield_strength  = minf(scaled_yield, handle_yield_cap)

	# Hazard & thermal integration
	matter.ignition_temp_c = min_ignition_c
	# Flammability reflects the most combustible part when exposed to heat
	var max_part_flammability: float = 0.0
	for p in resolved_parts.values():
		var p_mat = _MaterialTypes.get_data(p["material_id"])
		max_part_flammability = maxf(max_part_flammability, p_mat.get("flammability", 0.0))
	matter.flammability    = max_part_flammability

	matter.specific_heat   = sum_c_mass / total_mass
	matter.conductivity    = sum_cond_vol / total_volume
	matter.moisture        = sum_moisture_mass / total_mass
	matter.rot_rate        = max_rot_rate

	world.add_component(entity_id, matter)
	notify_item_created(item_type, quantity)

	return entity_id

## Create a single-material item entity and deposit it into an inventory.
## Stacks with existing compatible items on the target entity if available.
static func create_and_deposit(
	world: Node,
	item_type: int,
	material_type: int,
	target_entity: int,
	quantity: int = 1
) -> int:
	var inv: _InventoryComponent = world.get_component(target_entity, &"InventoryComponent")
	if inv == null:
		return -1

	var reg = world.get_registry()
	# 1. Try stacking into an existing item stack on this entity
	var existing_id: int = inv.find_stackable_item(reg, item_type, material_type)
	if existing_id != -1:
		var existing_item = reg.get_component(existing_id, &"ItemComponent")
		if existing_item != null:
			var overflow: int = existing_item.add_quantity(quantity)
			var added: int = quantity - overflow
			if added > 0:
				notify_item_created(item_type, added)
				inv.update_cache(reg)
				if world != null and world.signals != null:
					world.signals.register_active_inventory(target_entity)
			if overflow <= 0:
				return existing_id
			quantity = overflow

	if not inv.has_space():
		return -1

	var item_id: int = create(world, item_type, material_type, quantity)
	_finalize_deposit(world, item_id, target_entity, inv)
	inv.update_cache(reg)
	if world != null and world.signals != null:
		world.signals.register_active_inventory(target_entity)
	return item_id

## Create a multi-material composite item entity and deposit it into an inventory.
## Stacks with existing compatible composite items on the target entity if available.
static func create_composite_and_deposit(
	world: Node,
	item_type: int,
	parts_materials: Dictionary,
	target_entity: int,
	quantity: int = 1
) -> int:
	var inv: _InventoryComponent = world.get_component(target_entity, &"InventoryComponent")
	if inv == null:
		return -1

	var reg = world.get_registry()
	var mold_parts: Dictionary = _ItemTypes.get_parts_data(item_type)
	var primary_name: String = _ItemTypes.get_primary_part_name(item_type)
	var primary_def: Dictionary = mold_parts.get(primary_name, {})
	var primary_mat: int = parts_materials.get(primary_name, primary_def.get("default_matter", 0))

	# Try stacking into an existing matching composite item
	var existing_id: int = inv.find_stackable_item(reg, item_type, primary_mat, parts_materials)
	if existing_id != -1:
		var existing_item = reg.get_component(existing_id, &"ItemComponent")
		if existing_item != null:
			var overflow: int = existing_item.add_quantity(quantity)
			var added: int = quantity - overflow
			if added > 0:
				notify_item_created(item_type, added)
				inv.update_cache(reg)
				if world != null and world.signals != null:
					world.signals.register_active_inventory(target_entity)
			if overflow <= 0:
				return existing_id
			quantity = overflow

	if not inv.has_space():
		return -1

	var item_id: int = create_composite(world, item_type, parts_materials, quantity)
	_finalize_deposit(world, item_id, target_entity, inv)
	inv.update_cache(reg)
	if world != null and world.signals != null:
		world.signals.register_active_inventory(target_entity)
	return item_id

static func _finalize_deposit(
	world: Node,
	item_id: int,
	target_entity: int,
	inv: _InventoryComponent
) -> void:
	var item_comp: _ItemComponent = world.get_component(item_id, &"ItemComponent")
	if item_comp != null:
		item_comp.container_id = target_entity

	# Inherit initial temperature from container entity
	var target_matter = world.get_component(target_entity, &"MatterComponent")
	var item_matter   = world.get_component(item_id, &"MatterComponent")
	if target_matter != null and item_matter != null:
		item_matter.temperature_c = target_matter.temperature_c

	inv.container_id = target_entity
	inv.items.append(item_id)

## Convenience method to create grass, either fresh with water material or dried/pure.
static func create_grass(world: Node, is_fresh: bool = true, quantity: int = 1) -> int:
	if is_fresh:
		return create_composite(world, _ItemTypes.Type.GRASS, {
			"main":  _MaterialTypes.Type.ORGANIC,
			"water": _MaterialTypes.Type.WATER,
		}, quantity)
	return create(world, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, quantity)

## Convenience method to create and deposit grass into an inventory.
static func create_and_deposit_grass(
	world: Node,
	target_entity: int,
	is_fresh: bool = true,
	quantity: int = 1
) -> int:
	if is_fresh:
		return create_composite_and_deposit(world, _ItemTypes.Type.GRASS, {
			"main":  _MaterialTypes.Type.ORGANIC,
			"water": _MaterialTypes.Type.WATER,
		}, target_entity, quantity)
	return create_and_deposit(world, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, target_entity, quantity)




## DecaySystem.gd
## Priority 190 -- runs every 300 ticks (slow biological process).
##
## Simulates organic rotting, moisture loss, preservation by freezing,
## and conversion of spoiled organic matter to soil and contaminants.
class_name DecaySystem
extends "res://core/SystemBase.gd"

const _ContaminantComponent = preload("res://modules/matter/components/ContaminantComponent.gd")
const _MaterialTypes        = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes            = preload("res://modules/terrain/data/TileTypes.gd")

func initialize() -> void:
	print("[DecaySystem] Initialized. Priority 190.")

func tick(tick_number: int) -> void:
	if tick_number % 300 != 0:
		return

	var reg = world.get_registry()
	var matter_store: Dictionary = reg.get_store(&"MatterComponent")
	var entity_ids: Array = matter_store.keys()

	for matter_eid: int in entity_ids:
		var matter = reg.get_component(matter_eid, &"MatterComponent")
		if matter == null or matter.rot_rate <= 0.0:
			continue

		# If this entity is an item inside a container, sync temperature and check container freezing
		var item_comp = reg.get_component(matter_eid, &"ItemComponent")
		if item_comp != null and item_comp.container_id != -1:
			var container_matter = reg.get_component(item_comp.container_id, &"MatterComponent")
			if container_matter != null:
				matter.temperature_c = container_matter.temperature_c
			if reg.has(item_comp.container_id, &"FrozenComponent"):
				continue

		# Freezing completely halts rot (Dwarf Fortress faithful)
		if reg.has(matter_eid, &"FrozenComponent"):
			continue

		# Temperature accelerates decay: 0.5x in cold, up to 2.0x in summer heat (40C)
		var temp_ratio: float = clampf(matter.temperature_c / 40.0, 0.0, 1.0)
		var temp_factor: float = lerpf(0.5, 2.0, temp_ratio)
		var decay_amount: float = matter.rot_rate * temp_factor * 0.005

		matter.moisture = maxf(0.0, matter.moisture - decay_amount * 0.3)
		matter._decay_progress += decay_amount

		if matter._decay_progress >= 1.0:
			_on_fully_decayed(matter_eid, matter, reg)

func _on_fully_decayed(eid: int, matter, reg) -> void:
	# Check if entity is an item
	var item_comp = reg.get_component(eid, &"ItemComponent")
	if item_comp != null:
		_on_item_decayed(eid, item_comp, matter, reg)
		return

	var tile_comp = reg.get_component(eid, &"TileComponent")
	var mat_id: int = matter.material_id

	if mat_id == _MaterialTypes.Type.KINDLING:
		# Kindling rots down into dirt
		if reg.has(eid, &"VegetationComponent"):
			reg.remove(eid, &"VegetationComponent")
		matter.material_id = _MaterialTypes.Type.DIRT
		_apply_material_data(matter, _MaterialTypes.get_data(_MaterialTypes.Type.DIRT))
		matter._decay_progress = 0.0
		if tile_comp != null:
			tile_comp.tile_type = _TileTypes.Type.DIRT
			_update_render(eid, _TileTypes.Type.DIRT, reg)

	elif mat_id in [_MaterialTypes.Type.WOOD_SOFT, _MaterialTypes.Type.WOOD_HARD]:
		# Dead trees/shrubs rot into ground humus
		if reg.has(eid, &"VegetationComponent"):
			reg.remove(eid, &"VegetationComponent")
		matter.material_id = _MaterialTypes.Type.GROUND
		_apply_material_data(matter, _MaterialTypes.get_data(_MaterialTypes.Type.GROUND))
		matter._decay_progress = 0.0
		if tile_comp != null:
			tile_comp.tile_type = _TileTypes.Type.GROUND
			_update_render(eid, _TileTypes.Type.GROUND, reg)

	elif mat_id == _MaterialTypes.Type.RAW_MEAT:
		# Rotting meat generates toxic miasma contaminant, turns to dirt
		var contam = reg.get_component(eid, &"ContaminantComponent")
		if contam == null:
			contam = _ContaminantComponent.new()
			contam.source_mat_id = _MaterialTypes.Type.RAW_MEAT
			reg.add(eid, contam)
		contam.toxicity = clampf(contam.toxicity + 0.5, 0.0, 1.0)

		matter.material_id = _MaterialTypes.Type.DIRT
		_apply_material_data(matter, _MaterialTypes.get_data(_MaterialTypes.Type.DIRT))
		matter._decay_progress = 0.0
		if tile_comp != null:
			tile_comp.tile_type = _TileTypes.Type.DIRT
			_update_render(eid, _TileTypes.Type.DIRT, reg)
	else:
		matter._decay_progress = 0.0

## Resolves an item whose matter has rotted completely away.
func _on_item_decayed(eid: int, item_comp, matter, reg) -> void:
	# Rotting meat leaves toxic miasma on the containing tile/entity
	if matter.material_id == _MaterialTypes.Type.RAW_MEAT and item_comp.container_id != -1:
		var contam = reg.get_component(item_comp.container_id, &"ContaminantComponent")
		if contam == null:
			contam = _ContaminantComponent.new()
			contam.source_mat_id = _MaterialTypes.Type.RAW_MEAT
			reg.add(item_comp.container_id, contam)
		contam.toxicity = clampf(contam.toxicity + 0.5, 0.0, 1.0)

	# Cleanly remove from container's InventoryComponent
	if item_comp.container_id != -1:
		var inv = reg.get_component(item_comp.container_id, &"InventoryComponent")
		if inv != null:
			inv.remove_item(eid)

	# Destroy the item entity
	world.destroy_entity(eid)


func _apply_material_data(matter, d: Dictionary) -> void:
	matter.state           = d.get("state",           0) as int
	matter.density         = d.get("density",         1000.0) as float
	matter.melting_point_c = d.get("melting_point_c", INF) as float
	matter.boiling_point_c = d.get("boiling_point_c", INF) as float
	matter.ignition_temp_c = d.get("ignition_temp_c", INF) as float
	matter.conductivity    = d.get("conductivity",    1.0) as float
	matter.specific_heat   = d.get("specific_heat",   1000.0) as float
	matter.flammability    = d.get("flammability",    0.0) as float
	matter.acidity_ph      = d.get("acidity_ph",      7.0) as float
	matter.corrosiveness   = d.get("corrosiveness",   0.0) as float
	matter.moisture        = d.get("moisture",        0.0) as float
	matter.rot_rate        = d.get("rot_rate",        0.0) as float
	matter.toxicity        = d.get("toxicity",        0.0) as float
	matter.hardness        = d.get("hardness",        5.0) as float
	matter.yield_strength  = d.get("yield_strength",  100.0) as float
	matter.elasticity      = d.get("elasticity",      0.3) as float

func _update_render(eid: int, tile_type: int, reg) -> void:
	var render = reg.get_component(eid, &"RenderComponent")
	if render == null:
		return
	var td: Dictionary = _TileTypes.get_data(tile_type)
	render.glyph    = td["glyph"]
	render.fg_color = td["fg_color"]
	render.bg_color = td["bg_color"]

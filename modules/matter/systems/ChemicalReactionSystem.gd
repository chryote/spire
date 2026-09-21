## ChemicalReactionSystem.gd
## Priority 185 (18.5) -- runs every 20 ticks.
##
## Manages chemical reactions, acid/corrosion degradation of material
## yield_strength, structural breakdown, and corrosion spread from fluids/gases.
class_name ChemicalReactionSystem
extends "res://core/SystemBase.gd"

const _ContaminantComponent = preload("res://modules/matter/components/ContaminantComponent.gd")
const _MaterialTypes        = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes            = preload("res://modules/terrain/data/TileTypes.gd")

const NEIGHBOURS: Array = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                   Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]

func initialize() -> void:
	print("[ChemicalReactionSystem] Initialized. Priority 185.")

func tick(tick_number: int) -> void:
	if tick_number % 20 != 0:
		return

	var reg = world.get_registry()

	# --- 1. Spread corrosion from corrosive gases and fluids ---
	_spread_corrosion_sources(reg)

	# --- 2. Apply corrosion degradation ---
	var contam_store: Dictionary = reg.get_store(&"ContaminantComponent")
	var contam_eids: Array = contam_store.keys()

	for contam_eid: int in contam_eids:
		var contam = reg.get_component(contam_eid, &"ContaminantComponent")
		if contam == null or contam.corrosion <= 0.0:
			continue

		var matter = reg.get_component(contam_eid, &"MatterComponent")
		if matter == null:
			continue

		# Deplete yield_strength by corrosion
		var damage: float = contam.corrosion * 0.1
		matter.yield_strength = maxf(0.0, matter.yield_strength - damage)

		if matter.yield_strength <= 0.0:
			_on_corroded_through(contam_eid, matter, reg)

		# Corrosive agent gradually neutralises / depletes
		contam.corrosion *= 0.95
		if contam.corrosion < 0.005:
			contam.corrosion = 0.0
			if contam.toxicity <= 0.0:
				reg.remove(contam_eid, &"ContaminantComponent")

func _spread_corrosion_sources(reg) -> void:
	# Spread from GasComponent
	var gas_store: Dictionary = reg.get_store(&"GasComponent")
	for gas_eid: int in gas_store.keys():
		var gas = gas_store.get(gas_eid)
		if gas == null:
			continue
		var g_mat: Dictionary = _MaterialTypes.get_data(gas.material_id)
		var g_corr: float = g_mat.get("corrosiveness", 0.0) as float
		if g_corr > 0.0:
			var tile_comp = reg.get_component(gas_eid, &"TileComponent")
			if tile_comp != null:
				_deposit_corrosion_to_neighbours(tile_comp.position, g_corr * gas.concentration * 0.01, gas.material_id, reg)

	# Spread from FluidComponent
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	for fluid_eid: int in fluid_store.keys():
		var fluid = fluid_store.get(fluid_eid)
		if fluid == null:
			continue
		var f_mat: Dictionary = _MaterialTypes.get_data(fluid.material_id)
		var f_corr: float = f_mat.get("corrosiveness", 0.0) as float
		if f_corr > 0.0:
			var tile_comp = reg.get_component(fluid_eid, &"TileComponent")
			if tile_comp != null:
				_deposit_corrosion_to_neighbours(tile_comp.position, f_corr * fluid.volume * 0.01, fluid.material_id, reg)

func _deposit_corrosion_to_neighbours(pos: Vector2i, amount: float, source_mat: int, reg) -> void:
	if amount <= 0.0:
		return
	for offset: Vector2i in NEIGHBOURS:
		var npos: Vector2i = pos + offset
		if not world.is_valid_position(npos):
			continue
		var nid: int = world.get_entity_at(npos)
		if nid == -1:
			continue
		var contam = reg.get_component(nid, &"ContaminantComponent")
		if contam == null:
			contam = _ContaminantComponent.new()
			contam.source_mat_id = source_mat
			reg.add(nid, contam)
		contam.corrosion = clampf(contam.corrosion + amount, 0.0, 1.0)

func _on_corroded_through(eid: int, matter, reg) -> void:
	var tile_comp = reg.get_component(eid, &"TileComponent")
	var mat_id: int = matter.material_id

	if mat_id == _MaterialTypes.Type.STEEL:
		# Rust and crumble into ground
		matter.material_id = _MaterialTypes.Type.GROUND
		_apply_material_data(matter, _MaterialTypes.get_data(_MaterialTypes.Type.GROUND))
		if tile_comp != null:
			tile_comp.tile_type = _TileTypes.Type.GROUND
			if world != null and world.signals != null:
				world.signals.notify_tile_type_changed(tile_comp.position, _TileTypes.Type.GROUND)
			_update_render(eid, _TileTypes.Type.GROUND, reg)

	elif mat_id == _MaterialTypes.Type.STONE or mat_id == _MaterialTypes.Type.OBSIDIAN:
		# Weather into dirt
		matter.material_id = _MaterialTypes.Type.DIRT
		_apply_material_data(matter, _MaterialTypes.get_data(_MaterialTypes.Type.DIRT))
		if tile_comp != null:
			tile_comp.tile_type = _TileTypes.Type.DIRT
			if world != null and world.signals != null:
				world.signals.notify_tile_type_changed(tile_comp.position, _TileTypes.Type.DIRT)
			_update_render(eid, _TileTypes.Type.DIRT, reg)

	elif mat_id in [_MaterialTypes.Type.WOOD_SOFT, _MaterialTypes.Type.WOOD_HARD, _MaterialTypes.Type.KINDLING]:
		# Dissolve plant material
		if reg.has(eid, &"VegetationComponent"):
			reg.remove(eid, &"VegetationComponent")
		var fallback_type: int = tile_comp.tile_type if tile_comp != null else _TileTypes.Type.GROUND
		var fallback_mat: int = _MaterialTypes.TILE_MATERIAL_MAP.get(fallback_type, _MaterialTypes.Type.GROUND)
		matter.material_id = fallback_mat
		_apply_material_data(matter, _MaterialTypes.get_data(fallback_mat))
		if tile_comp != null:
			_update_render(eid, tile_comp.tile_type, reg)

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

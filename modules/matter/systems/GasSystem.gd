## GasSystem.gd
## Priority 180 -- runs every 3 ticks, after FluidSystem (170).
##
## Manages atmospheric gas dispersal, dissipation, toxicity/corrosiveness
## deposition onto ContaminantComponent, and rendering.
class_name GasSystem
extends "res://core/SystemBase.gd"

const _GasComponent         = preload("res://modules/matter/components/GasComponent.gd")
const _ContaminantComponent = preload("res://modules/matter/components/ContaminantComponent.gd")
const _MaterialTypes        = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes            = preload("res://modules/terrain/data/TileTypes.gd")

## 8-directional neighbor offsets for atmospheric diffusion
const NEIGHBOURS: Array = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                   Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]

## Dissipation rate per cycle (runs every 3 ticks, equivalent to ~0.01 per tick)
const DISSIPATION_RATE: float = 0.03

func initialize() -> void:
	print("[GasSystem] Initialized. Priority 180.")

func tick(tick_number: int) -> void:
	if tick_number % 3 != 0:
		return

	var reg = world.get_registry()
	var gas_store: Dictionary = reg.get_store(&"GasComponent")
	var entity_ids: Array = gas_store.keys()

	for gas_eid: int in entity_ids:
		var gas = reg.get_component(gas_eid, &"GasComponent")
		if gas == null:
			continue

		var tile_comp = reg.get_component(gas_eid, &"TileComponent")
		if tile_comp == null:
			continue

		# --- 1. Dissipation ---
		gas.concentration -= DISSIPATION_RATE
		if gas.concentration <= 0.01:
			reg.remove(gas_eid, &"GasComponent")
			_revert_render(gas_eid, reg)
			continue

		var mat_data: Dictionary = _MaterialTypes.get_data(gas.material_id)
		var tox: float = mat_data.get("toxicity", 0.0) as float
		var corr: float = mat_data.get("corrosiveness", 0.0) as float

		# --- 2. Apply contamination to local tile ---
		if tox > 0.0 or corr > 0.0:
			var contam = reg.get_component(gas_eid, &"ContaminantComponent")
			if contam == null:
				contam = _ContaminantComponent.new()
				contam.source_mat_id = gas.material_id
				reg.add(gas_eid, contam)
			if tox > 0.0:
				contam.toxicity = clampf(contam.toxicity + tox * gas.concentration * 0.02, 0.0, 1.0)
			if corr > 0.0:
				contam.corrosion = clampf(contam.corrosion + corr * gas.concentration * 0.02, 0.0, 1.0)

		# --- 3. Diffusion to neighbors ---
		if gas.concentration > 0.08:
			var pos: Vector2i = tile_comp.position
			for offset: Vector2i in NEIGHBOURS:
				var npos: Vector2i = pos + offset
				if not world.is_valid_position(npos):
					continue
				var nid: int = world.get_entity_at(npos)
				if nid == -1:
					continue

				var ngas = reg.get_component(nid, &"GasComponent")
				if ngas == null:
					var spread_conc: float = gas.concentration * 0.08
					if spread_conc > 0.01:
						var new_gas = _GasComponent.new()
						new_gas.concentration = spread_conc
						new_gas.material_id = gas.material_id
						reg.add(nid, new_gas)
				else:
					ngas.concentration = clampf(ngas.concentration + gas.concentration * 0.04, 0.0, 1.0)

		# --- 4. Render overlay ---
		_update_render(gas_eid, gas, reg)

func _update_render(eid: int, gas, reg) -> void:
	var render = reg.get_component(eid, &"RenderComponent")
	if render == null:
		return

	# Light shade block glyph \u2591
	render.glyph = "\u2591"
	var alpha: float = clampf(gas.concentration, 0.3, 0.85)

	if gas.material_id == _MaterialTypes.Type.CHLORINE:
		render.fg_color = Color(0.72, 0.85, 0.22, alpha)
		render.bg_color = render.bg_color.lerp(Color(0.2, 0.25, 0.05), gas.concentration * 0.4)
	elif gas.material_id == _MaterialTypes.Type.CAVE_METHANE:
		render.fg_color = Color(0.60, 0.65, 0.78, alpha)
		render.bg_color = render.bg_color.lerp(Color(0.08, 0.1, 0.15), gas.concentration * 0.4)
	else:
		# Steam / generic vapor
		render.fg_color = Color(0.85, 0.90, 0.95, alpha)
		render.bg_color = render.bg_color.lerp(Color(0.12, 0.15, 0.2), gas.concentration * 0.3)

func _revert_render(eid: int, reg) -> void:
	var render = reg.get_component(eid, &"RenderComponent")
	if render == null:
		return
	var tile_comp = reg.get_component(eid, &"TileComponent")
	if tile_comp != null:
		var td: Dictionary = _TileTypes.get_data(tile_comp.tile_type)
		render.glyph    = td["glyph"]
		render.fg_color = td["fg_color"]
		render.bg_color = td["bg_color"]

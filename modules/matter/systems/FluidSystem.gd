## FluidSystem.gd
## Priority 170 -- runs after CombustionSystem (160) and PhaseChangeSystem (150).
##
## Manages liquid volume flow, fluid freezing, fluid ignition, and rendering.
## Continuous float volume 0.0 to 1.0 (Q1-B).
class_name FluidSystem
extends "res://core/SystemBase.gd"

const _FluidComponent   = preload("res://modules/matter/components/FluidComponent.gd")
const _FrozenComponent  = preload("res://modules/matter/components/FrozenComponent.gd")
const _BurningComponent = preload("res://modules/matter/components/BurningComponent.gd")
const _MaterialTypes    = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes        = preload("res://modules/terrain/data/TileTypes.gd")

## 4-directional offsets for liquid flow
const FLOW_OFFSETS: Array = [
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
]

## Relative terrain elevations per tile type for gravity calculation
const TILE_ELEVATION: Dictionary = {
	_TileTypes.Type.MUD: 0.0,
	_TileTypes.Type.DIRT: 0.5,
	_TileTypes.Type.GRASS: 1.0,
	_TileTypes.Type.GROUND: 1.5,
	_TileTypes.Type.STONE: 2.0,
}

func initialize() -> void:
	print("[FluidSystem] Initialized. Priority 170.")

func tick(tick_number: int) -> void:
	var reg = world.get_registry()
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	if fluid_store.is_empty():
		return

	var tile_store: Dictionary   = reg.get_store(&"TileComponent")
	var matter_store: Dictionary = reg.get_store(&"MatterComponent")
	var burn_store: Dictionary   = reg.get_store(&"BurningComponent")
	var has_fire: bool           = not burn_store.is_empty()

	var to_remove: Array[int] = []

	for fluid_eid: int in fluid_store:
		var fluid = fluid_store[fluid_eid]
		if fluid == null:
			continue

		# Settled fluids are in equilibrium (at rest) -- skip simulation
		if fluid.settled:
			continue

		var matter = matter_store.get(fluid_eid, null)
		if matter == null:
			continue

		var tile_comp = tile_store.get(fluid_eid, null)
		if tile_comp == null:
			continue

		# --- 1. Freeze check ---
		var fluid_mat_data: Dictionary = _MaterialTypes.get_data(fluid.material_id)
		var fluid_melt_c: float = fluid_mat_data.get("melting_point_c", 0.0) as float
		if fluid_melt_c < INF and matter.temperature_c < fluid_melt_c:
			to_remove.append(fluid_eid)
			if matter.state == 1:
				matter.state = 0  # SOLID
			if not reg.has(fluid_eid, &"FrozenComponent"):
				reg.add(fluid_eid, _FrozenComponent.new())
			_revert_render(fluid_eid, reg)
			if world != null:
				world.mark_render_dirty()
			continue

		# --- 2. Minimum volume drain / removal ---
		if fluid.volume <= 0.01:
			to_remove.append(fluid_eid)
			if matter.state == 1:
				matter.state = 0
			_revert_render(fluid_eid, reg)
			if world != null:
				world.mark_render_dirty()
			continue

		# --- 3. Flammable fluid ignition from adjacent fire ---
		if has_fire and not burn_store.has(fluid_eid):
			var fluid_flammability: float = fluid_mat_data.get("flammability", 0.0) as float
			if fluid_flammability > 0.1 and _has_adjacent_fire_fast(tile_comp.position, burn_store):
				var b = _BurningComponent.new()
				b.intensity   = fluid_flammability
				b.fuel        = clampf(fluid.volume * 2.0, 0.5, 3.0)
				b.heat_output = 30.0 + fluid_flammability * 20.0
				reg.add(fluid_eid, b)

		# --- 4. Flow simulation ---

		var pos: Vector2i = tile_comp.position
		var current_elev: float = TILE_ELEVATION.get(tile_comp.tile_type, 1.0)
		var current_level: float = current_elev + fluid.volume

		var lowest_nid: int = -1
		var lowest_level: float = current_level
		var lowest_n_volume: float = 0.0

		for offset: Vector2i in FLOW_OFFSETS:
			var npos: Vector2i = pos + offset
			if not world.is_valid_position(npos):
				continue
			var nid: int = world.get_entity_at(npos)
			if nid == -1:
				continue
			var ntile = tile_store.get(nid, null)
			if ntile == null:
				continue

			var nfluid = fluid_store.get(nid, null)
			var n_vol: float = nfluid.volume if nfluid != null else 0.0
			var n_elev: float = TILE_ELEVATION.get(ntile.tile_type, 1.0)
			var n_level: float = n_elev + n_vol

			if n_level < lowest_level and n_vol < 1.0:
				lowest_level = n_level
				lowest_nid = nid
				lowest_n_volume = n_vol

		var flow_occurred: bool = false
		if lowest_nid != -1 and current_level > lowest_level:
			var space_left: float = 1.0 - lowest_n_volume
			var level_diff: float = (current_level - lowest_level) * 0.5
			var transfer: float = minf(fluid.volume * 0.25, minf(space_left, level_diff))

			if transfer > 0.005:
				fluid.volume -= transfer
				flow_occurred = true

				var target_fluid = fluid_store.get(lowest_nid, null)
				if target_fluid == null:
					var new_fluid = _FluidComponent.new()
					new_fluid.volume = transfer
					new_fluid.material_id = fluid.material_id
					new_fluid.settled = false
					reg.add(lowest_nid, new_fluid)
					var nmatter = matter_store.get(lowest_nid, null)
					if nmatter != null:
						nmatter.state = 1  # LIQUID
					_update_render(lowest_nid, new_fluid, reg)
				else:
					target_fluid.volume = minf(1.0, target_fluid.volume + transfer)
					target_fluid.settled = false
					_update_render(lowest_nid, target_fluid, reg)

				_update_render(fluid_eid, fluid, reg)
				if world != null:
					world.mark_render_dirty()

		if not flow_occurred:
			fluid.settled = true

	for rem_eid: int in to_remove:
		reg.remove(rem_eid, &"FluidComponent")

func _has_adjacent_fire_fast(pos: Vector2i, burn_store: Dictionary) -> bool:
	for offset: Vector2i in FLOW_OFFSETS:
		var npos: Vector2i = pos + offset
		if not world.is_valid_position(npos):
			continue
		var nid: int = world.get_entity_at(npos)
		if nid != -1 and burn_store.has(nid):
			return true
	return false

func _has_adjacent_fire(pos: Vector2i, reg) -> bool:
	return _has_adjacent_fire_fast(pos, reg.get_store(&"BurningComponent"))

func _update_render(eid: int, fluid, reg) -> void:
	var render = reg.get_component(eid, &"RenderComponent")
	if render == null:
		return

	if fluid.material_id == _MaterialTypes.Type.GREEK_FIRE:
		render.glyph = "\u2248"
		render.fg_color = Color(0.2, 0.95, 0.3, clampf(fluid.volume, 0.5, 1.0))
		render.bg_color = render.bg_color.lerp(Color(0.02, 0.25, 0.06), fluid.volume * 0.6)
	else:
		if fluid.volume >= 0.4:
			# Deep water wave
			render.glyph = "\u2248"
			render.fg_color = Color(0.25, 0.65, 1.0, clampf(fluid.volume, 0.6, 1.0))
			render.bg_color = render.bg_color.lerp(Color(0.04, 0.12, 0.28), clampf(fluid.volume * 0.8, 0.4, 0.9))
		else:
			# Shallow water ripple
			render.glyph = "~"
			render.fg_color = Color(0.35, 0.75, 1.0, clampf(fluid.volume * 2.0, 0.3, 0.8))
			render.bg_color = render.bg_color.lerp(Color(0.06, 0.16, 0.32), fluid.volume * 0.6)

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

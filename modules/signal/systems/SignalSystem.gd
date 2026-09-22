## SignalSystem.gd
## Priority 220 -- runs after physical simulation, vegetation yield, and decay.
##
## Central coordinator for all spatial signals and affordances.
## - Maintains a dynamic registry of SignalGrid channels (static, transient, diffuse).
## - Aggregates physical ECS world state into normalized 0.0-1.0 signals.
## - Updates the fast 64-bit TileAffordance bitmask map.
## - Advances atmospheric scent advection and sound decay.
## - Exposes a clean, high-performance query API for creature Utility AI.
class_name SignalSystem
extends "res://core/SystemBase.gd"

const _TileAffordance        = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes           = preload("res://modules/signal/data/SignalTypes.gd")
const _SignalGrid            = preload("res://modules/signal/data/SignalGrid.gd")
const _MaterialTypes         = preload("res://modules/matter/data/MaterialTypes.gd")
const _TileTypes             = preload("res://modules/terrain/data/TileTypes.gd")
const _VegetationTypes       = preload("res://modules/vegetation/data/VegetationTypes.gd")
const _InventoryComponent    = preload("res://modules/item/components/InventoryComponent.gd")
const _ItemTypes             = preload("res://modules/item/data/ItemTypes.gd")

## Registry of all active channels: StringName -> SignalGrid
var _channels: Dictionary = {}

## Custom external provider callables: Array[Callable]
## Each callable receives `(reg: ComponentRegistry, signals: SignalSystem)`
var _custom_providers: Array[Callable] = []

## 64-bit affordance bitmask per tile (width x height).
var affordance_map: PackedInt64Array

## Pre-cached static terrain baseline buffers to eliminate 16,384 GDScript iterations per tick
var _clean_trav_cache:       PackedFloat32Array = PackedFloat32Array()
var _base_trav_cache:        PackedFloat32Array = PackedFloat32Array()
var _base_affordance_cache:  PackedInt64Array   = PackedInt64Array()
var _terrain_cache_ready:    bool               = false

## Pre-cached static vegetation baseline buffers to eliminate 12,000 GDScript iterations per tick
var _cached_food_plant:       PackedFloat32Array = PackedFloat32Array()
var _cached_cover:            PackedFloat32Array = PackedFloat32Array()
var _veg_affordance_cache:    PackedInt64Array   = PackedInt64Array()
var _combined_affordance_map: PackedInt64Array   = PackedInt64Array()
var _veg_cache_ready:         bool               = false

## Pre-cached static settled fluid baseline buffers to eliminate 1,300 fluid entity queries per tick
var _cached_hydration:        PackedFloat32Array = PackedFloat32Array()
var _fluid_cache_ready:       bool               = false
var _cached_fluid_count:      int                = -1

## Pre-cached static climate temperature hazard buffer to eliminate 16,384 tile iterations per tick
var _cached_climate_hazard:   PackedFloat32Array = PackedFloat32Array()
var _climate_lethal_indices:  PackedInt32Array   = PackedInt32Array()
var _climate_hazard_ready:    bool               = false

## Sparse active inventory tracking (container_id: int -> true)
var _active_inventories:      Dictionary         = {}

var _width: int = 128
var _height: int = 128
var _total_tiles: int = 128 * 128

# ===========================================================================
# System Lifecycle
# ===========================================================================

func initialize() -> void:
	if world != null:
		_width = world.MAP_WIDTH
		_height = world.MAP_HEIGHT
	_total_tiles = _width * _height

	affordance_map.resize(_total_tiles)
	affordance_map.fill(_TileAffordance.WALKABLE)

	# Register standard core channels
	register_channel(_SignalTypes.HAZARD, _SignalTypes.PropagationType.STATIC_SNAPSHOT)
	register_channel(_SignalTypes.HYDRATION, _SignalTypes.PropagationType.STATIC_SNAPSHOT)
	register_channel(_SignalTypes.FOOD_PLANT, _SignalTypes.PropagationType.STATIC_SNAPSHOT)
	register_channel(_SignalTypes.FOOD_MEAT, _SignalTypes.PropagationType.STATIC_SNAPSHOT)
	register_channel(_SignalTypes.COVER, _SignalTypes.PropagationType.STATIC_SNAPSHOT)
	register_channel(_SignalTypes.TRAVERSABILITY, _SignalTypes.PropagationType.STATIC_SNAPSHOT)

	# Transient channel (sound)
	register_channel(_SignalTypes.SOUND, _SignalTypes.PropagationType.TRANSIENT)

	# Olfactory / lingering channels (decay 0.95, diffuses & drifts with wind)
	register_channel(_SignalTypes.SCENT_PREDATOR, _SignalTypes.PropagationType.DIFFUSE_DRIFT, 0.96, 0.04)
	register_channel(_SignalTypes.SCENT_PREY,     _SignalTypes.PropagationType.DIFFUSE_DRIFT, 0.96, 0.04)
	register_channel(_SignalTypes.SCENT_BLOOD,    _SignalTypes.PropagationType.DIFFUSE_DRIFT, 0.93, 0.05)
	register_channel(_SignalTypes.SCENT_SMOKE,    _SignalTypes.PropagationType.DIFFUSE_DRIFT, 0.90, 0.06)

	# Seed active inventories from any pre-existing non-empty inventories
	_active_inventories.clear()
	if world != null:
		var reg = world.get_registry()
		if reg != null:
			var inv_store: Dictionary = reg.get_store(&"InventoryComponent")
			for cid: int in inv_store:
				var inv = inv_store[cid]
				if inv != null and not inv.items.is_empty():
					_active_inventories[cid] = true

	print("[SignalSystem] Initialized with %d channels (%dx%d). Priority 220." % [_channels.size(), _width, _height])

## Event-driven O(1) cache update when a tile's terrain type changes dynamically.
## Prevents stale signal data without requiring a 16,384-tile loop on every tick.
func notify_tile_type_changed(pos: Vector2i, new_tile_type: int) -> void:
	if not _terrain_cache_ready:
		_build_terrain_cache()
	var idx: int = pos.y * _width + pos.x
	if idx < 0 or idx >= _total_tiles:
		return

	var trav_val: float = 1.0
	var aff_val: int = _TileAffordance.WALKABLE

	match new_tile_type:
		_TileTypes.Type.MUD:
			trav_val = 0.6
			aff_val = _TileAffordance.WALKABLE | _TileAffordance.HAZARD_SLOW
		_TileTypes.Type.STONE:
			trav_val = 0.9
			aff_val = _TileAffordance.WALKABLE
		_:
			trav_val = 1.0
			aff_val = _TileAffordance.WALKABLE

	if _clean_trav_cache.size() > idx:
		_clean_trav_cache[idx] = trav_val
	if _base_trav_cache.size() > idx:
		_base_trav_cache[idx] = trav_val
	if _base_affordance_cache.size() > idx:
		_base_affordance_cache[idx] = aff_val
	if _veg_affordance_cache.size() > idx:
		_veg_affordance_cache[idx] = aff_val
	if _combined_affordance_map.size() > idx:
		_combined_affordance_map[idx] = aff_val
	if affordance_map.size() > idx:
		affordance_map[idx] = aff_val
	if _channels.has(_SignalTypes.TRAVERSABILITY):
		_channels[_SignalTypes.TRAVERSABILITY].data[idx] = trav_val

	if world != null:
		world.mark_render_dirty()

func _build_terrain_cache() -> void:
	if world == null:
		return
	var reg = world.get_registry()
	if reg == null:
		return
	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	if tile_store.is_empty():
		return

	_clean_trav_cache.resize(_total_tiles)
	_clean_trav_cache.fill(1.0)
	_base_trav_cache.resize(_total_tiles)
	_base_trav_cache.fill(1.0)
	_base_affordance_cache.resize(_total_tiles)
	_base_affordance_cache.fill(_TileAffordance.WALKABLE)

	for eid: int in tile_store:
		var tile = tile_store[eid]
		var idx: int = tile.position.y * _width + tile.position.x
		if idx >= 0 and idx < _total_tiles:
			match tile.tile_type:
				_TileTypes.Type.MUD:
					_clean_trav_cache[idx] = 0.6
					_base_trav_cache[idx] = 0.6
					_base_affordance_cache[idx] = _TileAffordance.WALKABLE | _TileAffordance.HAZARD_SLOW
				_TileTypes.Type.STONE:
					_clean_trav_cache[idx] = 0.9
					_base_trav_cache[idx] = 0.9
					_base_affordance_cache[idx] = _TileAffordance.WALKABLE
				_:
					_clean_trav_cache[idx] = 1.0
					_base_trav_cache[idx] = 1.0
					_base_affordance_cache[idx] = _TileAffordance.WALKABLE
	_terrain_cache_ready = true

func tick(_tick_number: int) -> void:
	var reg = world.get_registry()

	# 1. Reset transient channels from the previous tick
	for ch in _channels.values():
		if ch.propagation_type == _SignalTypes.PropagationType.TRANSIENT:
			ch.fill(0.0)

	# 2. Reset static snapshot channels (restored in step 3 via memcpy from pre-cached buffers)
	for ch in _channels.values():
		if ch.propagation_type == _SignalTypes.PropagationType.STATIC_SNAPSHOT:
			if ch.name != _SignalTypes.TRAVERSABILITY and ch.name != _SignalTypes.FOOD_PLANT and ch.name != _SignalTypes.COVER and ch.name != _SignalTypes.HYDRATION and ch.name != _SignalTypes.HAZARD:
				ch.fill(0.0)

	# 3. Built-in physical simulation providers (starts with instant base terrain copy)
	_sample_terrain_and_traversability(reg)
	_sample_hazards(reg)
	_sample_fluids(reg)
	_sample_vegetation(reg)
	_sample_inventory_items(reg)

	# 4. Process dynamic ECS emitters
	_process_signal_emitters(reg)

	# 5. Execute any registered external / modular providers
	for provider: Callable in _custom_providers:
		provider.call(reg, self)

	# 6. Advance lingering atmospheric signals (decay & wind advection)
	var wind_dir: Vector2 = world.wind_direction
	var wind_str: float   = world.wind_strength
	for ch in _channels.values():
		if ch.propagation_type == _SignalTypes.PropagationType.DIFFUSE_DRIFT:
			ch.decay_and_advect(wind_dir, wind_str)

# ===========================================================================
# Channel & Provider Registry API
# ===========================================================================

## Register a new channel dynamically (e.g. from mods or other modules).
func register_channel(
	channel_name: StringName,
	prop_type: int = _SignalTypes.PropagationType.STATIC_SNAPSHOT,
	decay_rate: float = 0.95,
	diffuse_rate: float = 0.04
):
	if _channels.has(channel_name):
		return _channels[channel_name]

	var grid = _SignalGrid.new(
		channel_name,
		prop_type,
		decay_rate,
		diffuse_rate,
		_width,
		_height
	)
	_channels[channel_name] = grid
	return grid

## Return the SignalGrid for the given channel name, or null if unmapped.
func get_channel(channel_name: StringName):
	return _channels.get(channel_name, null)

## True when a channel with this name is registered.
func has_channel(channel_name: StringName) -> bool:
	return _channels.has(channel_name)

## Register an external signal provider function.
## Signature: func(reg: ComponentRegistry, signals: SignalSystem) -> void
func register_provider(provider_fn: Callable) -> void:
	if not _custom_providers.has(provider_fn):
		_custom_providers.append(provider_fn)

# ===========================================================================
# Sparse Active Inventory API
# ===========================================================================

## Register an entity as holding active items in its inventory.
func register_active_inventory(container_id: int) -> void:
	_active_inventories[container_id] = true

## Unregister an entity whose inventory has been emptied.
func unregister_active_inventory(container_id: int) -> void:
	_active_inventories.erase(container_id)

# ===========================================================================
# Public Query & Perception API for Creature AI
# ===========================================================================

## Returns normalized signal intensity [0.0, 1.0] at pos for the specified channel.
func get_signal(channel_name: StringName, pos: Vector2i) -> float:
	var ch = _channels.get(channel_name, null)
	return ch.get_value(pos) if ch != null else 0.0

## Checks whether a signal is active (intensity >= min_intensity) at pos.
func has_signal_at(channel_name: StringName, pos: Vector2i, min_intensity: float = 0.01) -> bool:
	return get_signal(channel_name, pos) >= min_intensity

## Inspects all signals present at pos with intensity >= min_intensity.
## Returns Dictionary: { channel_name (StringName) -> intensity (float 0.0-1.0) }
func get_signals_at(pos: Vector2i, min_intensity: float = 0.01) -> Dictionary:
	var result: Dictionary = {}
	for ch_name: StringName in _channels.keys():
		var val: float = get_signal(ch_name, pos)
		if val >= min_intensity:
			result[ch_name] = val
	return result

## Returns the raw 64-bit affordance bitmask at pos.
func get_affordance(pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= _width or pos.y < 0 or pos.y >= _height:
		return 0
	return affordance_map[pos.y * _width + pos.x]

## Checks whether a specific affordance flag is active at pos.
func has_affordance(pos: Vector2i, flag: int) -> bool:
	return (get_affordance(pos) & flag) != 0

## Computes the spatial gradient vector for a channel at pos (points towards highest intensity).
func get_gradient(channel_name: StringName, pos: Vector2i) -> Vector2:
	var ch = _channels.get(channel_name, null)
	return ch.sample_gradient(pos) if ch != null else Vector2.ZERO

## Broadcasts a signal with intensity [0.0, 1.0].
func broadcast_signal(channel_name: StringName, pos: Vector2i, intensity: float, radius: int = 0) -> void:
	var ch = _channels.get(channel_name, null)
	if ch != null:
		ch.add_impulse(pos, intensity, radius)

## Broadcasts an acoustic sound impulse that drops off with distance.
func emit_sound(pos: Vector2i, volume: float, radius: int = 6) -> void:
	broadcast_signal(_SignalTypes.SOUND, pos, volume, radius)

## Emits a lingering scent puff at pos.
func emit_scent(channel_name: StringName, pos: Vector2i, intensity: float, radius: int = 1) -> void:
	broadcast_signal(channel_name, pos, intensity, radius)

## Adds an impulse to any arbitrary registered channel (alias for broadcast_signal).
func emit_impulse(channel_name: StringName, pos: Vector2i, intensity: float, radius: int) -> void:
	broadcast_signal(channel_name, pos, intensity, radius)

# ===========================================================================
# Physical State Sample Providers
# ===========================================================================

func _sample_terrain_and_traversability(reg) -> void:
	if not _terrain_cache_ready:
		_build_terrain_cache()
	if not _veg_cache_ready:
		_build_veg_cache(reg)
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	if not _fluid_cache_ready or fluid_store.size() != _cached_fluid_count or (world != null and world.is_rare_tick()):
		_build_fluid_cache(reg)
	var trav_grid = _channels[_SignalTypes.TRAVERSABILITY]
	trav_grid.data = _base_trav_cache.duplicate()
	affordance_map = _combined_affordance_map.duplicate()

func _build_climate_hazard_cache(reg) -> void:
	if _cached_climate_hazard.size() != _total_tiles:
		_cached_climate_hazard.resize(_total_tiles)
	_cached_climate_hazard.fill(0.0)
	_climate_lethal_indices.clear()

	var tile_store: Dictionary   = reg.get_store(&"TileComponent")
	var matter_store: Dictionary = reg.get_store(&"MatterComponent")

	for eid: int in tile_store:
		var matter = matter_store.get(eid, null)
		if matter != null and (matter.temperature_c > 65.0 or matter.temperature_c < -25.0):
			var tile = tile_store[eid]
			var idx: int = tile.position.y * _width + tile.position.x
			var temp_hazard: float = 0.0
			if matter.temperature_c > 65.0:
				temp_hazard = clampf((matter.temperature_c - 65.0) / 40.0, 0.2, 1.0)
			else:
				temp_hazard = clampf((-25.0 - matter.temperature_c) / 30.0, 0.2, 1.0)
			_cached_climate_hazard[idx] = temp_hazard
			if temp_hazard >= 0.7:
				_climate_lethal_indices.append(idx)

	_climate_hazard_ready = true

func _sample_hazards(reg) -> void:
	var hazard_grid = _channels[_SignalTypes.HAZARD]
	var tile_store: Dictionary = reg.get_store(&"TileComponent")

	# Rebuild climate hazard baseline only on long ticks (when climate changes) or first run
	if not _climate_hazard_ready or (world != null and world.is_long_tick()):
		_build_climate_hazard_cache(reg)

	hazard_grid.data = _cached_climate_hazard.duplicate()

	for idx: int in _climate_lethal_indices:
		affordance_map[idx] |= _TileAffordance.HAZARD_LETHAL

	# 1. Fire / Combustion
	var burn_store: Dictionary = reg.get_store(&"BurningComponent")
	for eid: int in burn_store:
		var burning = burn_store[eid]
		var tile = tile_store.get(eid, null)
		if tile != null:
			var idx: int = tile.position.y * _width + tile.position.x
			hazard_grid.data[idx] = maxf(hazard_grid.data[idx], burning.intensity)
			affordance_map[idx] |= _TileAffordance.HAZARD_LETHAL
			affordance_map[idx] &= ~_TileAffordance.WALKABLE

			# Burning emit smoke scent
			emit_scent(_SignalTypes.SCENT_SMOKE, tile.position, burning.intensity * 0.4, 1)

	# 2. Toxic Gas
	var gas_store: Dictionary = reg.get_store(&"GasComponent")
	for eid: int in gas_store:
		var gas = gas_store[eid]
		var mat_data: Dictionary = _MaterialTypes.get_data(gas.material_id)
		var toxicity: float = mat_data.get("toxicity", 0.0) as float
		if toxicity > 0.0:
			var tile = tile_store.get(eid, null)
			if tile != null:
				var idx: int = tile.position.y * _width + tile.position.x
				var hazard_level: float = clampf(toxicity * gas.concentration, 0.0, 1.0)
				hazard_grid.data[idx] = maxf(hazard_grid.data[idx], hazard_level)
				if hazard_level >= 0.4:
					affordance_map[idx] |= _TileAffordance.HAZARD_LETHAL

	# 3. Chemical Contaminants (acid/miasma)
	var contam_store: Dictionary = reg.get_store(&"ContaminantComponent")
	for eid: int in contam_store:
		var contam = contam_store[eid]
		var tile = tile_store.get(eid, null)
		if tile != null:
			var idx: int = tile.position.y * _width + tile.position.x
			var tox_corr: float = clampf(contam.toxicity + contam.corrosion, 0.0, 1.0)
			hazard_grid.data[idx] = maxf(hazard_grid.data[idx], tox_corr)
			if tox_corr >= 0.5:
				affordance_map[idx] |= _TileAffordance.HAZARD_LETHAL

func _build_fluid_cache(reg) -> void:
	if not _terrain_cache_ready:
		_build_terrain_cache()
	if not _veg_cache_ready:
		_build_veg_cache(reg)

	if _cached_hydration.size() != _total_tiles:
		_cached_hydration.resize(_total_tiles)
	_cached_hydration.fill(0.0)

	_combined_affordance_map = _veg_affordance_cache.duplicate()
	_base_trav_cache = _clean_trav_cache.duplicate()

	var fluid_store: Dictionary  = reg.get_store(&"FluidComponent")
	var tile_store: Dictionary   = reg.get_store(&"TileComponent")
	var contam_store: Dictionary = reg.get_store(&"ContaminantComponent")
	var has_contam: bool         = not contam_store.is_empty()

	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		if fluid == null or not fluid.settled or fluid.material_id != _MaterialTypes.Type.WATER:
			continue
		var tile = tile_store.get(eid, null)
		if tile == null:
			continue
		var idx: int = tile.position.y * _width + tile.position.x
		if idx < 0 or idx >= _total_tiles:
			continue

		var is_contaminated: bool = false
		if has_contam:
			var contam = contam_store.get(eid, null)
			is_contaminated = contam != null and (contam.toxicity > 0.2 or contam.corrosion > 0.2)

		if not is_contaminated:
			_cached_hydration[idx] = clampf(fluid.volume, 0.0, 1.0)
			_combined_affordance_map[idx] |= _TileAffordance.DRINKABLE

		# Depth / swimming check on base affordance & traversability
		if fluid.volume >= 0.4:
			_combined_affordance_map[idx] |= _TileAffordance.SWIMMABLE
			_combined_affordance_map[idx] &= ~_TileAffordance.WALKABLE
			_base_trav_cache[idx] = minf(_base_trav_cache[idx], 0.4)
		elif fluid.volume >= 0.15:
			_combined_affordance_map[idx] |= (_TileAffordance.WALKABLE | _TileAffordance.HAZARD_SLOW)
			_combined_affordance_map[idx] &= ~_TileAffordance.SWIMMABLE
			_base_trav_cache[idx] = minf(_base_trav_cache[idx], 0.7)
		else:
			_combined_affordance_map[idx] |= _TileAffordance.WALKABLE
			_combined_affordance_map[idx] &= ~_TileAffordance.SWIMMABLE

	_cached_fluid_count = fluid_store.size()
	_fluid_cache_ready = true

func _sample_fluids(reg) -> void:
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	if not _fluid_cache_ready or fluid_store.size() != _cached_fluid_count or (world != null and world.is_rare_tick()):
		_build_fluid_cache(reg)
		affordance_map = _combined_affordance_map.duplicate()

	var hydra_grid = _channels[_SignalTypes.HYDRATION]
	hydra_grid.data = _cached_hydration.duplicate()

	var tile_store: Dictionary   = reg.get_store(&"TileComponent")
	var contam_store: Dictionary = reg.get_store(&"ContaminantComponent")
	var has_contam: bool         = not contam_store.is_empty()
	var trav_grid                = _channels[_SignalTypes.TRAVERSABILITY]

	# Fast scan: only iterate unsettled (dynamic) fluids, hazardous fluids, or if contaminants are present
	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		if fluid == null:
			continue
		if fluid.settled and fluid.material_id == _MaterialTypes.Type.WATER and not has_contam:
			continue

		var tile = tile_store.get(eid, null)
		if tile == null:
			continue
		var idx: int = tile.position.y * _width + tile.position.x

		if fluid.material_id == _MaterialTypes.Type.WATER:
			var is_contaminated: bool = false
			if has_contam:
				var contam = contam_store.get(eid, null)
				is_contaminated = contam != null and (contam.toxicity > 0.2 or contam.corrosion > 0.2)

			if not is_contaminated:
				hydra_grid.data[idx] = clampf(fluid.volume, 0.0, 1.0)
				affordance_map[idx] |= _TileAffordance.DRINKABLE
			else:
				hydra_grid.data[idx] = 0.0
				affordance_map[idx] &= ~_TileAffordance.DRINKABLE

			if fluid.volume >= 0.4:
				affordance_map[idx] |= _TileAffordance.SWIMMABLE
				affordance_map[idx] &= ~_TileAffordance.WALKABLE
				trav_grid.data[idx] = minf(trav_grid.data[idx], 0.4)
			elif fluid.volume >= 0.15:
				affordance_map[idx] |= (_TileAffordance.WALKABLE | _TileAffordance.HAZARD_SLOW)
				affordance_map[idx] &= ~_TileAffordance.SWIMMABLE
				trav_grid.data[idx] = minf(trav_grid.data[idx], 0.7)
			else:
				affordance_map[idx] |= _TileAffordance.WALKABLE
				affordance_map[idx] &= ~_TileAffordance.SWIMMABLE
		elif fluid.material_id == _MaterialTypes.Type.GREEK_FIRE:
			_channels[_SignalTypes.HAZARD].data[idx] = 1.0
			affordance_map[idx] |= _TileAffordance.HAZARD_LETHAL
			affordance_map[idx] &= ~_TileAffordance.WALKABLE

func _build_veg_cache(reg) -> void:
	if not _terrain_cache_ready:
		_build_terrain_cache()

	if _cached_food_plant.size() != _total_tiles:
		_cached_food_plant.resize(_total_tiles)
		_cached_cover.resize(_total_tiles)
		_combined_affordance_map.resize(_total_tiles)

	_cached_food_plant.fill(0.0)
	_cached_cover.fill(0.0)
	_combined_affordance_map = _base_affordance_cache.duplicate()

	var veg_store:  Dictionary = reg.get_store(&"VegetationComponent")
	var tile_store: Dictionary = reg.get_store(&"TileComponent")

	for eid: int in veg_store:
		var veg = veg_store[eid]
		var tile = tile_store.get(eid, null)
		if tile == null:
			continue
		var idx: int = tile.position.y * _width + tile.position.x
		if idx < 0 or idx >= _total_tiles:
			continue

		# Edible plant nutrition for herbivores
		if veg.growth_stage >= 1:
			var food_val: float = float(veg.growth_stage) / 3.0
			_cached_food_plant[idx] = food_val
			_combined_affordance_map[idx] |= _TileAffordance.GRAZEABLE

		# Cover / Concealment
		match veg.veg_type:
			_VegetationTypes.Type.PINE_TREE, _VegetationTypes.Type.OAK_TREE:
				_cached_cover[idx] = 1.0
				_combined_affordance_map[idx] |= _TileAffordance.COVER
			_VegetationTypes.Type.SHRUB:
				_cached_cover[idx] = 0.7
				_combined_affordance_map[idx] |= _TileAffordance.COVER
			_VegetationTypes.Type.TALL_GRASS:
				_cached_cover[idx] = 0.4
				_combined_affordance_map[idx] |= _TileAffordance.COVER

	# Write directly to persistent channel data buffers without per-tick allocations
	if _channels.has(_SignalTypes.FOOD_PLANT):
		_channels[_SignalTypes.FOOD_PLANT].data = _cached_food_plant.duplicate()
	if _channels.has(_SignalTypes.COVER):
		_channels[_SignalTypes.COVER].data = _cached_cover.duplicate()

	_veg_affordance_cache = _combined_affordance_map.duplicate()
	_veg_cache_ready = true
	_fluid_cache_ready = false # ensure fluid layer builds on top of updated vegetation affordances

func _sample_vegetation(reg) -> void:
	if not _veg_cache_ready or (world != null and world.is_rare_tick()):
		_build_veg_cache(reg)

func _sample_inventory_items(reg) -> void:
	if _active_inventories.is_empty():
		return

	var meat_food_grid = _channels[_SignalTypes.FOOD_MEAT]
	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	var inv_store:  Dictionary = reg.get_store(&"InventoryComponent")

	var dead_containers: Array[int] = []

	for container_id: int in _active_inventories:
		var inv = inv_store.get(container_id, null)
		if inv == null or inv.items.is_empty():
			dead_containers.append(container_id)
			continue

		# Lazy cache initialization if directly populated
		if not inv.has_carnivore_food and not inv.has_blood_scent and inv.max_calories == 0:
			inv.update_cache(reg)

		if not inv.has_carnivore_food and not inv.has_blood_scent:
			continue

		var tile = tile_store.get(container_id, null)
		if tile == null:
			continue
		var idx: int = tile.position.y * _width + tile.position.x

		if inv.has_carnivore_food and inv.max_calories > 0:
			meat_food_grid.data[idx] = clampf(float(inv.max_calories) / 1000.0, 0.1, 1.0)
			affordance_map[idx] |= _TileAffordance.CARNIVORE_FOOD

		# Loose grass items in tile inventory (yielded from plants or dropped)
		var grass_qty: int = inv.get_total_quantity_of_type(reg, _ItemTypes.Type.GRASS)
		if grass_qty > 0:
			var food_plant_grid = _channels[_SignalTypes.FOOD_PLANT]
			food_plant_grid.data[idx] = maxf(food_plant_grid.data[idx], clampf(float(grass_qty) / 3.0, 0.4, 1.0))
			affordance_map[idx] |= _TileAffordance.GRAZEABLE

		# Meat emits blood scent downwind
		if inv.has_blood_scent:
			emit_scent(_SignalTypes.SCENT_BLOOD, tile.position, 0.6, 1)

	for dead_id: int in dead_containers:
		_active_inventories.erase(dead_id)

func _process_signal_emitters(reg) -> void:
	var emitter_store: Dictionary = reg.get_store(&"SignalEmitterComponent")
	var tile_store:    Dictionary = reg.get_store(&"TileComponent")
	for eid: int in emitter_store:
		var emitter = emitter_store[eid]
		if not emitter.enabled or emitter.channel.is_empty():
			continue

		var tile = tile_store.get(eid, null)
		if tile != null:
			broadcast_signal(emitter.channel, tile.position, emitter.intensity, emitter.radius)

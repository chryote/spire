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

## Registry of all active channels: StringName -> SignalGrid
var _channels: Dictionary = {}

## Custom external provider callables: Array[Callable]
## Each callable receives `(reg: ComponentRegistry, signals: SignalSystem)`
var _custom_providers: Array[Callable] = []

## 64-bit affordance bitmask per tile (width x height).
var affordance_map: PackedInt64Array

## Pre-cached static terrain baseline buffers to eliminate 16,384 GDScript iterations per tick
var _base_trav_cache:       PackedFloat32Array = PackedFloat32Array()
var _base_affordance_cache: PackedInt64Array   = PackedInt64Array()
var _terrain_cache_ready:   bool               = false

## Pre-cached static vegetation baseline buffers to eliminate 12,000 GDScript iterations per tick
var _cached_food_plant:       PackedFloat32Array = PackedFloat32Array()
var _cached_cover:            PackedFloat32Array = PackedFloat32Array()
var _combined_affordance_map: PackedInt64Array   = PackedInt64Array()
var _veg_cache_ready:         bool               = false

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

	print("[SignalSystem] Initialized with %d channels (%dx%d). Priority 220." % [_channels.size(), _width, _height])

## Event-driven O(1) cache update when a tile's terrain type changes dynamically.
## Prevents stale signal data without requiring a 16,384-tile loop on every tick.
func notify_tile_type_changed(pos: Vector2i, new_tile_type: int) -> void:
	if not _terrain_cache_ready:
		_build_terrain_cache()
	var idx: int = pos.y * _width + pos.x
	if idx < 0 or idx >= _total_tiles:
		return

	match new_tile_type:
		_TileTypes.Type.MUD:
			_base_trav_cache[idx] = 0.6
			_base_affordance_cache[idx] = _TileAffordance.WALKABLE | _TileAffordance.HAZARD_SLOW
		_TileTypes.Type.STONE:
			_base_trav_cache[idx] = 0.9
			_base_affordance_cache[idx] = _TileAffordance.WALKABLE
		_:
			_base_trav_cache[idx] = 1.0
			_base_affordance_cache[idx] = _TileAffordance.WALKABLE

	if _combined_affordance_map.size() > idx:
		_combined_affordance_map[idx] = _base_affordance_cache[idx]

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
					_base_trav_cache[idx] = 0.6
					_base_affordance_cache[idx] = _TileAffordance.WALKABLE | _TileAffordance.HAZARD_SLOW
				_TileTypes.Type.STONE:
					_base_trav_cache[idx] = 0.9
					_base_affordance_cache[idx] = _TileAffordance.WALKABLE
				_:
					_base_trav_cache[idx] = 1.0
					_base_affordance_cache[idx] = _TileAffordance.WALKABLE
	_terrain_cache_ready = true

func tick(_tick_number: int) -> void:
	var reg = world.get_registry()

	# 1. Reset transient channels from the previous tick
	for ch in _channels.values():
		if ch.propagation_type == _SignalTypes.PropagationType.TRANSIENT:
			ch.fill(0.0)

	# 2. Reset static snapshot channels (traversability, vegetation, and affordance restored in step 3 via memcpy)
	for ch in _channels.values():
		if ch.propagation_type == _SignalTypes.PropagationType.STATIC_SNAPSHOT:
			if ch.name != _SignalTypes.TRAVERSABILITY and ch.name != _SignalTypes.FOOD_PLANT and ch.name != _SignalTypes.COVER:
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
	var trav_grid = _channels[_SignalTypes.TRAVERSABILITY]
	trav_grid.data = _base_trav_cache.duplicate()
	affordance_map = _combined_affordance_map.duplicate()

func _sample_hazards(reg) -> void:
	var hazard_grid = _channels[_SignalTypes.HAZARD]
	var tile_store: Dictionary = reg.get_store(&"TileComponent")

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

	# 4. Thermodynamic Extreme Temperatures (sampled on Rare Ticks or severe seasonal weather)
	# Note: Local combustion fires are already sampled above in step 1 via burn_store.
	# Scan tile entities only (loose items in containers do not define terrain hazard cells)
	if world != null and (world.is_rare_tick() or absf(world.season_temp_mod) > 0.7):
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
				hazard_grid.data[idx] = maxf(hazard_grid.data[idx], temp_hazard)
				if temp_hazard >= 0.7:
					affordance_map[idx] |= _TileAffordance.HAZARD_LETHAL

func _sample_fluids(reg) -> void:
	var hydra_grid = _channels[_SignalTypes.HYDRATION]
	var trav_grid  = _channels[_SignalTypes.TRAVERSABILITY]
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var tile_store:  Dictionary = reg.get_store(&"TileComponent")

	for eid: int in fluid_store:
		var fluid = fluid_store[eid]
		var tile = tile_store.get(eid, null)
		if tile == null:
			continue
		var idx: int = tile.position.y * _width + tile.position.x

		# Check water vs hazardous fluid
		if fluid.material_id == _MaterialTypes.Type.WATER:
			# Check contaminants
			var contam = reg.get_component(eid, &"ContaminantComponent")
			var is_contaminated: bool = contam != null and (contam.toxicity > 0.2 or contam.corrosion > 0.2)
			if not is_contaminated:
				hydra_grid.data[idx] = clampf(fluid.volume, 0.0, 1.0)
				affordance_map[idx] |= _TileAffordance.DRINKABLE

			# Depth / swimming check
			if fluid.volume >= 0.4:
				affordance_map[idx] |= _TileAffordance.SWIMMABLE
				trav_grid.data[idx] = minf(trav_grid.data[idx], 0.4)
			elif fluid.volume >= 0.15:
				affordance_map[idx] |= _TileAffordance.HAZARD_SLOW
				trav_grid.data[idx] = minf(trav_grid.data[idx], 0.7)
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

	_veg_cache_ready = true

func _sample_vegetation(reg) -> void:
	if not _veg_cache_ready or (world != null and world.is_rare_tick()):
		_build_veg_cache(reg)

	var plant_food_grid = _channels[_SignalTypes.FOOD_PLANT]
	var cover_grid      = _channels[_SignalTypes.COVER]
	plant_food_grid.data = _cached_food_plant.duplicate()
	cover_grid.data = _cached_cover.duplicate()

func _sample_inventory_items(reg) -> void:
	var inv_store: Dictionary = reg.get_store(&"InventoryComponent")
	if inv_store.is_empty():
		return

	var meat_food_grid = _channels[_SignalTypes.FOOD_MEAT]
	var tile_store: Dictionary = reg.get_store(&"TileComponent")

	for container_id: int in inv_store:
		var inv = inv_store[container_id]
		if inv.items.is_empty():
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

		# Meat emits blood scent downwind
		if inv.has_blood_scent:
			emit_scent(_SignalTypes.SCENT_BLOOD, tile.position, 0.6, 1)

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

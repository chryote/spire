## RainSystem.gd
## Priority 6 — runs after WeatherSystem (5), which writes wind state.
##
## Drives a spatial rain field using 2D FastNoiseLite sampled at a drifting
## offset that advances each tick in the current wind direction.
##
## Season modulation (world.season):
##   SPRING (0): threshold −0.12 → more rain
##   SUMMER (1): threshold +0.05 → moderate
##   AUTUMN (2): threshold −0.10 → more rain
##   WINTER (3): threshold +0.18 → mostly dry (snow suppresses liquid rain)
##
## Per rainy tick on a tile:
##   BiomeComponent.moisture    += intensity * MOISTURE_GAIN   (capped 1.0)
##   BiomeComponent.temperature -= intensity * RAIN_COOLING    (floored 0.0)
##
## World fields read:
##   wind_direction, wind_strength, season
class_name RainSystem
extends "res://core/SystemBase.gd"

const _RainComponent = preload("res://modules/weather/components/RainComponent.gd")
const _TileTypes     = preload("res://modules/terrain/data/TileTypes.gd")
const _MaterialTypes = preload("res://modules/matter/data/MaterialTypes.gd")


## Noise value above which a tile is considered rainy (0.0–1.0 range after remap).
const BASE_THRESHOLD: float = 0.38

## Rain field drift speed: tiles per tick per unit of wind strength.
const DRIFT_SPEED: float = 0.08

## How many ticks to skip between rain field updates (10 TPS = 1 update/sec).
const TICK_STRIDE: int = 10

## Moisture added to BiomeComponent per tick per unit intensity (scaled for 10-tick stride).
const MOISTURE_GAIN: float = 0.006

## Temperature reduction applied per tick per unit intensity (scaled for 10-tick stride).
const RAIN_COOLING: float = 0.009

## Base drying/evaporation rate per slice update when not raining.
const DRYING_RATE: float = 0.008

## Moisture threshold at or below which saturated mud dries back to solid ground.
const MUD_DRY_THRESHOLD: float = 0.65

## Per-season adjustment to BASE_THRESHOLD (negative = lower threshold = more rain).
const SEASON_THRESHOLD_MOD: Array = [-0.12, 0.05, -0.10, 0.18]

var _noise: FastNoiseLite = null
var _rng: RandomNumberGenerator = null

## Accumulated drift offset so rain patches move continuously with the wind.
var _drift: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	_noise = FastNoiseLite.new()
	_noise.seed       = _rng.randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency  = 0.025

	print("[Rain] Initialized.")

const SLICE_COUNT: int = 10
var _slice_buckets: Array[PackedInt32Array] = []
var _slice_pos_x: Array[PackedFloat32Array] = []
var _slice_pos_y: Array[PackedFloat32Array] = []
var _slice_biome: Array[Array] = []
var _slice_tile: Array[Array] = []
var _slice_rain: Array[Array] = []
var _cached_store_size: int = -1

var _active_mud_tiles: Dictionary = {}
var _wetted_slices: Array[Dictionary] = []
var _rain_pool: Array = []

func _rebuild_buckets(reg, tile_store: Dictionary) -> void:
	_slice_buckets.clear()
	_slice_pos_x.clear()
	_slice_pos_y.clear()
	_slice_biome.clear()
	_slice_tile.clear()
	_slice_rain.clear()
	_active_mud_tiles.clear()
	_wetted_slices.clear()

	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var rain_store: Dictionary  = reg.get_store(&"RainComponent")

	for i in range(SLICE_COUNT):
		_slice_buckets.append(PackedInt32Array())
		_slice_pos_x.append(PackedFloat32Array())
		_slice_pos_y.append(PackedFloat32Array())
		_slice_biome.append([])
		_slice_tile.append([])
		_slice_rain.append([])
		_wetted_slices.append({})

	for entity_id: int in tile_store:
		var tile = tile_store[entity_id]
		var b_idx: int = entity_id % SLICE_COUNT
		_slice_buckets[b_idx].append(entity_id)
		_slice_pos_x[b_idx].append(float(tile.position.x))
		_slice_pos_y[b_idx].append(float(tile.position.y))
		_slice_tile[b_idx].append(tile)
		_slice_biome[b_idx].append(biome_store.get(entity_id, null))
		_slice_rain[b_idx].append(rain_store.get(entity_id, null))
		if tile.tile_type == _TileTypes.Type.MUD and tile.original_tile_type != -1:
			_active_mud_tiles[entity_id] = true

	for entity_id: int in biome_store:
		var b = biome_store[entity_id]
		if b != null and b.moisture > b.base_moisture:
			var b_idx: int = entity_id % SLICE_COUNT
			_wetted_slices[b_idx][entity_id] = true

	_cached_store_size = tile_store.size()

func tick(tick_number: int) -> void:
	var reg = world.get_registry()
	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	if tile_store.is_empty():
		return

	if _cached_store_size != tile_store.size():
		_rebuild_buckets(reg, tile_store)

	var slice_mod: int = tick_number % SLICE_COUNT

	# --- System condition gate ---
	# If current weather condition does not permit rain, clear active rain and process drying/evaporation
	if not world.rain_allowed:
		var rain_store: Dictionary = reg.get_store(&"RainComponent")
		if not rain_store.is_empty():
			var to_remove: Array = rain_store.keys()
			for eid: int in to_remove:
				reg.remove(eid, &"RainComponent")
			for b in range(SLICE_COUNT):
				var r_arr: Array = _slice_rain[b]
				for i in range(r_arr.size()):
					if r_arr[i] != null:
						_rain_pool.append(r_arr[i])
						r_arr[i] = null

		if not _active_mud_tiles.is_empty():
			_process_mud_drying(reg)
		_process_evaporation(reg, slice_mod)
		return

	var wind_dir: Vector2 = world.wind_direction
	var wind_str: float   = world.wind_strength

	# Advance drift smoothly each tick
	_drift += wind_dir * wind_str * DRIFT_SPEED

	# Effective threshold for this season + wind
	var season: int = world.season
	var threshold: float = BASE_THRESHOLD \
		+ (SEASON_THRESHOLD_MOD[season] as float) \
		- wind_str * 0.08
	var raw_threshold: float = threshold * 2.0 - 1.0
	var inv_one_minus_threshold: float = 1.0 / maxf(0.001, 1.0 - threshold)

	var dx: float = _drift.x
	var dy: float = _drift.y
	var m_gain: float = MOISTURE_GAIN
	var r_cool: float = RAIN_COOLING

	var slice: PackedInt32Array   = _slice_buckets[slice_mod]
	var pos_x: PackedFloat32Array = _slice_pos_x[slice_mod]
	var pos_y: PackedFloat32Array = _slice_pos_y[slice_mod]
	var slice_biome: Array        = _slice_biome[slice_mod]
	var slice_tile: Array         = _slice_tile[slice_mod]
	var slice_rain: Array         = _slice_rain[slice_mod]
	var slice_wetted: Dictionary  = _wetted_slices[slice_mod]
	var slice_size: int           = slice.size()
	var rain_store: Dictionary    = reg.get_store(&"RainComponent")

	for i: int in range(slice_size):
		var entity_id: int = slice[i]

		# Sample the drifting noise field
		var nx: float = pos_x[i] + dx
		var ny: float = pos_y[i] + dy
		var raw_noise: float = _noise.get_noise_2d(nx, ny)

		if raw_noise > raw_threshold:
			var noise_val: float = (raw_noise + 1.0) * 0.5
			# --- Tile is raining ---
			var intensity: float = clampf(
				(noise_val - threshold) * inv_one_minus_threshold, 0.0, 1.0
			)

			var rain = slice_rain[i]
			if rain == null:
				rain = _rain_pool.pop_back() if not _rain_pool.is_empty() else _RainComponent.new()
				slice_rain[i] = rain
				rain_store[entity_id] = rain
			rain.intensity = intensity

			# Update biome state
			var biome = slice_biome[i]
			if biome != null:
				var is_snow: bool = biome.temperature < 0.18
				if is_snow:
					biome.temperature = clampf(biome.temperature + 0.002 * intensity, 0.0, 1.0)
				else:
					biome.moisture    = clampf(biome.moisture + intensity * m_gain, 0.0, 1.0)
					biome.temperature = clampf(biome.temperature - intensity * r_cool, 0.0, 1.0)
					slice_wetted[entity_id] = true

					# --- MUD conversion on saturation (Gap 6) ---
					if biome.moisture >= 1.0:
						var flood_tile = slice_tile[i]
						if flood_tile != null and flood_tile.tile_type != _TileTypes.Type.MUD:
							if flood_tile.original_tile_type == -1:
								flood_tile.original_tile_type = flood_tile.tile_type
							flood_tile.tile_type = _TileTypes.Type.MUD
							_active_mud_tiles[entity_id] = true
							if world != null and world.signals != null:
								world.signals.notify_tile_type_changed(flood_tile.position, _TileTypes.Type.MUD)

							# Sync physical matter
							var matter = reg.get_component(entity_id, &"MatterComponent")
							if matter != null:
								matter.material_id = _MaterialTypes.Type.MUD

							# Kill any vegetation (roots drown)
							if reg.has(entity_id, &"VegetationComponent"):
								reg.remove(entity_id, &"VegetationComponent")
							if reg.has(entity_id, &"GrowthComponent"):
								reg.remove(entity_id, &"GrowthComponent")
							# Update render to mud visuals
							var render = reg.get_component(entity_id, &"RenderComponent")
							if render != null:
								var td: Dictionary = _TileTypes.get_data(_TileTypes.Type.MUD)
								render.glyph    = td.get("glyph",    "~")
								render.fg_color = td.get("fg_color", Color(0.3, 0.25, 0.1))
								render.bg_color = td.get("bg_color", Color(0.15, 0.1, 0.05))
								render.z_layer  = 0

							if world != null:
								world.mark_render_dirty()
		else:
			# Tile is dry
			var rain = slice_rain[i]
			if rain != null:
				_rain_pool.append(rain)
				slice_rain[i] = null
				rain_store.erase(entity_id)

	# Mud drying and evaporation on active sets
	if not _active_mud_tiles.is_empty():
		_process_mud_drying(reg)
	_process_evaporation(reg, slice_mod)

func _process_mud_drying(reg) -> void:
	var tile_store: Dictionary  = reg.get_store(&"TileComponent")
	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var fluid_store: Dictionary = reg.get_store(&"FluidComponent")
	var to_revert: Array[int]   = []

	for eid: int in _active_mud_tiles:
		var flood_tile = tile_store.get(eid, null)
		if flood_tile == null or flood_tile.tile_type != _TileTypes.Type.MUD or flood_tile.original_tile_type == -1:
			to_revert.append(eid)
			continue

		# Guard: Do not dry out if submerged under standing water
		var fluid = fluid_store.get(eid, null)
		if fluid != null and fluid.volume > 0.05:
			continue

		var biome = biome_store.get(eid, null)
		if biome != null and biome.moisture <= MUD_DRY_THRESHOLD:
			var restore_type: int = flood_tile.original_tile_type
			flood_tile.tile_type = restore_type
			flood_tile.original_tile_type = -1
			to_revert.append(eid)

			# Sync matter material
			var matter = reg.get_component(eid, &"MatterComponent")
			if matter != null:
				matter.material_id = _MaterialTypes.TILE_MATERIAL_MAP.get(restore_type, _MaterialTypes.Type.GROUND)

			# Notify signals of restored terrain
			if world != null and world.signals != null:
				world.signals.notify_tile_type_changed(flood_tile.position, restore_type)

			# Restore render visuals
			var render = reg.get_component(eid, &"RenderComponent")
			if render != null:
				var td: Dictionary = _TileTypes.get_data(restore_type)
				render.glyph    = td.get("glyph", ".")
				render.fg_color = td.get("fg_color", Color(0.5, 0.5, 0.5))
				render.bg_color = td.get("bg_color", Color(0.05, 0.05, 0.05))
				render.z_layer  = 0

			if world != null:
				world.mark_render_dirty()

	for eid: int in to_revert:
		_active_mud_tiles.erase(eid)

func _process_evaporation(reg, slice_mod: int = -1) -> void:
	if slice_mod < 0 or slice_mod >= SLICE_COUNT:
		return
	var w_dict: Dictionary = _wetted_slices[slice_mod]
	if w_dict.is_empty():
		return

	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	var rain_store: Dictionary  = reg.get_store(&"RainComponent")
	var to_clean: Array[int]    = []

	for eid: int in w_dict:
		if rain_store.has(eid):
			continue

		var biome = biome_store.get(eid, null)
		if biome == null:
			to_clean.append(eid)
			continue

		if biome.moisture > biome.base_moisture:
			var evap: float = DRYING_RATE * (0.5 + biome.temperature * 0.5)
			biome.moisture = maxf(biome.base_moisture, biome.moisture - evap)
			if biome.moisture <= biome.base_moisture:
				to_clean.append(eid)
		else:
			to_clean.append(eid)

	for eid: int in to_clean:
		w_dict.erase(eid)

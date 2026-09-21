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
var _cached_store_size: int = -1

func _rebuild_buckets(tile_store: Dictionary) -> void:
	_slice_buckets.clear()
	for i in range(SLICE_COUNT):
		_slice_buckets.append(PackedInt32Array())
	for entity_id: int in tile_store:
		_slice_buckets[entity_id % SLICE_COUNT].append(entity_id)
	_cached_store_size = tile_store.size()

func tick(tick_number: int) -> void:
	var reg = world.get_registry()

	# --- System condition gate (Approach 1) ---
	# If current weather condition does not permit rain, clear active rain and exit
	if not world.rain_allowed:
		var rain_store: Dictionary = reg.get_store(&"RainComponent")
		if not rain_store.is_empty():
			var to_remove: Array = rain_store.keys()
			for eid: int in to_remove:
				reg.remove(eid, &"RainComponent")
		return

	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	if tile_store.is_empty():
		return

	if _cached_store_size != tile_store.size():
		_rebuild_buckets(tile_store)

	var wind_dir: Vector2 = world.wind_direction
	var wind_str: float   = world.wind_strength

	# Advance drift smoothly each tick
	_drift += wind_dir * wind_str * DRIFT_SPEED

	# Effective threshold for this season + wind
	var season: int = world.season
	var threshold: float = BASE_THRESHOLD \
		+ (SEASON_THRESHOLD_MOD[season] as float) \
		- wind_str * 0.08

	var slice_mod: int = tick_number % SLICE_COUNT
	var slice: PackedInt32Array = _slice_buckets[slice_mod]

	for entity_id: int in slice:
		var tile = tile_store.get(entity_id, null)
		if tile == null:
			continue
		var pos: Vector2i = tile.position

		# Sample the drifting noise field
		var nx: float = float(pos.x) + _drift.x
		var ny: float = float(pos.y) + _drift.y
		var noise_val: float = (_noise.get_noise_2d(nx, ny) + 1.0) * 0.5  # remap to 0→1

		if noise_val > threshold:
			# --- Tile is raining ---
			var intensity: float = clampf(
				(noise_val - threshold) / (1.0 - threshold), 0.0, 1.0
			)

			var rain = reg.get_component(entity_id, &"RainComponent")
			if rain == null:
				rain = _RainComponent.new()
				reg.add(entity_id, rain)
			rain.intensity = intensity

			# Update biome state
			var biome = reg.get_component(entity_id, &"BiomeComponent")
			if biome != null:
				# --- Snow precipitation (Gap 4) ---
				# Below approx -16 C (temp < 0.18) precipitation falls as snow.
				# Snow doesn't wet soil directly; it adds a small temperature buffer.

				var is_snow: bool = biome.temperature < 0.18
				if is_snow:
					# Snow insulates — nudge temperature slightly upward (like ground cover)
					biome.temperature = clampf(biome.temperature + 0.002 * intensity, 0.0, 1.0)
				else:
					biome.moisture    = clampf(biome.moisture + intensity * MOISTURE_GAIN, 0.0, 1.0)
					biome.temperature = clampf(biome.temperature - intensity * RAIN_COOLING, 0.0, 1.0)

					# --- MUD conversion on saturation (Gap 6) ---
					if biome.moisture >= 1.0:
						var flood_tile = reg.get_component(entity_id, &"TileComponent")
						if flood_tile != null and flood_tile.tile_type != _TileTypes.Type.MUD:
							flood_tile.tile_type = _TileTypes.Type.MUD
							if world != null and world.signals != null:
								world.signals.notify_tile_type_changed(flood_tile.position, _TileTypes.Type.MUD)
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



		else:
			# --- Tile is dry — remove RainComponent if present ---
			if reg.has(entity_id, &"RainComponent"):
				reg.remove(entity_id, &"RainComponent")

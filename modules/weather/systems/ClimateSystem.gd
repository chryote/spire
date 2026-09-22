## ClimateSystem.gd
## Priority 4 — runs before WeatherSystem (5) and RainSystem (6).
##
## Derives the current season from tick_count using Dwarf Fortress-exact
## time constants.  Computes a smooth season_temp_mod (sin curve over the
## full year cycle) and updates every terrain tile's BiomeComponent.temperature.
##
## Time constants (DF-exact):
##   1 day    = 1,200 ticks
##   1 month  = 28,800 ticks  (24 days)
##   1 season = 100,800 ticks (84 days / 3 months)
##   1 year   = 403,200 ticks (4 seasons)
##
## World fields written:
##   season          : int    0=SPRING, 1=SUMMER, 2=AUTUMN, 3=WINTER
##   season_progress : float  0.0→1.0 through the current season
##   season_temp_mod : float  -1.0 (winter) → +1.0 (summer), sin curve
class_name ClimateSystem
extends "res://core/SystemBase.gd"

const SEASON_NAMES: Array = ["SPRING", "SUMMER", "AUTUMN", "WINTER"]

## Cardinal cloud drift directions, one per season.
## SPRING → North, SUMMER → East, AUTUMN → South, WINTER → West.
const SEASON_CLOUD_DIRS: Array = [
	Vector2( 0.0, -1.0),  # SPRING  → North
	Vector2( 1.0,  0.0),  # SUMMER  → East
	Vector2( 0.0,  1.0),  # AUTUMN  → South
	Vector2(-1.0,  0.0),  # WINTER  → West
]

## Amplitude of the seasonal offset applied to each tile's base temperature.
## A value of 0.25 means ±0.25 swing around the latitudinal base.
const SEASON_AMPLITUDE: float = 0.25

## Vegetation growth rate per season: SPRING, SUMMER, AUTUMN, WINTER.
const SEASON_GROWTH_MOD: Array = [0.9, 1.0, 0.5, 0.0]

## 8-directional neighbour offsets (duplicated locally to avoid cross-system coupling).
const _NEIGHBOURS: Array = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                   Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]


## entity_id (int) → base_temperature (float) cached from TerrainGenSystem output.
var _base_temps: Dictionary = {}

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	# TerrainGenSystem has already run (priority 0), so BiomeComponent.temperature
	# holds the local embark tile's base value.  Cache it now before we start overwriting.
	var reg = world.get_registry()
	var store: Dictionary = reg.get_store(&"BiomeComponent")
	for entity_id: int in store:
		var biome = store[entity_id]
		_base_temps[entity_id] = biome.temperature

	# Write initial season state to World
	world.season          = 0
	world.season_progress = 0.0
	world.season_temp_mod = 0.0

	print("[Climate] Initialized — cached %d tile base temperatures." % _base_temps.size())

func tick(tick_number: int) -> void:
	var t: float = float(tick_number)

	# --- Season (DF-exact integer arithmetic) ---
	var new_season: int = (tick_number / world.TICKS_PER_SEASON) % 4
	if new_season != world.season:
		print("[Climate] Season %s → %s  (tick %d, day %d)" % [
			SEASON_NAMES[world.season],
			SEASON_NAMES[new_season],
			tick_number,
			tick_number / world.TICKS_PER_DAY,
		])
		world.season = new_season

	world.season_progress = fmod(t, float(world.TICKS_PER_SEASON)) / float(world.TICKS_PER_SEASON)

	# --- Smooth temperature modifier: sin over full year ---
	# SPRING (season 0, angle≈0):  mod=0 (warming)
	# SUMMER (season 1, angle=π/2): mod=+1 (peak hot)
	# AUTUMN (season 2, angle=π):  mod=0 (cooling)
	# WINTER (season 3, angle=3π/2): mod=-1 (peak cold)
	var year_angle: float = (t / float(world.TICKS_PER_YEAR)) * TAU
	world.season_temp_mod = sin(year_angle)

	# --- Write seasonal growth modifier ---
	world.growth_rate_mod = SEASON_GROWTH_MOD[world.season] as float

	# --- Smooth cloud drift direction: slerp current → next season cardinal ---
	# Transition blending kicks in over the last 20% of each season so the
	# direction rotates gradually rather than snapping on the season boundary.
	var cur_dir: Vector2  = SEASON_CLOUD_DIRS[world.season]         as Vector2
	var next_dir: Vector2 = SEASON_CLOUD_DIRS[(world.season + 1) % 4] as Vector2
	var blend: float = smoothstep(0.80, 1.0, world.season_progress)
	world.cloud_direction = cur_dir.slerp(next_dir, blend).normalized()

	# --- Long Tick Gate: Update per-tile temperatures every 50 ticks (~5s) ---
	# Ambient seasonal curves over 403,200 ticks change imperceptibly per second.
	# Evaluating tiles on Long Tick cuts 98% of per-tick climate workload.
	if tick_number > 1 and tick_number % 50 != 0:
		return

	# --- Update per-tile temperatures ---
	# RainSystem applies cooling on top; preserve fire heat.
	var reg = world.get_registry()
	var season_offset: float = world.season_temp_mod * SEASON_AMPLITUDE
	var burning_store: Dictionary = reg.get_store(&"BurningComponent")
	var has_any_fire: bool = not burning_store.is_empty()

	# Pre-index entity IDs that are burning or adjacent to burning tiles
	# Inverted check: only ~5-25 entities are protected, eliminating 65,536 neighbour lookups per tick.
	var fire_protected_eids: Dictionary = {}
	if has_any_fire:
		for burning_eid: int in burning_store:
			fire_protected_eids[burning_eid] = true
			var b_tile = reg.get_component(burning_eid, &"TileComponent")
			if b_tile != null:
				for nb_offset: Vector2i in _NEIGHBOURS:
					var nid: int = world.get_entity_at(b_tile.position + nb_offset)
					if nid != -1:
						fire_protected_eids[nid] = true

	var biome_store: Dictionary = reg.get_store(&"BiomeComponent")
	for entity_id: int in _base_temps:
		if has_any_fire and fire_protected_eids.has(entity_id):
			continue

		var biome = biome_store.get(entity_id, null)
		if biome != null:
			biome.temperature = clampf((_base_temps[entity_id] as float) + season_offset, 0.0, 1.0)


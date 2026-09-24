## World.gd
## Central ECS singleton — autoloaded as "World".
##
## Responsibilities:
##   - Entity lifecycle (create / destroy)
##   - Component delegation to ComponentRegistry
##   - Spatial tile index (Vector2i → entity_id)
##   - Dwarf-Fortress-style turn tick loop
##   - Module registration (add new modules here)
##
## Adding a new module:
##   1. Create your System (extends SystemBase) in modules/<name>/systems/
##   2. Preload it below and add to _register_modules()
##   3. Done — no other files need changing.
extends Node

# ---------------------------------------------------------------------------
# Preloads — explicit so the script parses cleanly as an autoload
# ---------------------------------------------------------------------------
const _ComponentRegistry  = preload("res://core/ComponentRegistry.gd")
const _SystemBase         = preload("res://core/SystemBase.gd")
const _Query              = preload("res://core/Query.gd")
const _ItemFactory        = preload("res://modules/item/systems/ItemFactory.gd")

const _TerrainGenSystem      = preload("res://modules/terrain/systems/TerrainGenSystem.gd")
const _ClimateSystem         = preload("res://modules/weather/systems/ClimateSystem.gd")
const _WeatherSystem         = preload("res://modules/weather/systems/WeatherSystem.gd")
const _RainSystem            = preload("res://modules/weather/systems/RainSystem.gd")
const _MatterAssignSystem    = preload("res://modules/matter/systems/MatterAssignSystem.gd")
const _PhaseChangeSystem     = preload("res://modules/matter/systems/PhaseChangeSystem.gd")
const _CombustionSystem      = preload("res://modules/matter/systems/CombustionSystem.gd")
const _FluidSystem           = preload("res://modules/matter/systems/FluidSystem.gd")
const _GasSystem             = preload("res://modules/matter/systems/GasSystem.gd")
const _ChemicalReactionSystem= preload("res://modules/matter/systems/ChemicalReactionSystem.gd")
const _DecaySystem           = preload("res://modules/matter/systems/DecaySystem.gd")
const _VegetationSpawnSystem = preload("res://modules/vegetation/systems/VegetationSpawnSystem.gd")
const _VegetationGrowthSystem= preload("res://modules/vegetation/systems/VegetationGrowthSystem.gd")
const _VegetationYieldSystem = preload("res://modules/vegetation/systems/VegetationYieldSystem.gd")
const _ImpactSolverSystem    = preload("res://modules/matter/systems/ImpactSolverSystem.gd")
const _SignalSystem          = preload("res://modules/signal/systems/SignalSystem.gd")
const _CreatureGrowthSystem     = preload("res://modules/creature/systems/CreatureGrowthSystem.gd")
const _TraitSystem              = preload("res://modules/creature/systems/TraitSystem.gd")
const _CreatureBodySystem       = preload("res://modules/creature/systems/CreatureBodySystem.gd")
const _CreatureAISystem         = preload("res://modules/creature/systems/CreatureAISystem.gd")
const _CreatureLocomotionSystem = preload("res://modules/creature/systems/CreatureLocomotionSystem.gd")
const _CreatureAbilitySystem    = preload("res://modules/creature/systems/CreatureAbilitySystem.gd")

# ---------------------------------------------------------------------------
# Map constants
# ---------------------------------------------------------------------------
const MAP_WIDTH: int  = 128
const MAP_HEIGHT: int = 128

## Biome of the active local map tile (0 = BiomeTypes.Type.PLAINS).
var local_biome: int = 0

# ---------------------------------------------------------------------------
# Time constants (Dwarf Fortress-exact)
# ---------------------------------------------------------------------------
const TICKS_PER_DAY:    int = 1_200
const TICKS_PER_MONTH:  int = 28_800   ## 24 days
const TICKS_PER_SEASON: int = 100_800  ## 84 days / 3 months
const TICKS_PER_YEAR:   int = 403_200  ## 4 seasons

# ---------------------------------------------------------------------------
# Temperature scale — change these two values to rescale the whole simulation
# ---------------------------------------------------------------------------
## Celsius at BiomeComponent.temperature = 0.0  (deep winter / frost).
const TEMP_MIN_C: float = -20.0
## Celsius at BiomeComponent.temperature = 1.0  (extreme summer heat peak).
const TEMP_MAX_C: float = 50.0

# ---------------------------------------------------------------------------
# Weather state (written by WeatherSystem each tick, read by AsciiRenderSystem)
# ---------------------------------------------------------------------------
## Normalised wind direction vector.
var wind_direction: Vector2 = Vector2(1.0, 0.0)
## Wind intensity 0.0 (dead calm) → 1.0 (full storm).
var wind_strength: float = 0.0
## Integer condition: 0=CALM, 1=BREEZY, 2=WINDY, 3=RAIN, 4=STORM.
var wind_condition: int = 1
## Whether current weather conditions permit precipitation to emerge (written by WeatherSystem).
var rain_allowed: bool = false

# ---------------------------------------------------------------------------
# Season state (written by ClimateSystem each tick)
# ---------------------------------------------------------------------------
## Current season: 0=SPRING, 1=SUMMER, 2=AUTUMN, 3=WINTER.
var season: int = 0
## Progress through the current season 0.0 (start) → 1.0 (end).
var season_progress: float = 0.0
## Smooth temperature modifier: -1.0 (deep winter) → +1.0 (peak summer).
var season_temp_mod: float = 0.0
## Vegetation growth rate modifier driven by season: 0.0 (winter) → 1.0 (summer peak).
## Written by ClimateSystem each tick; read by VegetationGrowthSystem.
var growth_rate_mod: float = 1.0
## Normalised cloud drift direction, driven by season (independent of wind).
## Written by ClimateSystem; forwarded to the cloud shader by AsciiRenderSystem.
## SPRING=(0,-1 N), SUMMER=(1,0 E), AUTUMN=(0,1 S), WINTER=(-1,0 W).
var cloud_direction: Vector2 = Vector2(0.0, -1.0)


# ---------------------------------------------------------------------------
# Turn-tick configuration
# ---------------------------------------------------------------------------
# Multi-Tier Ticking Configuration (RimWorld / Dwarf Fortress-exact)
# ---------------------------------------------------------------------------
## Rare tick interval: plant growth, item yields, decay, material temperature (~2s at 10 TPS)
const RARE_TICK_INTERVAL: int = 20
## Long tick interval: seasonal climate updates across 16,384 tiles (~5s at 10 TPS)
const LONG_TICK_INTERVAL: int = 50

func is_rare_tick(tick: int = -1) -> bool:
	var t: int = tick if tick >= 0 else tick_count
	return t % RARE_TICK_INTERVAL == 0

func is_long_tick(tick: int = -1) -> bool:
	var t: int = tick if tick >= 0 else tick_count
	return t % LONG_TICK_INTERVAL == 0

# ---------------------------------------------------------------------------
## Simulation ticks per real-world second.
var ticks_per_second: float = 10.0
## Pause the simulation without unloading anything.
var paused: bool = false

var tick_count: int = 0
var _tick_accumulator: float = 0.0

# ---------------------------------------------------------------------------
# Entity storage
# ---------------------------------------------------------------------------
var _next_entity_id: int = 0
var _active_entities: Dictionary = {}   # int → true
var _tile_index: Dictionary = {}        # Vector2i → int (entity_id)

# ---------------------------------------------------------------------------
# ECS core objects
# ---------------------------------------------------------------------------
var _registry = null   # ComponentRegistry instance
var _sim_systems: Array = []
var impact_solver = null
var signals = null
var creature_locomotion = null
var creature_abilities = null

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
## Emitted after all systems have processed a tick.
signal tick_processed(tick_number: int)
## Emitted once after all systems have been initialized.
signal world_ready()
## Emitted when terrain or render components change and textures should be re-baked.
signal render_dirty()

func mark_render_dirty() -> void:
	emit_signal("render_dirty")

# ---------------------------------------------------------------------------
# Diagnostics & High-Precision System Profiling
# ---------------------------------------------------------------------------
var profiling_enabled: bool = false
var _system_metrics: Dictionary = {}
var _tick_timings_usec: Array = []
var _max_tick_usec: int = 0
var _total_tick_usec: int = 0

func get_system_performance_data() -> Dictionary:
	return {
		"profiling_enabled": profiling_enabled,
		"tick_count": tick_count,
		"total_tick_usec": _total_tick_usec,
		"max_tick_usec": _max_tick_usec,
		"average_tick_usec": float(_total_tick_usec) / maxf(1.0, float(tick_count)),
		"recent_ticks": _tick_timings_usec.duplicate(),
		"systems": _system_metrics.duplicate(true)
	}

func reset_profiler() -> void:
	_system_metrics.clear()
	_tick_timings_usec.clear()
	_max_tick_usec = 0
	_total_tick_usec = 0

# ===========================================================================
# Godot lifecycle
# ===========================================================================

func _ready() -> void:
	_registry = _ComponentRegistry.new()
	_register_modules()
	_initialize_systems()
	emit_signal("world_ready")

const MAX_TICKS_PER_FRAME: int = 2

func _process(delta: float) -> void:
	if paused:
		return
	_tick_accumulator += delta
	var interval: float = 1.0 / ticks_per_second
	# Prevent accumulator death spiral: cap accumulated catch-up time
	if _tick_accumulator > interval * float(MAX_TICKS_PER_FRAME):
		_tick_accumulator = interval * float(MAX_TICKS_PER_FRAME)

	var ticks_run: int = 0
	while _tick_accumulator >= interval and ticks_run < MAX_TICKS_PER_FRAME:
		_tick_accumulator -= interval
		ticks_run += 1
		_run_tick()

# ===========================================================================
# Tick
# ===========================================================================

func _run_tick() -> void:
	tick_count += 1
	if not profiling_enabled:
		for system in _sim_systems:
			if system.enabled:
				system.tick(tick_count)
		emit_signal("tick_processed", tick_count)
		return

	# High-precision profiling active
	var tick_start: int = Time.get_ticks_usec()
	for system in _sim_systems:
		if not system.enabled:
			continue
		var sys_name: String = system.get_script().resource_path.get_file().get_basename()
		var s_start: int = Time.get_ticks_usec()
		system.tick(tick_count)
		var s_duration: int = Time.get_ticks_usec() - s_start

		var data = _system_metrics.get(sys_name, null)
		if data == null:
			data = {
				"calls": 0,
				"total_usec": 0,
				"max_usec": 0,
				"min_usec": 999999999,
				"last_usec": 0
			}
			_system_metrics[sys_name] = data

		data["calls"] += 1
		data["total_usec"] += s_duration
		data["last_usec"] = s_duration
		if s_duration > data["max_usec"]:
			data["max_usec"] = s_duration
		if s_duration < data["min_usec"]:
			data["min_usec"] = s_duration

	var tick_total: int = Time.get_ticks_usec() - tick_start
	_total_tick_usec += tick_total
	if tick_total > _max_tick_usec:
		_max_tick_usec = tick_total
	_tick_timings_usec.append(tick_total)
	if _tick_timings_usec.size() > 500:
		_tick_timings_usec.pop_front()

	emit_signal("tick_processed", tick_count)

# ===========================================================================
# Module registration — extend here to add new modules
# ===========================================================================

func _register_modules() -> void:
	# --- Terrain module (priority 0: runs first, one-shot generation) ---
	_add_system(_TerrainGenSystem.new(), 0)

	# --- Matter module (priority 10: one-shot material assignment, right after terrain) ---
	_add_system(_MatterAssignSystem.new(), 10)

	# --- Climate module (priority 40: seasons + per-tile temperature, before wind) ---
	_add_system(_ClimateSystem.new(), 40)

	# --- Weather module (priority 50: sets wind state before rain reads it) ---
	_add_system(_WeatherSystem.new(), 50)

	# --- Rain module (priority 60: reads wind, updates moisture & temperature) ---
	_add_system(_RainSystem.new(), 60)

	# --- Vegetation module ---
	_add_system(_VegetationSpawnSystem.new(), 100)   # one-shot seeding

	# --- Phase change (priority 150: melting, freezing, drying — after climate/rain) ---
	_add_system(_PhaseChangeSystem.new(), 150)

	# --- Combustion (priority 160: fire spread + burnout — after phase change) ---
	_add_system(_CombustionSystem.new(), 160)

	# --- Impact / Collision solver (priority 165: physical kinetic strikes, damage, splash) ---
	impact_solver = _ImpactSolverSystem.new()
	_add_system(impact_solver, 165)

	# --- Fluid simulation (priority 170: liquid flow downhill, freeze, ignition) ---
	_add_system(_FluidSystem.new(), 170)

	# --- Gas simulation (priority 180: atmospheric diffusion, dissipation, toxic/corrosive tagging) ---
	_add_system(_GasSystem.new(), 180)

	# --- Chemical reactions (priority 185: acid corrosion, structural yield breakdown) ---
	_add_system(_ChemicalReactionSystem.new(), 185)

	# --- Biological decay (priority 190: rot, spoilage, preservation) ---
	_add_system(_DecaySystem.new(), 190)

	# --- Vegetation growth (priority 200: last, reads clean matter state) ---
	_add_system(_VegetationGrowthSystem.new(), 200)  # per-tick growth & spread

	# --- Vegetation yield (priority 210: deposits items from grass onto tile inventory) ---
	_add_system(_VegetationYieldSystem.new(), 210)  # per-tick item production from plants

	# --- Spatial signals (priority 220: sound impulses, hazard, olfactory channels) ---
	signals = _SignalSystem.new()
	_add_system(signals, 220)

	# --- Creature module (priorities 223, 224, 225, 230, 235, 240) ---
	_add_system(_CreatureGrowthSystem.new(), 223)
	_add_system(_TraitSystem.new(), 224)
	_add_system(_CreatureBodySystem.new(), 225)
	_add_system(_CreatureAISystem.new(), 230)
	creature_locomotion = _CreatureLocomotionSystem.new()
	_add_system(creature_locomotion, 235)
	creature_abilities = _CreatureAbilitySystem.new()
	_add_system(creature_abilities, 240)

	# Sort ascending by priority so lower numbers execute first
	_sim_systems.sort_custom(func(a, b) -> bool: return a.priority < b.priority)

func _add_system(system, p: int) -> void:
	system.world    = self
	system.priority = p
	_sim_systems.append(system)

func _initialize_systems() -> void:
	for system in _sim_systems:
		system.initialize()

# ===========================================================================
# Entity API
# ===========================================================================

func create_entity() -> int:
	var id: int = _next_entity_id
	_next_entity_id += 1
	_active_entities[id] = true
	return id

func destroy_entity(id: int) -> void:
	# Synchronize item global count if entity is an item
	var item = _registry.get_component(id, &"ItemComponent")
	if item != null:
		_ItemFactory.notify_item_destroyed(item.item_type, item.quantity)

	# Clean up spatial index if entity has a tile
	var tile = _registry.get_component(id, &"TileComponent")
	if tile != null:
		_tile_index.erase(tile.position)
	_active_entities.erase(id)
	_registry.remove_all(id)

## Return all currently live entity IDs.
func get_all_entities() -> Array:
	return _active_entities.keys()

# ===========================================================================
# Spatial tile index
# ===========================================================================

## Register entity as the occupant of a world tile position.
func register_tile(entity_id: int, pos: Vector2i) -> void:
	_tile_index[pos] = entity_id

## Return the entity ID at a tile position, or -1 if empty.
func get_entity_at(pos: Vector2i) -> int:
	return _tile_index.get(pos, -1)

## Return true when a position is inside the map bounds.
func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < MAP_WIDTH \
		and pos.y >= 0 and pos.y < MAP_HEIGHT

## Return the creature entity ID at a tile position, or -1 if none.
func get_creature_at(pos: Vector2i) -> int:
	if _registry == null:
		return -1
	var pos_store: Dictionary = _registry.get_store(&"PositionComponent")
	for eid: int in pos_store:
		if pos_store[eid].position == pos:
			return eid
	return -1

# ===========================================================================
# Component API (delegates to registry)
# ===========================================================================

func add_component(entity_id: int, component: Resource) -> void:
	_registry.add(entity_id, component)

func get_component(entity_id: int, type_name: StringName):
	return _registry.get_component(entity_id, type_name)

func has_component(entity_id: int, type_name: StringName) -> bool:
	return _registry.has(entity_id, type_name)

func remove_component(entity_id: int, type_name: StringName) -> void:
	_registry.remove(entity_id, type_name)

## Return the underlying ComponentRegistry for direct iteration.
func get_registry():
	return _registry

## Start building a fluent ECS query.
## Example: World.query().with_all([&"TileComponent"]).run()
func query():
	var q = _Query.new()
	q._world    = self
	q._registry = _registry
	return q

# ===========================================================================
# Simulation controls
# ===========================================================================

func set_speed(tps: float) -> void:
	ticks_per_second = clampf(tps, 1.0, 200.0)

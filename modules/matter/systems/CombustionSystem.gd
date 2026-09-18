## CombustionSystem.gd
## Priority 16 — runs every 10 ticks, after PhaseChangeSystem.
##
## FIRE IS NEVER AUTO-IGNITED HERE.
## BurningComponent must be seeded externally (lightning, torch, debug key, etc.)
## This system is purely a resolver:
##
##   1. Burn tick  : deplete fuel, heat adjacent tiles.
##   2. Fire spread: roll per-neighbour using flammability × (1 − moisture).
##   3. Burnout    : fuel <= 0 → remove BurningComponent + VegetationComponent,
##                   update render to charred ash.
##
## To trigger fire in-game:
##   var b = BurningComponent.new()
##   b.intensity = 1.0; b.fuel = 1.0; b.heat_output = 25.0
##   World.add_component(entity_id, b)
class_name CombustionSystem
extends "res://core/SystemBase.gd"

const _BurningComponent = preload("res://modules/matter/components/BurningComponent.gd")

## Fraction of fuel consumed per cycle per unit of (intensity * flammability).
const BURN_RATE: float = 0.06

## Probability multiplier: spread_chance = intensity * neighbour.flammability * (1-moisture) * SPREAD_MUL
const SPREAD_MUL: float = 0.35

## 8-directional neighbour offsets.
const NEIGHBOURS: Array = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0),                   Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]

var _rng: RandomNumberGenerator = null

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	print("[Combustion] Initialized. External ignition required to start fire.")

func tick(tick_number: int) -> void:
	if tick_number % 10 != 0:
		return

	var reg = world.get_registry()

	# Snapshot burning IDs — avoid modifying the store during iteration.
	var burning_ids: Array = reg.get_store(&"BurningComponent").keys()

	for entity_id: int in burning_ids:
		var burning = reg.get_component(entity_id, &"BurningComponent")
		if burning == null:
			continue  # removed mid-loop by a previous spread step
		var matter = reg.get_component(entity_id, &"MatterComponent")
		if matter == null:
			continue
		var tile = reg.get_component(entity_id, &"TileComponent")
		if tile == null:
			continue

		# --- 1. Burn tick ---
		var depletion: float = burning.intensity * matter.flammability * BURN_RATE
		burning.fuel = maxf(0.0, burning.fuel - depletion)

		# --- 2. Heat and dry adjacent tiles ---
		_heat_neighbours(tile.position, burning, matter, reg)

		# --- 3. Fire spread ---
		if burning.intensity > 0.2:
			_try_spread(tile.position, burning, reg)

		# --- 4. Burnout ---
		if burning.fuel <= 0.0:
			_burnout(entity_id, matter, reg)

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _heat_neighbours(pos: Vector2i, burning, matter, reg) -> void:
	var heat: float = burning.heat_output * burning.intensity * matter.conductivity
	for offset: Vector2i in NEIGHBOURS:
		var npos: Vector2i = pos + offset
		if not world.is_valid_position(npos):
			continue
		var nid: int = world.get_entity_at(npos)
		if nid == -1:
			continue
		var nbiome = reg.get_component(nid, &"BiomeComponent")
		if nbiome == null:
			continue
		# Add heat to biome temperature (it will be re-clamped by ClimateSystem)
		var heat_delta: float = heat / (world.TEMP_MAX_C - world.TEMP_MIN_C)
		nbiome.temperature = clampf(nbiome.temperature + heat_delta * 0.005, 0.0, 1.0)
		# Dry out neighbours
		nbiome.moisture = maxf(0.0, nbiome.moisture - 0.003 * burning.intensity)

func _try_spread(pos: Vector2i, burning, reg) -> void:
	for offset: Vector2i in NEIGHBOURS:
		var npos: Vector2i = pos + offset
		if not world.is_valid_position(npos):
			continue
		var nid: int = world.get_entity_at(npos)
		if nid == -1:
			continue
		if reg.has(nid, &"BurningComponent"):
			continue  # already burning
		var nmatter = reg.get_component(nid, &"MatterComponent")
		if nmatter == null:
			continue
		if nmatter.flammability <= 0.05:
			continue  # not flammable

		# spread_chance = intensity × flammability × (1 − moisture) × SPREAD_MUL × wind_bias
		# Wind bias: downwind neighbours are more likely to catch; upwind are less.
		var wind_dir: Vector2 = world.wind_direction
		var wind_str: float   = world.wind_strength
		var spread_dir: Vector2 = Vector2(float(offset.x), float(offset.y)).normalized()
		var wind_bias: float = lerpf(1.0, 1.0 + wind_str * 1.5,
									 maxf(0.0, spread_dir.dot(wind_dir)))

		var spread_chance: float = burning.intensity \
			* nmatter.flammability \
			* (1.0 - nmatter.moisture) \
			* SPREAD_MUL \
			* wind_bias

		if _rng.randf() < spread_chance:
			var new_fire = _BurningComponent.new()
			new_fire.intensity  = nmatter.flammability
			# Fuel scales with the target plant's growth stage (Gap 9)
			var nveg = reg.get_component(nid, &"VegetationComponent")
			var fuel_scale: float = 1.0
			if nveg != null:
				fuel_scale = 0.3 + float(nveg.growth_stage) * 0.25  # 0→0.30, 3→1.05
			new_fire.fuel       = clampf(fuel_scale, 0.1, 1.5)
			new_fire.heat_output= 20.0 + nmatter.flammability * 15.0
			reg.add(nid, new_fire)


func _burnout(entity_id: int, matter, reg) -> void:
	reg.remove(entity_id, &"BurningComponent")

	# Remove any vegetation that burned away
	if reg.has(entity_id, &"VegetationComponent"):
		reg.remove(entity_id, &"VegetationComponent")
	if reg.has(entity_id, &"GrowthComponent"):
		reg.remove(entity_id, &"GrowthComponent")

	# Update render to charred ash
	var render = reg.get_component(entity_id, &"RenderComponent")
	if render != null:
		render.glyph    = "%"
		render.fg_color = Color(0.22, 0.20, 0.18)
		render.bg_color = Color(0.05, 0.04, 0.03)

	# Reset matter to a dry, ash-like state
	matter.flammability = 0.0
	matter.moisture     = 0.02

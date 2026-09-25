## CreatureSpawner.gd
## Extensible helper utility for finding valid spawn locations and instantiating
## creatures (individually or in batches) within the living world simulation.
class_name CreatureSpawner
extends RefCounted

const _CreatureFactory = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes   = preload("res://modules/creature/data/CreatureTypes.gd")
const _TileAffordance  = preload("res://modules/signal/data/TileAffordance.gd")

## Default starter creature configuration: A pair of Grazers (1 Male, 1 Female)
## placed in the fertile plains vegetation zone.
const DEFAULT_STARTER_CONFIGS: Array[Dictionary] = [
	{
		"species": _CreatureTypes.Type.GRAZER,
		"gender": _CreatureTypes.Gender.MALE,
		"name": "Male Grazer",
		"options": {
			"min_y": 65,
			"max_y": 95,
			"require_vegetation": true,
		}
	},
	{
		"species": _CreatureTypes.Type.GRAZER,
		"gender": _CreatureTypes.Gender.FEMALE,
		"name": "Female Grazer",
		"options": {
			"min_y": 65,
			"max_y": 95,
			"require_vegetation": true,
			"near_previous": true,
			"min_distance": 2,
			"max_distance": 10,
		}
	}
]

## Returns a copy of the default starter creature configuration list.
static func get_default_starter_configs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cfg in DEFAULT_STARTER_CONFIGS:
		result.append(cfg.duplicate(true))
	return result

# ---------------------------------------------------------------------------
# Spatial Query & Spawn Location Helpers
# ---------------------------------------------------------------------------

## Finds a valid, walkable, safe tile position matching the provided criteria.
## Criteria keys:
##   - min_y / max_y (int): Y range bounds (default: 65, 95)
##   - min_x / max_x (int): X range bounds (default: 0, MAP_WIDTH - 1)
##   - require_vegetation (bool): must have edible vegetation / grazeable affordance (default: true)
##   - near_pos (Vector2i): target reference position to cluster near (default: Vector2i(-1, -1))
##   - min_distance (float): minimum distance from near_pos (default: 1.0)
##   - max_distance (float): maximum distance from near_pos (default: -1.0 = unlimited)
##   - custom_filter (Callable): optional func(pos: Vector2i) -> bool predicate
static func find_spawn_position(
	world: Node,
	criteria: Dictionary = {},
	excluded_positions: Array[Vector2i] = []
) -> Vector2i:
	if world == null:
		return Vector2i(-1, -1)

	var reg = world.get_registry()
	if reg == null:
		return Vector2i(64, 80)

	var veg_store: Dictionary  = reg.get_store(&"VegetationComponent")
	var tile_store: Dictionary = reg.get_store(&"TileComponent")

	var map_w: int = world.MAP_WIDTH if "MAP_WIDTH" in world else 128
	var map_h: int = world.MAP_HEIGHT if "MAP_HEIGHT" in world else 128

	var min_y: int = criteria.get("min_y", 65) as int
	var max_y: int = criteria.get("max_y", 95) as int
	var min_x: int = criteria.get("min_x", 0) as int
	var max_x: int = criteria.get("max_x", map_w - 1) as int
	var require_vegetation: bool = criteria.get("require_vegetation", true) as bool
	var near_pos: Vector2i = criteria.get("near_pos", Vector2i(-1, -1)) as Vector2i
	var min_dist: float = float(criteria.get("min_distance", 1.0))
	var max_dist: float = float(criteria.get("max_distance", -1.0))
	var custom_filter = criteria.get("custom_filter", null)

	# 1. Search candidates that meet all criteria
	var candidates: Array[Vector2i] = []

	if require_vegetation and not veg_store.is_empty():
		for eid: int in veg_store:
			var tile = tile_store.get(eid, null)
			if tile == null:
				continue
			var pos: Vector2i = tile.position
			if _is_tile_valid(world, pos, min_x, max_x, min_y, max_y, near_pos, min_dist, max_dist, excluded_positions, custom_filter):
				candidates.append(pos)
	else:
		for eid: int in tile_store:
			var tile = tile_store[eid]
			var pos: Vector2i = tile.position
			if _is_tile_valid(world, pos, min_x, max_x, min_y, max_y, near_pos, min_dist, max_dist, excluded_positions, custom_filter):
				candidates.append(pos)

	if not candidates.is_empty():
		return _select_candidate(candidates, near_pos)

	# 2. Fallback Phase 1: Relax distance constraints if near_pos was specified
	if near_pos != Vector2i(-1, -1) and max_dist > 0.0:
		var relaxed_crit: Dictionary = criteria.duplicate()
		relaxed_crit.erase("max_distance")
		relaxed_crit.erase("near_pos")
		return find_spawn_position(world, relaxed_crit, excluded_positions)

	# 3. Fallback Phase 2: Relax vegetation requirement if it was required
	if require_vegetation:
		var no_veg_crit: Dictionary = criteria.duplicate()
		no_veg_crit["require_vegetation"] = false
		return find_spawn_position(world, no_veg_crit, excluded_positions)

	# 4. Fallback Phase 3: Relax region constraints across whole map
	if min_y > 0 or max_y < map_h - 1:
		var whole_map_crit: Dictionary = {
			"min_y": 0,
			"max_y": map_h - 1,
			"min_x": 0,
			"max_x": map_w - 1,
			"require_vegetation": false,
		}
		return find_spawn_position(world, whole_map_crit, excluded_positions)

	# 5. Ultimate Fallback: Default safe position around map center
	var fallback_center := Vector2i(map_w / 2, mini(map_h - 1, 80))
	if not excluded_positions.has(fallback_center) and world.get_creature_at(fallback_center) == -1:
		return fallback_center

	for r in range(1, 15):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var test_pos: Vector2i = fallback_center + Vector2i(dx, dy)
				if world.is_valid_position(test_pos) and not excluded_positions.has(test_pos) and world.get_creature_at(test_pos) == -1:
					if world.signals == null or world.signals.has_affordance(test_pos, _TileAffordance.WALKABLE):
						return test_pos

	return fallback_center

static func _is_tile_valid(
	world: Node,
	pos: Vector2i,
	min_x: int, max_x: int, min_y: int, max_y: int,
	near_pos: Vector2i, min_dist: float, max_dist: float,
	excluded_positions: Array[Vector2i],
	custom_filter
) -> bool:
	if pos.x < min_x or pos.x > max_x or pos.y < min_y or pos.y > max_y:
		return false
	if excluded_positions.has(pos):
		return false
	if world.get_creature_at(pos) != -1:
		return false
	if world.signals != null:
		if not world.signals.has_affordance(pos, _TileAffordance.WALKABLE):
			return false
		if world.signals.has_affordance(pos, _TileAffordance.HAZARD_LETHAL):
			return false
	if near_pos != Vector2i(-1, -1):
		var d: float = Vector2(pos).distance_to(Vector2(near_pos))
		if min_dist > 0.0 and d < min_dist:
			return false
		if max_dist > 0.0 and d > max_dist:
			return false
	if custom_filter != null and custom_filter is Callable and custom_filter.is_valid():
		if not custom_filter.call(pos):
			return false
	return true

static func _select_candidate(candidates: Array[Vector2i], near_pos: Vector2i) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-1, -1)
	if near_pos != Vector2i(-1, -1):
		# Sort by proximity to target reference
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a).distance_squared_to(Vector2(near_pos)) < Vector2(b).distance_squared_to(Vector2(near_pos))
		)
		return candidates[0]
	# Pick a centrally distributed candidate in the cluster
	return candidates[candidates.size() / 2]

# ---------------------------------------------------------------------------
# Spawning API
# ---------------------------------------------------------------------------

## Spawns a creature entity using a configuration dictionary.
## Supported config keys:
##   - species / species_type (int): CreatureTypes.Type (default: GRAZER)
##   - gender / gender_override (int): Gender enum (default: -1 -> random)
##   - name / name_override (String): custom name (default: auto "[Gender] [Species]")
##   - traits / initial_traits (Array[int]): custom traits (default: [])
##   - stage / start_stage (int): GrowthStage enum (default: -1 -> ADULT)
##   - pos / position / spawn_pos (Vector2i): explicit tile position, or omitted to auto-find
##   - options / criteria (Dictionary): criteria passed to find_spawn_position if pos omitted
static func spawn_creature(
	world: Node,
	config: Dictionary,
	excluded_positions: Array[Vector2i] = []
) -> int:
	if world == null:
		return -1

	# 1. Resolve position
	var spawn_pos := Vector2i(-1, -1)
	if config.has("position"):
		spawn_pos = config["position"]
	elif config.has("spawn_pos"):
		spawn_pos = config["spawn_pos"]
	elif config.has("pos"):
		spawn_pos = config["pos"]

	var criteria: Dictionary = config.get("options", config.get("criteria", {}))
	if spawn_pos == Vector2i(-1, -1):
		spawn_pos = find_spawn_position(world, criteria, excluded_positions)

	# 2. Extract configuration fields
	var species: int = config.get("species_type", config.get("species", _CreatureTypes.Type.GRAZER)) as int
	var gender: int = config.get("gender_override", config.get("gender", -1)) as int
	var creature_name: String = config.get("name_override", config.get("name", "")) as String
	var stage: int = config.get("start_stage", config.get("stage", -1)) as int

	var raw_traits = config.get("initial_traits", config.get("traits", []))
	var traits: Array[int] = []
	for t in raw_traits:
		traits.append(t as int)

	if creature_name == "":
		var spec_name: String = _CreatureTypes.get_data(species).get("display_name", "Creature")
		if gender >= 0:
			creature_name = "%s %s" % [_CreatureTypes.get_gender_name(gender), spec_name]
		else:
			creature_name = spec_name

	# 3. Create entity via CreatureFactory
	var eid: int = _CreatureFactory.create(world, species, spawn_pos, creature_name, traits, stage, gender)
	if eid != -1:
		excluded_positions.append(spawn_pos)
		print("[Spire] Spawned %s (eid=%d, gender=%s) at %s." % [
			creature_name, eid, _CreatureTypes.get_gender_name(gender), spawn_pos
		])

	return eid

## Spawns a list of creature configurations sequentially, preventing tile collisions
## and optionally supporting "near_previous": true for partner/pack clustering.
static func spawn_creatures(
	world: Node,
	configs: Array,
	excluded_positions: Array[Vector2i] = []
) -> Array[int]:
	var spawned_eids: Array[int] = []
	var prev_pos := Vector2i(-1, -1)

	for item in configs:
		if not (item is Dictionary):
			continue
		var cfg: Dictionary = (item as Dictionary).duplicate(true)
		var opts: Dictionary = cfg.get("options", cfg.get("criteria", {}))
		if opts.get("near_previous", false) and prev_pos != Vector2i(-1, -1):
			if not opts.has("near_pos"):
				opts["near_pos"] = prev_pos
			cfg["options"] = opts

		var eid: int = spawn_creature(world, cfg, excluded_positions)
		if eid != -1:
			spawned_eids.append(eid)
			if not excluded_positions.is_empty():
				prev_pos = excluded_positions[-1]

	return spawned_eids

## Spawns the starter creature population.
## Defaults to DEFAULT_STARTER_CONFIGS (1 Male Grazer, 1 Female Grazer) if configs is empty.
static func spawn_starter_creatures(
	world: Node,
	custom_configs: Array = []
) -> Array[int]:
	var configs: Array = custom_configs if not custom_configs.is_empty() else DEFAULT_STARTER_CONFIGS
	return spawn_creatures(world, configs)

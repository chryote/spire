## VegetationSpawnSystem.gd
## Priority 10 — seeds initial vegetation during tick 1 only, then goes dormant.
##
## Two-pass approach:
##   Pass 1 — Trees (PINE_TREE, OAK_TREE): rare, given first pick of grass tiles.
##   Pass 2 — Ground cover: fills remaining grass tiles that weren't taken by trees.
##
## This ensures trees claim territory before grass carpets everything.
class_name VegetationSpawnSystem
extends "res://core/SystemBase.gd"

const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _GrowthComponent     = preload("res://modules/vegetation/components/GrowthComponent.gd")
const _VegetationTypes     = preload("res://modules/vegetation/data/VegetationTypes.gd")
const _TileTypes           = preload("res://modules/terrain/data/TileTypes.gd")
const _ItemYieldComponent  = preload("res://modules/item/components/ItemYieldComponent.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")

## Spawn order for trees (checked first, before ground cover).
const TREE_TYPES: Array    = [4, 5]  # PINE_TREE, OAK_TREE

## Spawn order for ground cover (checked second).
const GROUND_TYPES: Array  = [0, 1, 2, 3]  # GRASS_PATCH, TALL_GRASS, SHRUB, WILDFLOWER

var _spawned: bool = false
var _rng: RandomNumberGenerator = null

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func tick(_tick_number: int) -> void:
	if _spawned:
		return
	_spawned = true
	_seed_vegetation()

# ---------------------------------------------------------------------------
# Seeding logic
# ---------------------------------------------------------------------------

func _seed_vegetation() -> void:
	# Query all terrain tiles (no vegetation filter yet — we're populating fresh)
	var entities: Array = world.query() \
		.with_all([&"TileComponent", &"BiomeComponent"]) \
		.run()

	var reg = world.get_registry()

	# ===========================================================
	# Pass 1: Trees — given first pick over grass tiles
	# ===========================================================
	for entity_id: int in entities:
		var tile  = reg.get_component(entity_id, &"TileComponent")
		var biome = reg.get_component(entity_id, &"BiomeComponent")

		if tile.tile_type != _TileTypes.Type.GRASS:
			continue

		for veg_type: int in TREE_TYPES:
			if _try_spawn(entity_id, veg_type, biome, reg):
				break

	# ===========================================================
	# Pass 2: Ground cover — only on tiles without vegetation
	# ===========================================================
	for entity_id: int in entities:
		if reg.has(entity_id, &"VegetationComponent"):
			continue  # Tree already claimed this tile

		var tile  = reg.get_component(entity_id, &"TileComponent")
		var biome = reg.get_component(entity_id, &"BiomeComponent")

		if tile.tile_type != _TileTypes.Type.GRASS:
			continue

		for veg_type: int in GROUND_TYPES:
			if _try_spawn(entity_id, veg_type, biome, reg):
				break

# ---------------------------------------------------------------------------
# Shared spawning helper
# ---------------------------------------------------------------------------

func _try_spawn(entity_id: int, veg_type: int, biome, reg) -> bool:
	var vd: Dictionary = _VegetationTypes.get_data(veg_type)

	# Biome check
	if not (biome.biome in vd.get("spawn_biomes", [])):
		return false

	# Moisture check
	if biome.moisture < (vd.get("min_moisture", 0.0) as float):
		return false

	# Probabilistic roll
	if _rng.randf() > (vd.get("spawn_chance", 0.0) as float):
		return false

	# --- Attach VegetationComponent ---
	var veg = _VegetationComponent.new()
	veg.veg_type     = veg_type
	veg.growth_stage = _rng.randi_range(0, vd.get("initial_stage_max", 2) as int)
	veg.age          = float(_rng.randi_range(0, vd.get("initial_age_max", 60) as int))
	reg.add(entity_id, veg)

	# --- Attach GrowthComponent ---
	var growth = _GrowthComponent.new()
	growth.ticks_per_stage = vd.get("ticks_per_stage", 40) as int
	growth.spread_chance   = vd.get("spread_chance", 0.03) as float
	growth.spread_radius   = vd.get("spread_radius", 2) as int
	reg.add(entity_id, growth)

	# --- Attach ItemYieldComponent for grass-type plants ---
	if veg_type in [_VegetationTypes.Type.GRASS_PATCH, _VegetationTypes.Type.TALL_GRASS]:
		var yield_comp = _ItemYieldComponent.new()
		yield_comp.item_type       = _ItemTypes.Type.GRASS
		yield_comp.material_type   = _MaterialTypes.Type.ORGANIC
		yield_comp.ticks_per_yield = vd.get("ticks_per_yield", 60) as int
		yield_comp.max_yield       = 5
		reg.add(entity_id, yield_comp)

	# --- Update RenderComponent ---
	_update_render(entity_id, veg, vd, reg)
	return true

func _update_render(entity_id: int, veg, vd: Dictionary, reg) -> void:
	var render = reg.get_component(entity_id, &"RenderComponent")
	if render == null:
		return
	render.glyph    = _VegetationTypes.get_glyph(veg.veg_type, veg.growth_stage)
	render.fg_color = _VegetationTypes.get_fg_color(veg.veg_type, veg.growth_stage)
	render.bg_color = vd.get("bg_color", Color(0.03, 0.08, 0.02)) as Color
	render.z_layer  = vd.get("z_layer", 0) as int

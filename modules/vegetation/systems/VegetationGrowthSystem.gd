## VegetationGrowthSystem.gd
## Priority 200 — runs every tick.
##
## For each vegetated entity:
##   1. Advance age by 1 tick (scaled by growth_rate_mod and TICK_STRIDE).
##   2. Check if the plant should promote to the next growth stage.
##   3. Roll for spread — attempt to plant a child on a nearby compatible tile.
##
## Spread eligibility uses the species' "spread_tiles" list so trees can
## colonise GROUND and DIRT tiles, while grass stays on GRASS only.
class_name VegetationGrowthSystem
extends "res://core/SystemBase.gd"

const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _GrowthComponent     = preload("res://modules/vegetation/components/GrowthComponent.gd")
const _VegetationTypes     = preload("res://modules/vegetation/data/VegetationTypes.gd")
const _TileTypes           = preload("res://modules/terrain/data/TileTypes.gd")
const _ItemYieldComponent  = preload("res://modules/item/components/ItemYieldComponent.gd")

var _rng: RandomNumberGenerator = null

const SLICE_COUNT: int = 20
const TICK_STRIDE: int = SLICE_COUNT
var _slice_buckets: Array[PackedInt32Array] = []
var _cached_store_size: int = -1

# Pre-computed per-species tables (indexed directly by veg_type int 0..5)
var _min_survival_moisture: PackedFloat32Array = PackedFloat32Array()
var _max_survival_temp:     PackedFloat32Array = PackedFloat32Array()
var _min_survival_temp:     PackedFloat32Array = PackedFloat32Array()
var _min_spread_moisture:   PackedFloat32Array = PackedFloat32Array()
var _spread_chances:        PackedFloat32Array = PackedFloat32Array()
var _spread_tile_masks:     PackedInt32Array   = PackedInt32Array()
var _spawn_biome_masks:     PackedInt32Array   = PackedInt32Array()
var _bg_colors:             Array[Color]       = []
var _z_layers:              PackedInt32Array   = PackedInt32Array()

# Pre-computed growth stage thresholds: [veg_type * 3 + stage (0..2)]
var _stage_thresholds:      PackedFloat32Array = PackedFloat32Array()

# Cached glyphs and colors: [veg_type * 4 + stage]
var _stage_glyphs:          Array[String]      = []
var _stage_fg_colors:       Array[Color]       = []

# Pre-computed base tile visuals for quick kill revert (indexed by tile_type 0..4)
var _tile_glyphs:    Array[String] = []
var _tile_fg_colors: Array[Color]  = []
var _tile_bg_colors: Array[Color]  = []

var _map_width: int = 128
var _map_height: int = 128

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_setup_species_cache()
	_setup_tile_cache()
	_init_buckets()
	if world != null:
		_map_width = world.MAP_WIDTH
		_map_height = world.MAP_HEIGHT

func _init_buckets() -> void:
	_slice_buckets.clear()
	for i in range(SLICE_COUNT):
		_slice_buckets.append(PackedInt32Array())
	_cached_store_size = -1

func _setup_species_cache() -> void:
	_min_survival_moisture.resize(6)
	_max_survival_temp.resize(6)
	_min_survival_temp.resize(6)
	_min_spread_moisture.resize(6)
	_spread_chances.resize(6)
	_spread_tile_masks.resize(6)
	_spawn_biome_masks.resize(6)
	_bg_colors.resize(6)
	_z_layers.resize(6)
	_stage_thresholds.resize(18)  # 6 species * 3 stages
	_stage_glyphs.resize(24)
	_stage_fg_colors.resize(24)

	for vt: int in range(6):
		var vd: Dictionary = _VegetationTypes.get_data(vt)
		_min_survival_moisture[vt] = vd.get("min_survival_moisture", 0.0) as float
		_max_survival_temp[vt]     = vd.get("max_survival_temp", 1.0) as float
		_min_survival_temp[vt]     = vd.get("min_survival_temp", 0.0) as float
		_min_spread_moisture[vt]   = vd.get("min_moisture", 0.0) as float
		_spread_chances[vt]        = vd.get("spread_chance", 0.03) as float
		_bg_colors[vt]             = vd.get("bg_color", Color(0.03, 0.08, 0.02)) as Color
		_z_layers[vt]              = vd.get("z_layer", 0) as int

		var ticks_per_stg: int = vd.get("ticks_per_stage", 40) as int
		for s in range(3):
			_stage_thresholds[vt * 3 + s] = float(ticks_per_stg * (s + 1))

		var spread_mask: int = 0
		var spread_tiles: Array = vd.get("spread_tiles", [1])
		for st in spread_tiles:
			spread_mask |= (1 << int(st))
		_spread_tile_masks[vt] = spread_mask

		var biome_mask: int = 0
		var spawn_biomes: Array = vd.get("spawn_biomes", [])
		for bm in spawn_biomes:
			biome_mask |= (1 << int(bm))
		_spawn_biome_masks[vt] = biome_mask

		for stg: int in range(4):
			var idx: int = vt * 4 + stg
			_stage_glyphs[idx]    = _VegetationTypes.get_glyph(vt, stg)
			_stage_fg_colors[idx] = _VegetationTypes.get_fg_color(vt, stg)

func _setup_tile_cache() -> void:
	_tile_glyphs.resize(5)
	_tile_fg_colors.resize(5)
	_tile_bg_colors.resize(5)
	for tt: int in range(5):
		var td: Dictionary = _TileTypes.get_data(tt)
		_tile_glyphs[tt]    = td.get("glyph", ".") as String
		_tile_fg_colors[tt] = td.get("fg_color", Color(0.4, 0.4, 0.3)) as Color
		_tile_bg_colors[tt] = td.get("bg_color", Color(0.1, 0.1, 0.05)) as Color

func _rebuild_buckets(veg_store: Dictionary) -> void:
	_slice_buckets.clear()
	for i in range(SLICE_COUNT):
		_slice_buckets.append(PackedInt32Array())
	for entity_id: int in veg_store:
		_slice_buckets[entity_id % SLICE_COUNT].append(entity_id)
	_cached_store_size = veg_store.size()

func tick(tick_number: int) -> void:
	var reg = world.get_registry()
	var veg_store: Dictionary = reg.get_store(&"VegetationComponent")
	if veg_store.is_empty():
		return

	if _cached_store_size == -1 or _slice_buckets.is_empty() or (_slice_buckets[0].is_empty() and veg_store.size() > 0):
		_rebuild_buckets(veg_store)

	var slice_mod: int = tick_number % SLICE_COUNT
	var slice: PackedInt32Array = _slice_buckets[slice_mod]

	var growth_store: Dictionary = reg.get_store(&"GrowthComponent")
	var tile_store:   Dictionary = reg.get_store(&"TileComponent")
	var burn_store:   Dictionary = reg.get_store(&"BurningComponent")
	var biome_store:  Dictionary = reg.get_store(&"BiomeComponent")
	var render_store: Dictionary = reg.get_store(&"RenderComponent")

	var visuals_changed: bool = false
	var dead_count: int = 0
	var has_burning: bool = not burn_store.is_empty()
	var growth_rate: float = world.growth_rate_mod
	var age_step: float = growth_rate * float(TICK_STRIDE)
	var spread_multiplier: float = growth_rate * float(TICK_STRIDE)

	for entity_id: int in slice:
		var veg = veg_store.get(entity_id, null)
		if veg == null:
			dead_count += 1
			continue

		# Fire takes priority — no growth on burning tiles (skipped entirely if no fires exist)
		if has_burning and burn_store.has(entity_id):
			continue

		var vt: int = veg.veg_type

		# --- Survival check — instant death when conditions breach threshold ---
		var target_biome = biome_store.get(entity_id, null)
		if target_biome != null:
			var moisture: float = target_biome.moisture
			var temp: float = target_biome.temperature
			if moisture < _min_survival_moisture[vt] or temp > _max_survival_temp[vt] or temp < _min_survival_temp[vt]:
				var tile = tile_store.get(entity_id, null)
				_kill_plant_fast(entity_id, reg, veg_store, growth_store, tile, render_store)
				dead_count += 1
				visuals_changed = true
				continue

			# --- Moisture consumption ---
			target_biome.moisture = maxf(0.0, moisture - (0.0002 + float(veg.growth_stage) * 0.00006))

		# --- Age advancement scaled by season and TICK_STRIDE ---
		veg.age += age_step

		# --- Growth stage promotion ---
		var stage: int = veg.growth_stage
		if stage < 3:
			if veg.age >= _stage_thresholds[vt * 3 + stage]:
				veg.growth_stage = stage + 1
				_refresh_render_fast(entity_id, vt, stage + 1, render_store)
				visuals_changed = true

		# --- Spread attempt scaled by season and TICK_STRIDE ---
		if _rng.randf() < _spread_chances[vt] * spread_multiplier:
			var growth = growth_store.get(entity_id, null)
			if growth != null:
				var source_pos := Vector2i(entity_id % _map_width, entity_id / _map_width)
				if _try_spread_fast(entity_id, vt, growth, source_pos, reg, veg_store, tile_store, biome_store, render_store):
					visuals_changed = true

	# Compact slice in-place if dead entities were encountered
	if dead_count > 0:
		var new_size: int = slice.size() - dead_count
		var compacted := PackedInt32Array()
		if new_size > 0:
			compacted.resize(new_size)
			var w_idx: int = 0
			for eid: int in slice:
				if veg_store.has(eid):
					compacted[w_idx] = eid
					w_idx += 1
		_slice_buckets[slice_mod] = compacted

	if visuals_changed and world != null:
		world.mark_render_dirty()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _try_spread_fast(
	source_id: int,
	vt: int,
	growth,
	source_pos: Vector2i,
	reg,
	veg_store: Dictionary,
	tile_store: Dictionary,
	biome_store: Dictionary,
	render_store: Dictionary
) -> bool:
	var r: int = growth.spread_radius
	var offset := Vector2i(_rng.randi_range(-r, r), _rng.randi_range(-r, r))
	if offset == Vector2i.ZERO:
		return false

	var target_pos: Vector2i = source_pos + offset
	if target_pos.x < 0 or target_pos.x >= _map_width or target_pos.y < 0 or target_pos.y >= _map_height:
		return false

	var target_id: int = world.get_entity_at(target_pos)
	if target_id == -1:
		return false

	# 1. Skip already-vegetated tiles (instant O(1) dict lookup)
	if veg_store.has(target_id):
		return false

	# 2. Check tile type with pre-cached bitmask
	var target_tile = tile_store.get(target_id, null)
	if target_tile == null:
		return false

	var tile_mask: int = 1 << target_tile.tile_type
	if (_spread_tile_masks[vt] & tile_mask) == 0:
		return false

	# 3. Biome and moisture compatibility with pre-cached bitmask & array
	var target_biome = biome_store.get(target_id, null)
	if target_biome == null:
		return false

	var biome_mask: int = 1 << target_biome.biome
	if (_spawn_biome_masks[vt] & biome_mask) == 0:
		return false

	if target_biome.moisture < _min_spread_moisture[vt]:
		return false

	# --- Plant child ---
	var new_veg = _VegetationComponent.new()
	new_veg.veg_type     = vt
	new_veg.growth_stage = 0
	new_veg.age          = 0.0
	reg.add(target_id, new_veg)

	var new_growth = _GrowthComponent.new()
	new_growth.ticks_per_stage = growth.ticks_per_stage
	new_growth.spread_chance   = growth.spread_chance
	new_growth.spread_radius   = growth.spread_radius
	reg.add(target_id, new_growth)

	# Add to slice buckets immediately in O(1)
	_slice_buckets[target_id % SLICE_COUNT].append(target_id)

	# --- Copy ItemYieldComponent if the parent produces items ---
	var parent_yield = reg.get_component(source_id, &"ItemYieldComponent")
	if parent_yield != null:
		var child_yield = _ItemYieldComponent.new()
		child_yield.item_type         = parent_yield.item_type
		child_yield.material_type     = parent_yield.material_type
		child_yield.ticks_per_yield   = parent_yield.ticks_per_yield
		child_yield.max_yield         = parent_yield.max_yield
		child_yield.ticks_since_yield = 0
		reg.add(target_id, child_yield)

	_refresh_render_fast(target_id, vt, 0, render_store)
	return true

func _refresh_render_fast(entity_id: int, vt: int, stage: int, render_store: Dictionary) -> void:
	var render = render_store.get(entity_id, null)
	if render == null:
		return
	var stg: int = clampi(stage, 0, 3)
	var idx: int = vt * 4 + stg
	render.glyph    = _stage_glyphs[idx]
	render.fg_color = _stage_fg_colors[idx]
	render.bg_color = _bg_colors[vt]
	render.z_layer  = _z_layers[vt]

func _kill_plant_fast(entity_id: int, reg, veg_store: Dictionary, growth_store: Dictionary, tile, render_store: Dictionary) -> void:
	veg_store.erase(entity_id)
	growth_store.erase(entity_id)
	reg.remove(entity_id, &"VegetationComponent")
	reg.remove(entity_id, &"GrowthComponent")

	var render = render_store.get(entity_id, null)
	if tile != null and render != null:
		var tt: int = tile.tile_type
		if tt >= 0 and tt < 5:
			render.glyph    = _tile_glyphs[tt]
			render.fg_color = _tile_fg_colors[tt]
			render.bg_color = _tile_bg_colors[tt]
		else:
			var td: Dictionary = _TileTypes.get_data(tt)
			render.glyph    = td.get("glyph",    ".")
			render.fg_color = td.get("fg_color", Color(0.4, 0.4, 0.3))
			render.bg_color = td.get("bg_color", Color(0.1, 0.1, 0.05))
		render.z_layer = 0

## Backward compatibility helper
func _refresh_render(entity_id: int, veg, reg) -> void:
	var render_store = reg.get_store(&"RenderComponent")
	_refresh_render_fast(entity_id, veg.veg_type, veg.growth_stage, render_store)

## Backward compatibility helper
func _kill_plant(entity_id: int, reg) -> void:
	var veg_store = reg.get_store(&"VegetationComponent")
	var growth_store = reg.get_store(&"GrowthComponent")
	var tile_store = reg.get_store(&"TileComponent")
	var render_store = reg.get_store(&"RenderComponent")
	var tile = tile_store.get(entity_id, null)
	_kill_plant_fast(entity_id, reg, veg_store, growth_store, tile, render_store)

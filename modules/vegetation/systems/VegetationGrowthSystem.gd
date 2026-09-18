## VegetationGrowthSystem.gd
## Priority 20 — runs every tick.
##
## For each vegetated entity:
##   1. Advance age by 1 tick.
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


var _rng: RandomNumberGenerator = null

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

func tick(_tick_number: int) -> void:
	var entities: Array = world.query() \
		.with_all([&"VegetationComponent", &"GrowthComponent", &"TileComponent"]) \
		.run()

	var reg = world.get_registry()

	for entity_id: int in entities:
		var veg    = reg.get_component(entity_id, &"VegetationComponent")
		var growth = reg.get_component(entity_id, &"GrowthComponent")
		var tile   = reg.get_component(entity_id, &"TileComponent")

		# Fire takes priority — no growth on burning tiles
		if reg.has(entity_id, &"BurningComponent"):
			continue

		# --- Survival check (Gap 5) — instant death when conditions breach threshold ---
		var target_biome = reg.get_component(entity_id, &"BiomeComponent")
		if target_biome != null:
			var vd: Dictionary = _VegetationTypes.get_data(veg.veg_type)
			var too_dry:  bool = target_biome.moisture     < (vd.get("min_survival_moisture", 0.0) as float)
			var too_hot:  bool = target_biome.temperature  > (vd.get("max_survival_temp",     1.0) as float)
			var too_cold: bool = target_biome.temperature  < (vd.get("min_survival_temp",     0.0) as float)
			if too_dry or too_hot or too_cold:
				_kill_plant(entity_id, reg)
				continue

			# --- Moisture consumption (Gap 10) ---
			# Plants draw moisture from the biome proportional to size.
			var consumption: float = 0.0002 * (1.0 + float(veg.growth_stage) * 0.3)
			target_biome.moisture = maxf(0.0, target_biome.moisture - consumption)

		# --- Age advancement scaled by season (Gap 4) ---
		veg.age += world.growth_rate_mod

		# --- Growth stage promotion ---
		if veg.growth_stage < 3:
			var threshold: float = float(growth.ticks_per_stage) * float(veg.growth_stage + 1)
			if veg.age >= threshold:
				veg.growth_stage = mini(veg.growth_stage + 1, 3)
				_refresh_render(entity_id, veg, reg)

		# --- Spread attempt scaled by season (Gap 4) ---
		if _rng.randf() < growth.spread_chance * world.growth_rate_mod:
			_try_spread(entity_id, veg, growth, tile.position, reg)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _try_spread(_source_id: int, veg, growth, source_pos: Vector2i, reg) -> void:
	var r: int = growth.spread_radius
	var offset := Vector2i(_rng.randi_range(-r, r), _rng.randi_range(-r, r))
	if offset == Vector2i.ZERO:
		return

	var target_pos: Vector2i = source_pos + offset
	if not world.is_valid_position(target_pos):
		return

	var target_id: int = world.get_entity_at(target_pos)
	if target_id == -1:
		return

	# Skip already-vegetated tiles
	if reg.has(target_id, &"VegetationComponent"):
		return

	# Check tile type is in this species' allowed spread_tiles list
	var target_tile = reg.get_component(target_id, &"TileComponent")
	if target_tile == null:
		return

	var vd: Dictionary = _VegetationTypes.get_data(veg.veg_type)
	var spread_tiles: Array = vd.get("spread_tiles", [1])  # default: GRASS only
	if not (target_tile.tile_type in spread_tiles):
		return

	# Biome and moisture compatibility
	var target_biome = reg.get_component(target_id, &"BiomeComponent")
	if target_biome == null:
		return

	if not (target_biome.biome in vd.get("spawn_biomes", [])):
		return
	if target_biome.moisture < (vd.get("min_moisture", 0.0) as float):
		return

	# --- Plant child ---
	var new_veg = _VegetationComponent.new()
	new_veg.veg_type     = veg.veg_type
	new_veg.growth_stage = 0
	new_veg.age          = 0.0
	reg.add(target_id, new_veg)

	var new_growth = _GrowthComponent.new()
	new_growth.ticks_per_stage = growth.ticks_per_stage
	new_growth.spread_chance   = growth.spread_chance
	new_growth.spread_radius   = growth.spread_radius
	reg.add(target_id, new_growth)

	_refresh_render(target_id, new_veg, reg)

func _refresh_render(entity_id: int, veg, reg) -> void:
	var render = reg.get_component(entity_id, &"RenderComponent")
	if render == null:
		return
	var vd: Dictionary = _VegetationTypes.get_data(veg.veg_type)
	render.glyph    = _VegetationTypes.get_glyph(veg.veg_type, veg.growth_stage)
	render.fg_color = _VegetationTypes.get_fg_color(veg.veg_type, veg.growth_stage)
	render.bg_color = vd.get("bg_color", Color(0.03, 0.08, 0.02)) as Color
	render.z_layer  = vd.get("z_layer", 0) as int

func _kill_plant(entity_id: int, reg) -> void:
	## Remove all vegetation components and revert the render to bare terrain.
	reg.remove(entity_id, &"VegetationComponent")
	if reg.has(entity_id, &"GrowthComponent"):
		reg.remove(entity_id, &"GrowthComponent")
	# Revert render to base tile appearance
	var tile   = reg.get_component(entity_id, &"TileComponent")
	var render = reg.get_component(entity_id, &"RenderComponent")
	if tile != null and render != null:
		var td: Dictionary = _TileTypes.get_data(tile.tile_type)
		render.glyph    = td.get("glyph",    ".")
		render.fg_color = td.get("fg_color", Color(0.4, 0.4, 0.3))
		render.bg_color = td.get("bg_color", Color(0.1, 0.1, 0.05))
		render.z_layer  = 0


## TerrainGenSystem.gd
## Priority 0 — runs once in initialize() to populate the 128×128 map.
##
## Uses two layered FastNoiseLite passes:
##   Pass 1 (offset 0,0):    height  → tile type
##   Pass 2 (offset 200,200): moisture
##   Pass 3 (offset 400,400): temperature variation
##
## Each tile becomes one entity with TileComponent + BiomeComponent + RenderComponent.
class_name TerrainGenSystem
extends "res://core/SystemBase.gd"

const _TileComponent   = preload("res://modules/terrain/components/TileComponent.gd")
const _BiomeComponent  = preload("res://modules/terrain/components/BiomeComponent.gd")
const _RenderComponent = preload("res://modules/rendering/components/RenderComponent.gd")
const _TileTypes       = preload("res://modules/terrain/data/TileTypes.gd")
const _BiomeTypes      = preload("res://modules/terrain/data/BiomeTypes.gd")

## Change this to get a different world layout.
var noise_seed: int = 42

var _noise: FastNoiseLite = null

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_setup_noise()
	_generate()

func tick(_tick_number: int) -> void:
	pass  # One-shot; nothing to do per tick.

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed            = noise_seed
	_noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency       = 0.035
	_noise.fractal_octaves = 4
	_noise.fractal_gain    = 0.5

func _generate() -> void:
	var reg = world.get_registry()

	for y: int in range(world.MAP_HEIGHT):
		for x: int in range(world.MAP_WIDTH):
			var entity_id: int = world.create_entity()
			var pos := Vector2i(x, y)

			# --- Sample noise layers ---
			var height:      float = _noise.get_noise_2d(float(x), float(y))
			var moisture:    float = (_noise.get_noise_2d(float(x) + 200.0, float(y) + 200.0) + 1.0) * 0.5
			var temp_var:    float = _noise.get_noise_2d(float(x) + 400.0, float(y) + 400.0) * 0.15
			# Latitudinal temperature: cooler south (high y), warmer north (low y)
			var temperature: float = clampf(1.0 - (float(y) / float(world.MAP_HEIGHT)) + temp_var, 0.0, 1.0)

			var tile_type:  int = _classify_tile(height, moisture)
			var biome_type: int = _classify_biome(height, moisture, temperature)

			# --- TileComponent ---
			var tile = _TileComponent.new()
			tile.position  = pos
			tile.tile_type = tile_type
			reg.add(entity_id, tile)

			# --- BiomeComponent ---
			var biome = _BiomeComponent.new()
			biome.biome       = biome_type
			biome.moisture    = moisture
			biome.temperature = temperature
			reg.add(entity_id, biome)

			# --- RenderComponent (initial visual from tile type) ---
			var render = _RenderComponent.new()
			var td: Dictionary = _TileTypes.get_data(tile_type)
			render.glyph    = td["glyph"]
			render.fg_color = td["fg_color"]
			render.bg_color = td["bg_color"]
			reg.add(entity_id, render)

			# --- Register spatial position ---
			world.register_tile(entity_id, pos)

# ---------------------------------------------------------------------------
# Classification helpers
# ---------------------------------------------------------------------------

func _classify_tile(height: float, moisture: float) -> int:
	if height < -0.35:
		return _TileTypes.Type.MUD if moisture > 0.55 else _TileTypes.Type.DIRT
	elif height < 0.05:
		return _TileTypes.Type.GRASS
	elif height < 0.38:
		return _TileTypes.Type.GROUND
	else:
		return _TileTypes.Type.STONE

func _classify_biome(height: float, moisture: float, _temperature: float) -> int:
	if moisture > 0.62 and height < -0.1:
		return _BiomeTypes.Type.WETLAND
	elif moisture > 0.48 and height < 0.25:
		return _BiomeTypes.Type.FOREST_EDGE
	elif height > 0.32:
		return _BiomeTypes.Type.BARREN
	else:
		return _BiomeTypes.Type.PLAINS

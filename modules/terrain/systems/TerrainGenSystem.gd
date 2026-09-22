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
const _InventoryComponent = preload("res://modules/item/components/InventoryComponent.gd")
const _FluidComponent   = preload("res://modules/matter/components/FluidComponent.gd")
const _MaterialTypes   = preload("res://modules/matter/data/MaterialTypes.gd")

## Change this to get a different world layout.
var noise_seed: int = 42

## Local map embark configuration
## Current iteration: map is a local tile (not world tile) with Plains biome.
var local_biome: int = _BiomeTypes.Type.PLAINS
var plains_avg_temp: float = 0.50
var plains_avg_moisture: float = 0.48

## Generation configuration
var river_enabled: bool = true
var river_width: float = 1.6
var pond_count_min: int = 3
var pond_count_max: int = 5

var _noise: FastNoiseLite = null
var _rng: RandomNumberGenerator = null

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	if world != null:
		world.local_biome = local_biome
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

	_rng = RandomNumberGenerator.new()
	_rng.seed = noise_seed + 98765

func _generate() -> void:
	var reg = world.get_registry()
	var total_tiles: int = world.MAP_WIDTH * world.MAP_HEIGHT

	# Water volume and riparian moisture boost maps (1D arrays for fast O(1) access)
	var river_water_vol: PackedFloat32Array = PackedFloat32Array()
	river_water_vol.resize(total_tiles)
	river_water_vol.fill(0.0)

	var river_riparian: PackedFloat32Array = PackedFloat32Array()
	river_riparian.resize(total_tiles)
	river_riparian.fill(0.0)

	var pond_water_vol: PackedFloat32Array = PackedFloat32Array()
	pond_water_vol.resize(total_tiles)
	pond_water_vol.fill(0.0)

	var pond_riparian: PackedFloat32Array = PackedFloat32Array()
	pond_riparian.resize(total_tiles)
	pond_riparian.fill(0.0)

	var river_points: Array[Vector2] = []

	# --- 1. Procedural River System ---
	if river_enabled:
		river_points = _generate_river_system(river_water_vol, river_riparian)

	# --- 2. Procedural Small Ponds ---
	_generate_ponds(pond_water_vol, pond_riparian, river_points)

	# --- 3. Tile & Entity Generation Loop ---
	for y: int in range(world.MAP_HEIGHT):
		for x: int in range(world.MAP_WIDTH):
			var idx: int = y * world.MAP_WIDTH + x
			var entity_id: int = world.create_entity()
			var pos := Vector2i(x, y)

			# Sample base noise layers
			var base_height: float = _noise.get_noise_2d(float(x), float(y))

			# Combine river & pond water volumes and riparian moisture influence
			var r_vol: float = river_water_vol[idx]
			var p_vol: float = pond_water_vol[idx]
			var custom_water_vol: float = maxf(r_vol, p_vol)
			var rip_boost: float = maxf(river_riparian[idx], pond_riparian[idx])

			# Carve height in waterbed and riverbanks
			var height: float = base_height
			if custom_water_vol > 0.0:
				height = -0.42 if custom_water_vol < 0.4 else -0.52
			elif rip_boost > 0.0:
				height = base_height - rip_boost * 0.08

			# Local tile Plains climate:
			# Base temperature centered on average plains climate (0.50 ≈ 15°C base in spring/autumn)
			# with gentle microclimate noise (±0.03) and subtle elevation lapse rate
			var temp_noise: float = _noise.get_noise_2d(float(x) + 400.0, float(y) + 400.0) * 0.03
			var elevation_cooling: float = height * 0.04
			var temperature: float = clampf(plains_avg_temp + temp_noise - elevation_cooling, 0.0, 1.0)

			# Base moisture centered on average plains climate (0.48)
			# with natural soil moisture variation (±0.12) and riparian boost near water
			var moisture_noise: float = _noise.get_noise_2d(float(x) + 200.0, float(y) + 200.0) * 0.12
			var base_moisture: float = clampf(plains_avg_moisture + moisture_noise, 0.28, 0.65)
			var moisture: float = clampf(base_moisture + rip_boost * 0.35, 0.0, 1.0)
			if custom_water_vol > 0.0:
				moisture = 1.0

			# Classify tile type & biome
			# For current iteration, the entire map is a local tile with Plains biome throughout.
			var tile_type: int
			var biome_type: int = local_biome
			if custom_water_vol > 0.0:
				# Riverbeds and pond bottoms are saturated MUD
				tile_type = _TileTypes.Type.MUD
			else:
				tile_type = _classify_tile(height, moisture)

			# --- TileComponent ---
			var tile = _TileComponent.new()
			tile.position  = pos
			tile.tile_type = tile_type
			reg.add(entity_id, tile)

			# --- BiomeComponent ---
			var biome = _BiomeComponent.new()
			biome.biome         = biome_type
			biome.moisture      = moisture
			biome.base_moisture = moisture
			biome.temperature   = temperature
			reg.add(entity_id, biome)

			# --- Standing Water (Approach B: Dynamic Fluid Layer) ---
			var is_custom_water: bool = (custom_water_vol > 0.0)
			var is_base_water: bool   = (base_height < -0.38)
			var is_water: bool        = is_custom_water or is_base_water

			var is_deep_water: bool = false
			var water_volume: float = 0.0

			if is_custom_water:
				water_volume = custom_water_vol
				is_deep_water = (water_volume >= 0.4)
			elif is_base_water:
				is_deep_water = (base_height < -0.45)
				water_volume = 0.75 if is_deep_water else 0.25

			if is_water:
				var fluid = _FluidComponent.new()
				fluid.material_id = _MaterialTypes.Type.WATER
				fluid.settled     = true
				fluid.volume      = water_volume
				reg.add(entity_id, fluid)

			# --- RenderComponent (initial visual from water fluid or base tile) ---
			var render = _RenderComponent.new()
			if is_water:
				if is_deep_water:
					render.glyph    = "\u2248" # waves ≈
					render.fg_color = Color(0.25, 0.65, 1.0, 0.9)
					render.bg_color = Color(0.04, 0.12, 0.28)
				else:
					render.glyph    = "~"      # ripples ~
					render.fg_color = Color(0.35, 0.75, 1.0, 0.7)
					render.bg_color = Color(0.06, 0.16, 0.32)
			else:
				var td: Dictionary = _TileTypes.get_data(tile_type)
				render.glyph    = td["glyph"]
				render.fg_color = td["fg_color"]
				render.bg_color = td["bg_color"]
			reg.add(entity_id, render)

			# --- InventoryComponent (empty ground tile inventory) ---
			var inv = _InventoryComponent.new()
			reg.add(entity_id, inv)

			# --- Register spatial position ---
			world.register_tile(entity_id, pos)

# ---------------------------------------------------------------------------
# River & Pond Procedural Generation
# ---------------------------------------------------------------------------

## Generates main meandering river and optional tributary with ford crossings.
## Returns list of dense river path coordinates for distance checks.
func _generate_river_system(water_vol: PackedFloat32Array, riparian: PackedFloat32Array) -> Array[Vector2]:
	var w: int = world.MAP_WIDTH
	var h: int = world.MAP_HEIGHT
	var dense_path: Array[Vector2] = []

	# Determine primary flow direction: true = North->South, false = West->East
	var north_to_south: bool = _rng.randf() > 0.4

	var waypoints: Array[Vector2] = []
	var num_segments: int = 6

	if north_to_south:
		var start_x: float = _rng.randf_range(float(w) * 0.25, float(w) * 0.75)
		var end_x: float   = _rng.randf_range(float(w) * 0.25, float(w) * 0.75)
		waypoints.append(Vector2(start_x, 0.0))
		for i: int in range(1, num_segments):
			var t: float = float(i) / float(num_segments)
			var base_y: float = t * float(h - 1)
			var base_x: float = lerpf(start_x, end_x, t)
			var meander_x: float = base_x + _rng.randf_range(-22.0, 22.0)
			waypoints.append(Vector2(clampf(meander_x, 8.0, float(w - 9)), base_y))
		waypoints.append(Vector2(end_x, float(h - 1)))
	else:
		var start_y: float = _rng.randf_range(float(h) * 0.25, float(h) * 0.75)
		var end_y: float   = _rng.randf_range(float(h) * 0.25, float(h) * 0.75)
		waypoints.append(Vector2(0.0, start_y))
		for i: int in range(1, num_segments):
			var t: float = float(i) / float(num_segments)
			var base_x: float = t * float(w - 1)
			var base_y: float = lerpf(start_y, end_y, t)
			var meander_y: float = base_y + _rng.randf_range(-22.0, 22.0)
			waypoints.append(Vector2(base_x, clampf(meander_y, 8.0, float(h - 9))))
		waypoints.append(Vector2(float(w - 1), end_y))

	# Sample Catmull-Rom spline finely
	dense_path = _sample_spline(waypoints, 0.008)

	# Designate 2-3 ford crossings along the river length
	var ford_indices: Array[int] = []
	if dense_path.size() > 50:
		ford_indices.append(int(float(dense_path.size()) * 0.28))
		ford_indices.append(int(float(dense_path.size()) * 0.58))
		ford_indices.append(int(float(dense_path.size()) * 0.82))

	# Rasterize main river
	_rasterize_river_path(dense_path, river_width, ford_indices, water_vol, riparian)

	# 60% chance to generate a secondary tributary river merging into the main river
	if _rng.randf() < 0.6 and dense_path.size() > 60:
		var join_idx: int = _rng.randi_range(int(dense_path.size() * 0.35), int(dense_path.size() * 0.65))
		var join_pt: Vector2 = dense_path[join_idx]
		var trib_waypoints: Array[Vector2] = []

		if north_to_south:
			var trib_start_x: float = 0.0 if join_pt.x < float(w) * 0.5 else float(w - 1)
			var trib_start_y: float = clampf(join_pt.y + _rng.randf_range(-20.0, 20.0), 10.0, float(h - 11))
			trib_waypoints.append(Vector2(trib_start_x, trib_start_y))
			var mid_x: float = lerpf(trib_start_x, join_pt.x, 0.5)
			var mid_y: float = lerpf(trib_start_y, join_pt.y, 0.5) + _rng.randf_range(-15.0, 15.0)
			trib_waypoints.append(Vector2(mid_x, clampf(mid_y, 8.0, float(h - 9))))
			trib_waypoints.append(join_pt)
		else:
			var trib_start_y: float = 0.0 if join_pt.y < float(h) * 0.5 else float(h - 1)
			var trib_start_x: float = clampf(join_pt.x + _rng.randf_range(-20.0, 20.0), 10.0, float(w - 11))
			trib_waypoints.append(Vector2(trib_start_x, trib_start_y))
			var mid_x: float = lerpf(trib_start_x, join_pt.x, 0.5) + _rng.randf_range(-15.0, 15.0)
			var mid_y: float = lerpf(trib_start_y, join_pt.y, 0.5)
			trib_waypoints.append(Vector2(clampf(mid_x, 8.0, float(w - 9)), mid_y))
			trib_waypoints.append(join_pt)

		var trib_dense: Array[Vector2] = _sample_spline(trib_waypoints, 0.012)
		_rasterize_river_path(trib_dense, river_width * 0.75, [], water_vol, riparian)
		dense_path.append_array(trib_dense)

	return dense_path

## Generates small organic ponds scattered in non-mountainous, inland areas.
func _generate_ponds(
	water_vol: PackedFloat32Array,
	riparian: PackedFloat32Array,
	river_points: Array[Vector2]
) -> void:
	var w: int = world.MAP_WIDTH
	var h: int = world.MAP_HEIGHT
	var target_ponds: int = _rng.randi_range(pond_count_min, pond_count_max)
	var pond_centers: Array[Vector2] = []

	var attempts: int = 0
	while pond_centers.size() < target_ponds and attempts < 200:
		attempts += 1
		var cx: float = _rng.randf_range(12.0, float(w - 13))
		var cy: float = _rng.randf_range(12.0, float(h - 13))
		var candidate := Vector2(cx, cy)

		# Elevation check: avoid steep mountain peaks (stone/barren) and deep oceans
		var base_h: float = _noise.get_noise_2d(cx, cy)
		if base_h < -0.25 or base_h > 0.28:
			continue

		# Distance check from other ponds
		var too_close: bool = false
		for pc: Vector2 in pond_centers:
			if candidate.distance_to(pc) < 22.0:
				too_close = true
				break
		if too_close:
			continue

		# Distance check from river path
		for rp: Vector2 in river_points:
			if candidate.distance_to(rp) < 14.0:
				too_close = true
				break
		if too_close:
			continue

		pond_centers.append(candidate)
		var base_radius: float = _rng.randf_range(2.4, 4.0)
		_rasterize_pond(candidate, base_radius, water_vol, riparian)

## Rasterizes a spline path into water volume and riparian moisture arrays.
func _rasterize_river_path(
	path: Array[Vector2],
	base_width: float,
	ford_indices: Array[int],
	water_vol: PackedFloat32Array,
	riparian: PackedFloat32Array
) -> void:
	var w: int = world.MAP_WIDTH
	var h: int = world.MAP_HEIGHT

	for i: int in range(path.size()):
		var pt: Vector2 = path[i]

		# Check if this segment is part of a ford crossing (width ~7 samples around index)
		var is_ford: bool = false
		for f_idx: int in ford_indices:
			if absi(i - f_idx) <= 7:
				is_ford = true
				break

		# Apply high-frequency noise perturbation to add organic river wiggles
		var noise_disp := Vector2(
			_noise.get_noise_2d(pt.x * 2.5, pt.y * 2.5),
			_noise.get_noise_2d(pt.x * 2.5 + 150.0, pt.y * 2.5 + 150.0)
		) * 1.5
		var perturbed_pt: Vector2 = pt + noise_disp

		var r_eff: float = base_width * (0.85 if is_ford else 1.0)
		var r_deep: float = r_eff * 0.55
		var r_riparian: float = r_eff + 2.5

		var min_x: int = clampi(int(floorf(perturbed_pt.x - r_riparian)), 0, w - 1)
		var max_x: int = clampi(int(ceilf(perturbed_pt.x + r_riparian)), 0, w - 1)
		var min_y: int = clampi(int(floorf(perturbed_pt.y - r_riparian)), 0, h - 1)
		var max_y: int = clampi(int(ceilf(perturbed_pt.y + r_riparian)), 0, h - 1)

		for ty: int in range(min_y, max_y + 1):
			for tx: int in range(min_x, max_x + 1):
				var idx: int = ty * w + tx
				var d: float = perturbed_pt.distance_to(Vector2(float(tx), float(ty)))

				if d <= r_eff:
					# Water channel
					var vol: float
					if is_ford:
						vol = 0.25 # Ford crossing is always shallow walkable water
					elif d <= r_deep:
						vol = 0.75 # Deep central water
					else:
						vol = 0.25 # Shallow edges
					if vol > water_vol[idx]:
						water_vol[idx] = vol

				if d <= r_riparian:
					# Riparian moisture boost gradient
					var factor: float = clampf(1.0 - (d / r_riparian), 0.0, 1.0)
					if factor > riparian[idx]:
						riparian[idx] = factor

## Rasterizes an organic, non-circular small pond.
func _rasterize_pond(
	center: Vector2,
	radius: float,
	water_vol: PackedFloat32Array,
	riparian: PackedFloat32Array
) -> void:
	var w: int = world.MAP_WIDTH
	var h: int = world.MAP_HEIGHT
	var phase: float = _rng.randf() * TAU
	var r_max_extent: float = radius * 1.4 + 2.5

	var min_x: int = clampi(int(floorf(center.x - r_max_extent)), 0, w - 1)
	var max_x: int = clampi(int(ceilf(center.x + r_max_extent)), 0, w - 1)
	var min_y: int = clampi(int(floorf(center.y - r_max_extent)), 0, h - 1)
	var max_y: int = clampi(int(ceilf(center.y + r_max_extent)), 0, h - 1)

	for ty: int in range(min_y, max_y + 1):
		for tx: int in range(min_x, max_x + 1):
			var idx: int = ty * w + tx
			var pos := Vector2(float(tx), float(ty))
			var angle: float = (pos - center).angle()
			var wobble: float = 1.0 + 0.22 * sin(3.0 * angle + phase) + 0.14 * cos(2.0 * angle)
			var r_eff: float = radius * wobble
			var r_deep: float = r_eff * 0.50
			var r_rip: float = r_eff + 2.2

			var d: float = center.distance_to(pos)
			if d <= r_eff:
				var vol: float = 0.75 if d <= r_deep else 0.25
				if vol > water_vol[idx]:
					water_vol[idx] = vol
			if d <= r_rip:
				var factor: float = clampf(1.0 - (d / r_rip), 0.0, 1.0)
				if factor > riparian[idx]:
					riparian[idx] = factor

## Samples a Catmull-Rom spline through waypoints.
func _sample_spline(pts: Array[Vector2], step_t: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if pts.size() < 2:
		return result

	# Add phantom boundary points for smooth Catmull-Rom tangents at ends
	var p_first: Vector2 = pts[0] * 2.0 - pts[1]
	var p_last: Vector2  = pts[pts.size() - 1] * 2.0 - pts[pts.size() - 2]

	var full_pts: Array[Vector2] = [p_first]
	full_pts.append_array(pts)
	full_pts.append(p_last)

	for i: int in range(1, full_pts.size() - 2):
		var p0: Vector2 = full_pts[i - 1]
		var p1: Vector2 = full_pts[i]
		var p2: Vector2 = full_pts[i + 1]
		var p3: Vector2 = full_pts[i + 2]

		var t: float = 0.0
		while t < 1.0:
			result.append(_catmull_rom(p0, p1, p2, p3, t))
			t += step_t

	result.append(pts[pts.size() - 1])
	return result

static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

# ---------------------------------------------------------------------------
# Classification helpers
# ---------------------------------------------------------------------------

func _classify_tile(height: float, moisture: float) -> int:
	if height < -0.35:
		return _TileTypes.Type.MUD if moisture > 0.55 else _TileTypes.Type.DIRT
	elif height < 0.22:
		return _TileTypes.Type.GRASS
	elif height < 0.38:
		return _TileTypes.Type.GROUND
	else:
		return _TileTypes.Type.STONE

func _classify_biome(_height: float, _moisture: float, _temperature: float) -> int:
	# Local embark tile is set to local_biome (Plains)
	return local_biome



## SignalGrid.gd
## Represents a high-performance 2D spatial float channel over the world map (128x128).
## Encapsulates O(1) indexed reads, radial impulse splashing, spatial gradient computation,
## decay, and wind-driven atmospheric advection.
class_name SignalGrid
extends RefCounted

const _SignalTypes = preload("res://modules/signal/data/SignalTypes.gd")

## Unique identifier for this channel (e.g. &"hazard", &"hydration", &"sound").
var name: StringName

## One of SignalTypes.PropagationType.
var propagation_type: int

## Retention factor per tick for DIFFUSE_DRIFT channels (e.g. 0.95 = 5% decay per tick).
var decay_rate: float = 0.95

## Rate at which lingering signals bleed into neighboring tiles.
var diffusion_rate: float = 0.04

## Grid dimensions (defaults to World.MAP_WIDTH x World.MAP_HEIGHT).
var width: int = 128
var height: int = 128

## Primary float buffer, clamped to [0.0, 1.0].
var data: PackedFloat32Array

## Reusable secondary buffer for advection/diffusion to prevent mid-iteration feedback.
var _scratch_data: PackedFloat32Array

func _init(
	p_name: StringName,
	p_type: int = _SignalTypes.PropagationType.STATIC_SNAPSHOT,
	p_decay: float = 0.95,
	p_diffuse: float = 0.04,
	p_w: int = 128,
	p_h: int = 128
) -> void:
	name = p_name
	propagation_type = p_type
	decay_rate = clampf(p_decay, 0.0, 1.0)
	diffusion_rate = clampf(p_diffuse, 0.0, 0.25)
	width = p_w
	height = p_h
	
	var total_cells: int = width * height
	data.resize(total_cells)
	data.fill(0.0)
	
	if propagation_type == _SignalTypes.PropagationType.DIFFUSE_DRIFT:
		_scratch_data.resize(total_cells)
		_scratch_data.fill(0.0)

# ===========================================================================
# Direct Point Access (Normalized Intensity: 0.0 to 1.0)
# ===========================================================================

## Returns normalized signal intensity [0.0, 1.0] at pos.
func get_value(pos: Vector2i) -> float:
	if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
		return 0.0
	return data[pos.y * width + pos.x]

## Sets signal intensity at pos (clamped to [0.0, 1.0]).
func set_value(pos: Vector2i, val: float) -> void:
	if pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height:
		data[pos.y * width + pos.x] = clampf(val, 0.0, 1.0)

func add_value(pos: Vector2i, val: float) -> void:
	if pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height:
		var idx: int = pos.y * width + pos.x
		data[idx] = clampf(data[idx] + val, 0.0, 1.0)

## Reset all cells in the grid to a specific scalar value (e.g. 0.0).
func fill(val: float) -> void:
	data.fill(clampf(val, 0.0, 1.0))

# ===========================================================================
# Radial Impulse (Acoustics, Explosions, Scent Puffs)
# ===========================================================================

## Add a radial splash of signal with linear distance falloff.
## At center distance 0, adds intensity. At boundary distance == radius, adds 0.
func add_impulse(center: Vector2i, intensity: float, radius: int) -> void:
	if radius <= 0 or intensity <= 0.0:
		set_value(center, intensity)
		return

	var min_x: int = clampi(center.x - radius, 0, width - 1)
	var max_x: int = clampi(center.x + radius, 0, width - 1)
	var min_y: int = clampi(center.y - radius, 0, height - 1)
	var max_y: int = clampi(center.y + radius, 0, height - 1)
	var inv_r: float = 1.0 / float(radius)

	for y in range(min_y, max_y + 1):
		var dy: int = y - center.y
		var dy_sq: int = dy * dy
		var row_idx: int = y * width
		for x in range(min_x, max_x + 1):
			var dx: int = x - center.x
			var dist: float = sqrt(float(dx * dx + dy_sq))
			if dist <= radius:
				var falloff: float = 1.0 - (dist * inv_r)
				var idx: int = row_idx + x
				data[idx] = clampf(data[idx] + intensity * falloff, 0.0, 1.0)

# ===========================================================================
# Spatial Query & Utility Gradient Helpers
# ===========================================================================

## Computes the 2D spatial gradient (Sobel / central differences) of the signal at pos.
## Returns a Vector2 pointing in the direction of steepest increase.
## - Moving along +gradient tracks the scent source / water.
## - Moving along -gradient flees hazards / predators.
func sample_gradient(pos: Vector2i) -> Vector2:
	if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
		return Vector2.ZERO

	var left: float  = get_value(pos + Vector2i(-1, 0))
	var right: float = get_value(pos + Vector2i(1, 0))
	var up: float    = get_value(pos + Vector2i(0, -1))
	var down: float  = get_value(pos + Vector2i(0, 1))

	var gx: float = (right - left) * 0.5
	var gy: float = (down - up) * 0.5
	return Vector2(gx, gy)

## Finds the tile position with the maximum signal value within radius.
func sample_highest_in_radius(center: Vector2i, radius: int) -> Vector2i:
	var best_pos: Vector2i = center
	var max_val: float = -1.0

	var min_x: int = clampi(center.x - radius, 0, width - 1)
	var max_x: int = clampi(center.x + radius, 0, width - 1)
	var min_y: int = clampi(center.y - radius, 0, height - 1)
	var max_y: int = clampi(center.y + radius, 0, height - 1)

	for y in range(min_y, max_y + 1):
		var row_idx: int = y * width
		for x in range(min_x, max_x + 1):
			var val: float = data[row_idx + x]
			if val > max_val:
				max_val = val
				best_pos = Vector2i(x, y)

	return best_pos

# ===========================================================================
# Simulation Tick: Decay & Wind Advection (DIFFUSE_DRIFT only)
# ===========================================================================

## Updates lingering signals: applies exponential decay and diffuses outward,
## biased downwind based on wind direction and intensity.
func decay_and_advect(wind_dir: Vector2, wind_strength: float) -> void:
	if propagation_type != _SignalTypes.PropagationType.DIFFUSE_DRIFT:
		return

	var total_cells: int = width * height
	_scratch_data.fill(0.0)

	var wind_bias: Vector2 = wind_dir.normalized() * clampf(wind_strength, 0.0, 1.0)
	var w_east: float  = maxf(0.0, 0.25 + wind_bias.x * 0.2)
	var w_west: float  = maxf(0.0, 0.25 - wind_bias.x * 0.2)
	var w_south: float = maxf(0.0, 0.25 + wind_bias.y * 0.2)
	var w_north: float = maxf(0.0, 0.25 - wind_bias.y * 0.2)
	var total_w: float = w_east + w_west + w_south + w_north
	if total_w > 0.0:
		w_east /= total_w
		w_west /= total_w
		w_south /= total_w
		w_north /= total_w

	for y in range(height):
		var row_idx: int = y * width
		for x in range(width):
			var val: float = data[row_idx + x]
			if val <= 0.005:
				continue

			# 1. Decay
			var decayed_val: float = val * decay_rate
			if decayed_val <= 0.002:
				continue

			# 2. Diffusion / Spread
			var diffused_portion: float = decayed_val * diffusion_rate
			var retained_portion: float = decayed_val - diffused_portion

			_scratch_data[row_idx + x] += retained_portion

			# Spread to 4 neighbors with wind-biased weights
			if x + 1 < width:
				_scratch_data[row_idx + (x + 1)] += diffused_portion * w_east
			if x - 1 >= 0:
				_scratch_data[row_idx + (x - 1)] += diffused_portion * w_west
			if y + 1 < height:
				_scratch_data[(y + 1) * width + x] += diffused_portion * w_south
			if y - 1 >= 0:
				_scratch_data[(y - 1) * width + x] += diffused_portion * w_north

	# Swap scratch into primary data with clamping
	for i in range(total_cells):
		data[i] = clampf(_scratch_data[i], 0.0, 1.0)

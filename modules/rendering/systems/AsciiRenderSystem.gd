## AsciiRenderSystem.gd
## Node2D that draws the world as coloured ASCII characters every frame.
##
## Wind animation:
##   A traveling sine wave propagates in the current wind direction.
##   Each tile's phase = dot(tile_pos, wind_dir) * WAVE_FREQ.
##   wave = sin(phase − time_sec × wind_strength × WAVE_SPEED) × wind_strength
##   Vegetation with sway_factor > 0 switches to its sway_glyph when the wave
##   crest passes, and has its fg_color brightened (or dimmed on the trough).
##
## Only tiles visible in the current camera viewport are drawn (culling).
## Swap to PNG: replace _draw() internals — ECS data unchanged.
extends Node2D

const _VegTypes = preload("res://modules/vegetation/data/VegetationTypes.gd")

# ---------------------------------------------------------------------------
# Display constants
# ---------------------------------------------------------------------------
const CELL_W:     int   = 11   # pixels per character cell (horizontal)
const CELL_H:     int   = 18   # pixels per character cell (vertical)
const FONT_SIZE:  int   = 15   # font point size
const WAVE_FREQ:  float = 0.40 # spatial frequency of the wind wave
const WAVE_SPEED: float = 6.0  # wave propagation speed multiplier
const SWAY_THRESHOLD: float = 0.38  # wave value above which sway glyph activates

# ---------------------------------------------------------------------------
# Node references & cached state
# ---------------------------------------------------------------------------
var _world: Node      = null
var _camera: Camera2D = null
var _font:   Font     = null

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_world  = get_node("/root/World")
	_camera = get_node_or_null("../WorldCamera")
	_font   = _build_font()

func _process(_delta: float) -> void:
	queue_redraw()  # every frame — viewport culling keeps this fast

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var reg = _world.get_registry()

	# Wind state (read once per frame)
	var wind_dir: Vector2 = _world.wind_direction
	var wind_str: float   = _world.wind_strength
	var time_sec: float   = float(Time.get_ticks_msec()) / 1000.0
	var has_wind: bool    = wind_str > 0.05

	# Visible tile range (viewport culling)
	var vis: Rect2i = _visible_tile_range()

	for y: int in range(vis.position.y, vis.end.y):
		for x: int in range(vis.position.x, vis.end.x):
			var entity_id: int = _world.get_entity_at(Vector2i(x, y))
			if entity_id == -1:
				continue

			var render = reg.get_component(entity_id, &"RenderComponent")
			if render == null:
				continue

			var px: Vector2 = Vector2(float(x) * CELL_W, float(y) * CELL_H)
			var glyph: String = render.glyph
			var color: Color  = render.fg_color

			# ---------------------------------------------------------------
			# Wind sway animation (vegetation only)
			# ---------------------------------------------------------------
			if has_wind:
				var veg = reg.get_component(entity_id, &"VegetationComponent")
				if veg != null:
					var wave: float = _calc_wave(x, y, time_sec, wind_dir, wind_str)
					var vd: Dictionary = _VegTypes.get_data(veg.veg_type)
					var sf: float = vd.get("sway_factor", 1.0) as float

					var effective: float = wave * sf
					if effective > SWAY_THRESHOLD:
						# Crest — switch to sway glyph, lighten colour
						glyph = _VegTypes.get_sway_glyph(veg.veg_type, veg.growth_stage)
						color = render.fg_color.lightened(effective * 0.22)
					elif effective < -SWAY_THRESHOLD * 0.8:
						# Trough — slightly dim (compressed by wind)
						color = render.fg_color.darkened(abs(effective) * 0.12)

			# ---------------------------------------------------------------
			# Draw background cell then foreground glyph
			# ---------------------------------------------------------------
			draw_rect(Rect2(px, Vector2(CELL_W, CELL_H)), render.bg_color)
			if glyph.length() > 0:
				draw_char(
					_font,
					px + Vector2(1.0, float(CELL_H) - 3.0),
					glyph[0],
					FONT_SIZE,
					color
				)

# ---------------------------------------------------------------------------
# Wind wave helpers
# ---------------------------------------------------------------------------

## Returns the wave value for tile (x, y) at time t.
## Range is roughly -wind_str..+wind_str.
func _calc_wave(x: int, y: int, t: float,
		wind_dir: Vector2, wind_str: float) -> float:
	var pos   := Vector2(float(x), float(y))
	var phase: float = pos.dot(wind_dir) * WAVE_FREQ
	return sin(phase - t * wind_str * WAVE_SPEED) * wind_str

# ---------------------------------------------------------------------------
# Viewport culling
# ---------------------------------------------------------------------------

func _visible_tile_range() -> Rect2i:
	var vp_size: Vector2 = get_viewport_rect().size
	var cam_pos:  Vector2 = Vector2.ZERO
	var cam_zoom: Vector2 = Vector2.ONE

	if _camera != null:
		cam_pos  = _camera.global_position
		cam_zoom = _camera.zoom

	var half: Vector2 = vp_size * 0.5 / cam_zoom

	var left:   int = int((cam_pos.x - half.x) / float(CELL_W)) - 1
	var top:    int = int((cam_pos.y - half.y) / float(CELL_H)) - 1
	var right:  int = int((cam_pos.x + half.x) / float(CELL_W)) + 2
	var bottom: int = int((cam_pos.y + half.y) / float(CELL_H)) + 2

	left   = clampi(left,   0, _world.MAP_WIDTH)
	top    = clampi(top,    0, _world.MAP_HEIGHT)
	right  = clampi(right,  0, _world.MAP_WIDTH)
	bottom = clampi(bottom, 0, _world.MAP_HEIGHT)

	return Rect2i(left, top, right - left, bottom - top)

# ---------------------------------------------------------------------------
# Font — Caves of Qud terminal feel
# ---------------------------------------------------------------------------

func _build_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Lucida Console",   # tightest pixel grid on Windows
		"Consolas",
		"Courier New",
		"Courier",
		"monospace",
	])
	f.font_weight              = 700
	f.antialiasing             = TextServer.FONT_ANTIALIASING_NONE
	f.subpixel_positioning     = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f

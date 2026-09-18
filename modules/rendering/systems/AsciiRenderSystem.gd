## AsciiRenderSystem.gd
## High-performance GPU Shader-driven Quad renderer for the world ASCII simulation.
##
## Architecture (Stage 2):
##   - Entire 128x128 map is drawn in 1 single GPU draw call using a full-world
##     quad (ColorRect) with custom GLSL canvas shader (ascii_screen.gdshader).
##   - 3 dynamic 128x128 ImageTextures (bg_texture, fg_texture, glyph_texture)
##     are updated ONLY on simulation ticks (10 TPS), not every display frame.
##   - Wind wave sine propagation, vegetation sway, burning flame flicker,
##     rain puddle tinting, and animated rain drops run 100% in parallel on GPU.
##   - CPU frame time drops to ~0.00ms (only passes 4 uniform variables per frame).
extends Node2D

const _VegTypes = preload("res://modules/vegetation/data/VegetationTypes.gd")
const _AsciiShader = preload("res://modules/rendering/shaders/ascii_screen.gdshader")

# ---------------------------------------------------------------------------
# Display constants
# ---------------------------------------------------------------------------
const CELL_W:    int = 11   # pixels per character cell (horizontal)
const CELL_H:    int = 18   # pixels per character cell (vertical)
const FONT_SIZE: int = 15   # font point size

# ---------------------------------------------------------------------------
# Font Atlas Drawer (internal SubViewport child)
# ---------------------------------------------------------------------------
class AtlasDrawer extends Node2D:
	var font: Font = null

	func _draw() -> void:
		if font == null:
			return
		for i: int in range(256):
			var col: int = i % 16
			var row: int = floori(float(i) / 16.0)
			var px := Vector2(float(col * CELL_W), float(row * CELL_H))
			var ch: String = ""

			# Map CP437 / extended Unicode symbols used in simulation
			if i == 183 or i == 250:
				ch = "\u00B7" # middle dot ·
			elif i == 176:
				ch = "\u2591" # light shade ░
			elif i == 177:
				ch = "\u2592" # medium shade ▒
			elif i == 178:
				ch = "\u2593" # dark shade ▓
			elif i == 219:
				ch = "\u2588" # full block █
			elif i >= 32 and i <= 126:
				ch = String.chr(i)

			# Draw white character glyph on transparent background
			if ch.length() == 1 and ch != " ":
				draw_char(font, px + Vector2(1.0, float(CELL_H) - 3.0), ch, FONT_SIZE, Color.WHITE)

# ---------------------------------------------------------------------------
# Node references & state
# ---------------------------------------------------------------------------
var _world: Node = null
var _camera: Camera2D = null
var _font: Font = null

var _screen_quad: ColorRect = null
var _shader_mat: ShaderMaterial = null

var _bg_image: Image = null
var _fg_image: Image = null
var _data_image: Image = null

var _bg_tex: ImageTexture = null
var _fg_tex: ImageTexture = null
var _data_tex: ImageTexture = null

# Flat pre-cached buffers to eliminate 16,384 Vector2i allocations and dict queries per tick
var _tile_entity_ids: PackedInt32Array = PackedInt32Array()
var _bg_bytes:   PackedByteArray = PackedByteArray()
var _fg_bytes:   PackedByteArray = PackedByteArray()
var _data_bytes: PackedByteArray = PackedByteArray()

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_world  = get_node("/root/World")
	_camera = get_node_or_null("../WorldCamera")
	_font   = _build_font()

	_setup_shader_quad()
	_setup_font_atlas()

	_world.tick_processed.connect(_on_tick_processed)
	_world.world_ready.connect(_rebuild_simulation_textures)

	if _world.get_registry() != null:
		_rebuild_simulation_textures()

func _process(_delta: float) -> void:
	if _shader_mat == null or _world == null:
		return

	# Only 4 uniform updates per frame — ZERO tile looping on CPU!
	var time_sec: float = float(Time.get_ticks_msec()) / 1000.0
	_shader_mat.set_shader_parameter("time_sec", time_sec)
	_shader_mat.set_shader_parameter("wind_dir", _world.wind_direction)
	_shader_mat.set_shader_parameter("wind_strength", _world.wind_strength)
	if _camera != null:
		_shader_mat.set_shader_parameter("zoom_level", _camera.zoom.x)

func _on_tick_processed(_tick_number: int) -> void:
	_update_simulation_textures()

# ---------------------------------------------------------------------------
# Setup & Texture Pipeline
# ---------------------------------------------------------------------------

func _setup_shader_quad() -> void:
	var w: int = _world.MAP_WIDTH
	var h: int = _world.MAP_HEIGHT
	var world_size := Vector2(float(w * CELL_W), float(h * CELL_H))

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = _AsciiShader

	_screen_quad = ColorRect.new()
	_screen_quad.name = "ScreenQuad"
	_screen_quad.position = Vector2.ZERO
	_screen_quad.size = world_size
	_screen_quad.custom_minimum_size = world_size
	_screen_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_quad.material = _shader_mat
	add_child(_screen_quad)

func _setup_font_atlas() -> void:
	var atlas_vp := SubViewport.new()
	atlas_vp.name = "FontAtlasViewport"
	atlas_vp.size = Vector2i(16 * CELL_W, 16 * CELL_H)
	atlas_vp.transparent_bg = true
	atlas_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(atlas_vp)

	var drawer := AtlasDrawer.new()
	drawer.font = _font
	atlas_vp.add_child(drawer)

	# Set placeholder texture for initial frame
	var empty_img = Image.create_empty(16 * CELL_W, 16 * CELL_H, false, Image.FORMAT_RGBA8)
	_shader_mat.set_shader_parameter("font_atlas", ImageTexture.create_from_image(empty_img))

	_bake_static_atlas.call_deferred(atlas_vp)

func _bake_static_atlas(atlas_vp: SubViewport) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(atlas_vp):
		return
	var img: Image = atlas_vp.get_texture().get_image()
	if img != null and not img.is_empty():
		var static_tex: ImageTexture = ImageTexture.create_from_image(img)
		_shader_mat.set_shader_parameter("font_atlas", static_tex)
		atlas_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		atlas_vp.queue_free()

func _rebuild_simulation_textures() -> void:
	var w: int = _world.MAP_WIDTH
	var h: int = _world.MAP_HEIGHT
	var total_tiles: int = w * h
	var total_bytes: int = total_tiles * 4

	# Pre-cache flat tile entity IDs to avoid Vector2i allocations and dictionary lookups on tick
	_tile_entity_ids.resize(total_tiles)
	for y: int in range(h):
		var row_offset: int = y * w
		for x: int in range(w):
			_tile_entity_ids[row_offset + x] = _world.get_entity_at(Vector2i(x, y))

	# Pre-allocate reusable byte buffers
	_bg_bytes.resize(total_bytes)
	_fg_bytes.resize(total_bytes)
	_data_bytes.resize(total_bytes)

	_bg_image   = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _bg_bytes)
	_fg_image   = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _fg_bytes)
	_data_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _data_bytes)

	_bg_tex   = ImageTexture.create_from_image(_bg_image)
	_fg_tex   = ImageTexture.create_from_image(_fg_image)
	_data_tex = ImageTexture.create_from_image(_data_image)

	_shader_mat.set_shader_parameter("bg_texture", _bg_tex)
	_shader_mat.set_shader_parameter("fg_texture", _fg_tex)
	_shader_mat.set_shader_parameter("glyph_texture", _data_tex)

	_update_simulation_textures()

func _update_simulation_textures() -> void:
	var reg = _world.get_registry()
	if reg == null or _bg_tex == null:
		return

	var w: int = _world.MAP_WIDTH
	var h: int = _world.MAP_HEIGHT
	var total_tiles: int = w * h

	if _tile_entity_ids.size() != total_tiles:
		_rebuild_simulation_textures()
		return

	var render_store: Dictionary = reg.get_store(&"RenderComponent")
	var rain_store:   Dictionary = reg.get_store(&"RainComponent")
	var veg_store:    Dictionary = reg.get_store(&"VegetationComponent")
	var burn_store:   Dictionary = reg.get_store(&"BurningComponent")
	var frozen_store: Dictionary = reg.get_store(&"FrozenComponent")

	for idx: int in range(total_tiles):
		var eid: int = _tile_entity_ids[idx]
		if eid == -1:
			continue

		var r = render_store.get(eid, null)
		if r == null:
			continue

		var byte_idx: int = idx * 4
		var bg: Color = r.bg_color
		var fg: Color = r.fg_color

		# 1. Background color (fast native 8-bit getters, no float math or clamp)
		_bg_bytes[byte_idx]     = bg.r8
		_bg_bytes[byte_idx + 1] = bg.g8
		_bg_bytes[byte_idx + 2] = bg.b8
		_bg_bytes[byte_idx + 3] = bg.a8

		# 2. Foreground color (fast native 8-bit getters, no float math or clamp)
		_fg_bytes[byte_idx]     = fg.r8
		_fg_bytes[byte_idx + 1] = fg.g8
		_fg_bytes[byte_idx + 2] = fg.b8
		_fg_bytes[byte_idx + 3] = fg.a8

		# 3. Data: Red = base glyph
		_data_bytes[byte_idx] = _glyph_to_code(r.glyph)

		# Green = sway glyph, Blue = sway factor
		var veg = veg_store.get(eid, null)
		if veg != null:
			var vd: Dictionary = _VegTypes.get_data(veg.veg_type)
			var sf: float = vd.get("sway_factor", 1.0) as float
			var sg: String = _VegTypes.get_sway_glyph(veg.veg_type, veg.growth_stage)
			_data_bytes[byte_idx + 1] = _glyph_to_code(sg)
			_data_bytes[byte_idx + 2] = int(clampf(sf, 0.0, 1.0) * 255.0)
		else:
			_data_bytes[byte_idx + 1] = 0
			_data_bytes[byte_idx + 2] = 0

		# Alpha = packed flags:
		# bit 0: is_burning
		# bit 1: is_frozen
		# bits 2..7: rain intensity (0..63)
		var flags: int = 0
		if burn_store.has(eid):
			flags |= 1
		if frozen_store.has(eid):
			flags |= 2
		var rain = rain_store.get(eid, null)
		if rain != null and rain.intensity > 0.0:
			var ri_int: int = clampi(int(rain.intensity * 63.0), 0, 63)
			flags |= (ri_int << 2)
		_data_bytes[byte_idx + 3] = flags

	_bg_image.set_data(w, h, false, Image.FORMAT_RGBA8, _bg_bytes)
	_fg_image.set_data(w, h, false, Image.FORMAT_RGBA8, _fg_bytes)
	_data_image.set_data(w, h, false, Image.FORMAT_RGBA8, _data_bytes)

	_bg_tex.update(_bg_image)
	_fg_tex.update(_fg_image)
	_data_tex.update(_data_image)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _glyph_to_code(g: String) -> int:
	if g.is_empty():
		return 32 # space
	var code: int = g.unicode_at(0)
	if code <= 255:
		return code
	# Map common Unicode symbols to extended CP437 byte range 128..255:
	match code:
		0x00B7: return 183 # middle dot ·
		0x2591: return 176 # light shade ░
		0x2592: return 177 # medium shade ▒
		0x2593: return 178 # dark shade ▓
		0x2588: return 219 # full block █
		_:      return 63  # '?'

func _build_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Lucida Console",
		"Consolas",
		"Courier New",
		"Courier",
		"monospace",
	])
	f.font_weight          = 700
	f.antialiasing         = TextServer.FONT_ANTIALIASING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f

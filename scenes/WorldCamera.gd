## WorldCamera.gd
## Free-pan, scroll-zoom camera for the world view.
##
## Controls:
##   Middle mouse button drag  — pan
##   Right mouse button drag   — pan (alternative)
##   Scroll wheel up/down      — zoom in/out
##   Arrow keys / WASD         — nudge pan
extends Camera2D

const ZOOM_MIN:    float = 0.25
const ZOOM_MAX:    float = 5.0
const ZOOM_STEP:   float = 0.25
const KEY_PAN_SPEED: float = 650.0  # pixels per second at zoom 1.0
const SMOOTH_FACTOR: float = 24.0   # lerp response rate

var _dragging: bool   = false
var _drag_start: Vector2 = Vector2.ZERO
var _cam_start:  Vector2 = Vector2.ZERO

var _target_position: Vector2 = Vector2.ZERO
var _target_zoom:     Vector2 = Vector2(1.5, 1.5)

func _ready() -> void:
	# Start centred on the map (128 × 128 tiles at 18×18 px each)
	var cx: float = float(World.MAP_WIDTH)  * 18.0 * 0.5
	var cy: float = float(World.MAP_HEIGHT) * 18.0 * 0.5
	position = Vector2(cx, cy)
	zoom     = Vector2(1.5, 1.5)
	_target_position = position
	_target_zoom     = zoom

func _input(event: InputEvent) -> void:
	# --- Zoom via scroll wheel ---
	if event is InputEventMouseButton:
		var mbe: InputEventMouseButton = event as InputEventMouseButton
		if mbe.pressed:
			if mbe.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_zoom(ZOOM_STEP)
			elif mbe.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_zoom(-ZOOM_STEP)

		# --- Pan via mouse drag ---
		if mbe.button_index == MOUSE_BUTTON_MIDDLE \
				or mbe.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mbe.pressed
			if _dragging:
				_drag_start = mbe.global_position
				_cam_start  = _target_position

	if event is InputEventMouseMotion and _dragging:
		var mme: InputEventMouseMotion = event as InputEventMouseMotion
		_target_position = _cam_start - (mme.global_position - _drag_start) / zoom

func _process(delta: float) -> void:
	# --- Keyboard pan (delta-scaled) ---
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		_target_position += dir.normalized() * (KEY_PAN_SPEED * delta / _target_zoom.x)

	# --- Smooth interpolation with exact exponential decay to eliminate VSync frame-pacing judder ---
	var t: float = 1.0 - exp(-SMOOTH_FACTOR * delta)
	position = position.lerp(_target_position, t)
	zoom     = zoom.lerp(_target_zoom, t)

func _adjust_zoom(delta: float) -> void:
	var nz: float = clampf(_target_zoom.x + delta, ZOOM_MIN, ZOOM_MAX)
	_target_zoom = Vector2(nz, nz)

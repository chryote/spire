## WeatherSystem.gd
## Priority 5 — runs after terrain generation, before vegetation systems.
##
## Manages global wind state on World using two smooth noise samplers:
##   _dir_noise  → slowly rotating wind direction (full 360°)
##   _str_noise  → fluctuating wind strength (scaled by weather condition)
##
## Condition transitions occur every 150–550 ticks with weighted probabilities.
## All state is stored directly on World so AsciiRenderSystem can read it
## without any class-loading chain issues.
##
## World fields written by this system:
##   wind_direction : Vector2   (normalised)
##   wind_strength  : float     (0.0–1.0)
##   wind_condition : int       (0=CALM, 1=BREEZY, 2=WINDY, 3=STORM)
class_name WeatherSystem
extends "res://core/SystemBase.gd"

# Weather condition enum (mirrored as ints so AsciiRenderSystem needs no import)
const CALM   := 0
const BREEZY := 1
const WINDY  := 2
const RAIN   := 3
const STORM  := 4

## Maximum wind strength per condition.
const MAX_STRENGTH: Array = [0.10, 0.40, 0.70, 0.55, 1.00]

## Human-readable names for console output.
const CONDITION_NAMES: Array = ["CALM", "BREEZY", "WINDY", "RAIN", "STORM"]

## Transition weights (must sum to 100): CALM, BREEZY, WINDY, RAIN, STORM.
## Keeps the world mostly fair/breezy; rain and storms are limited events.
const TRANSITION_WEIGHTS: Array = [15, 38, 25, 15, 7]

## Hard duration caps for rain conditions (ticks).
## At 10 TPS, 400 ticks = 40 seconds maximum continuous rain.
const MAX_RAIN_DURATION: int = 400
const MIN_RAIN_DURATION: int = 150

## Non-rain (dry) conditions duration range (ticks).
## Guarantees a minimum dry cooldown between rain emergence.
const MIN_DRY_DURATION: int = 300
const MAX_DRY_DURATION: int = 700

var _dir_noise: FastNoiseLite = null
var _str_noise: FastNoiseLite = null
var _rng: RandomNumberGenerator = null
var _condition: int = BREEZY
var _condition_timer: int = 0
var _condition_duration: int = 300

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	# --- Direction noise (very slow rotation) ---
	_dir_noise = FastNoiseLite.new()
	_dir_noise.seed        = _rng.randi()
	_dir_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dir_noise.frequency   = 0.006

	# --- Strength noise (slightly faster fluctuation) ---
	_str_noise = FastNoiseLite.new()
	_str_noise.seed        = _rng.randi()
	_str_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_str_noise.frequency   = 0.018

	_condition = BREEZY
	_condition_duration = _rng.randi_range(MIN_DRY_DURATION, MAX_DRY_DURATION)

	# Write initial state to World
	world.wind_condition  = _condition
	world.wind_strength   = 0.3
	world.rain_allowed    = false
	var start_angle: float = _rng.randf() * TAU
	world.wind_direction  = Vector2(cos(start_angle), sin(start_angle))

	print("[Weather] Starting condition: %s" % CONDITION_NAMES[_condition])

func tick(_tick_number: int) -> void:
	var t: float = float(_tick_number)

	# --- Wind direction: full 360° driven by noise ---
	var angle: float = _dir_noise.get_noise_1d(t) * TAU
	world.wind_direction = Vector2(cos(angle), sin(angle))

	# --- Wind strength: noise mapped [0,1], scaled by condition max ---
	var raw: float = (_str_noise.get_noise_1d(t) + 1.0) * 0.5
	world.wind_strength = raw * (MAX_STRENGTH[_condition] as float)

	# --- Condition timer ---
	_condition_timer += 1
	if _condition_timer >= _condition_duration:
		_condition_timer = 0
		_transition_condition()

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _transition_condition() -> void:
	var was_raining: bool = (_condition == RAIN or _condition == STORM)

	# If coming out of a rain condition, force a dry condition (CALM, BREEZY, WINDY)
	# to guarantee a recovery period where rain cannot immediately re-emerge
	if was_raining:
		var dry_roll: int = _rng.randi_range(0, 2) # CALM, BREEZY, or WINDY
		_condition = dry_roll
		_condition_duration = _rng.randi_range(MIN_DRY_DURATION, MAX_DRY_DURATION)
	else:
		var roll: int = _rng.randi_range(0, 99)
		var acc: int = 0
		for i: int in range(TRANSITION_WEIGHTS.size()):
			acc += TRANSITION_WEIGHTS[i] as int
			if roll < acc:
				_condition = i
				break

		# Strictly enforce duration cap when rain is allowed
		if _condition == RAIN or _condition == STORM:
			_condition_duration = _rng.randi_range(MIN_RAIN_DURATION, MAX_RAIN_DURATION)
		else:
			_condition_duration = _rng.randi_range(MIN_DRY_DURATION, MAX_DRY_DURATION)

	world.wind_condition = _condition
	world.rain_allowed   = (_condition == RAIN or _condition == STORM)

	print("[Weather] Condition → %s (duration=%d ticks, rain_allowed=%s)" % [
		CONDITION_NAMES[_condition],
		_condition_duration,
		str(world.rain_allowed)
	])

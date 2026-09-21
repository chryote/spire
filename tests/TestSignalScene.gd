## TestSignalScene.gd
## Automated integration test suite for the Spatial Signal System in Spire.
extends Node2D

const _TileAffordance        = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes           = preload("res://modules/signal/data/SignalTypes.gd")
const _SignalEmitterComponent = preload("res://modules/signal/components/SignalEmitterComponent.gd")
const _BurningComponent      = preload("res://modules/matter/components/BurningComponent.gd")
const _FluidComponent        = preload("res://modules/matter/components/FluidComponent.gd")
const _ContaminantComponent  = preload("res://modules/matter/components/ContaminantComponent.gd")
const _MaterialTypes         = preload("res://modules/matter/data/MaterialTypes.gd")
const _ItemFactory           = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes             = preload("res://modules/item/data/ItemTypes.gd")
const _TileTypes             = preload("res://modules/terrain/data/TileTypes.gd")

func _ready() -> void:
	print("\n=== STARTING SIGNAL SYSTEM INTEGRATION TESTS ===")
	# Wait for World to process initial setup and at least 1 tick
	await get_tree().process_frame
	await get_tree().process_frame

	var signals = World.signals
	assert(signals != null, "World.signals must be initialized and accessible!")

	_test_channel_registry(signals)
	_test_sound_impulse(signals)
	_test_fire_hazard_and_affordance(signals)
	_test_clean_water_vs_contaminated(signals)
	_test_scent_wind_advection_and_gradient(signals)
	_test_signal_intensity(signals)
	_test_custom_modular_provider(signals)
	_test_dynamic_terrain_invalidation(signals)

	print("\n>>> ALL SIGNAL SYSTEM TESTS PASSED SUCCESSFULLY! <<<\n")
	await get_tree().create_timer(10.0).timeout
	get_tree().quit(0)

# ---------------------------------------------------------------------------
# Test 1: Channel Registry & Custom Channel Registration
# ---------------------------------------------------------------------------
func _test_channel_registry(signals) -> void:
	print("[Test 1] Channel Registry & Extensibility...")
	assert(signals.has_channel(_SignalTypes.HAZARD), "Standard HAZARD channel must exist")
	assert(signals.has_channel(_SignalTypes.HYDRATION), "Standard HYDRATION channel must exist")
	assert(signals.has_channel(_SignalTypes.SOUND), "Standard SOUND channel must exist")
	assert(signals.has_channel(_SignalTypes.SCENT_PREDATOR), "Standard SCENT_PREDATOR channel must exist")

	# Register a new custom channel dynamically (modding/future systems support)
	var custom_grid = signals.register_channel(&"mana_radiation", _SignalTypes.PropagationType.DIFFUSE_DRIFT, 0.90, 0.05)
	assert(custom_grid != null, "Custom channel registration must succeed")
	assert(signals.has_channel(&"mana_radiation"), "Registered channel must be queryable")
	print("  -> PASSED: Custom channel dynamically registered.")

# ---------------------------------------------------------------------------
# Test 2: Sound Impulse & Distance Falloff
# ---------------------------------------------------------------------------
func _test_sound_impulse(signals) -> void:
	print("[Test 2] Acoustic Sound Impulse & Falloff...")
	var center = Vector2i(50, 50)
	signals.emit_sound(center, 1.0, 4)

	var sound_center: float = signals.get_signal(_SignalTypes.SOUND, center)
	var sound_near: float   = signals.get_signal(_SignalTypes.SOUND, center + Vector2i(2, 0))
	var sound_far: float    = signals.get_signal(_SignalTypes.SOUND, center + Vector2i(4, 0))
	var sound_outside: float= signals.get_signal(_SignalTypes.SOUND, center + Vector2i(6, 0))

	assert(sound_center == 1.0, "Center of impulse must be maximum volume (1.0)")
	assert(sound_near > 0.3 and sound_near < 1.0, "Near radius must show distance falloff")
	assert(sound_far >= 0.0 and sound_far < sound_near, "Outer radius must be lower than near")
	assert(sound_outside == 0.0, "Outside radius must be 0.0")
	print("  -> PASSED: Sound radial falloff behaves correctly.")

# ---------------------------------------------------------------------------
# Test 3: Combustion & Hazard Affordance Bitmask
# ---------------------------------------------------------------------------
func _test_fire_hazard_and_affordance(signals) -> void:
	print("[Test 3] Fire Hazard & Affordance Flags...")
	var test_pos = Vector2i(20, 20)
	var eid: int = World.get_entity_at(test_pos)
	assert(eid != -1, "Test tile entity must exist")

	var b = _BurningComponent.new()
	b.intensity = 0.9
	b.fuel = 1.0
	World.add_component(eid, b)

	# Run a simulation tick so SignalSystem samples the fire
	World._run_tick()

	var hazard_val: float = signals.get_signal(_SignalTypes.HAZARD, test_pos)
	assert(hazard_val >= 0.89, "Hazard signal on burning tile must reflect intensity >= 0.9")
	assert(signals.has_affordance(test_pos, _TileAffordance.HAZARD_LETHAL), "Burning tile must have HAZARD_LETHAL flag")
	assert(not signals.has_affordance(test_pos, _TileAffordance.WALKABLE), "Burning tile must NOT be WALKABLE")

	# Clean up burning component
	World.remove_component(eid, &"BurningComponent")
	print("  -> PASSED: Fire hazard and affordance bitmask mapped accurately.")

# ---------------------------------------------------------------------------
# Test 4: Fluid Hydration & Contamination
# ---------------------------------------------------------------------------
func _test_clean_water_vs_contaminated(signals) -> void:
	print("[Test 4] Fluid Hydration & Clean Water vs Contamination...")
	var water_pos = Vector2i(35, 35)
	var water_eid: int = World.get_entity_at(water_pos)

	# Add clean water
	var fl = _FluidComponent.new()
	fl.material_id = _MaterialTypes.Type.WATER
	fl.volume = 0.8
	fl.settled = true
	World.add_component(water_eid, fl)

	World._run_tick()

	var hydra_clean: float = signals.get_signal(_SignalTypes.HYDRATION, water_pos)
	assert(hydra_clean >= 0.7, "Clean water tile must have >= 0.7 hydration")
	assert(signals.has_affordance(water_pos, _TileAffordance.DRINKABLE), "Clean water tile must be DRINKABLE")
	assert(signals.has_affordance(water_pos, _TileAffordance.SWIMMABLE), "Deep water (volume 0.8 >= 0.4) must be SWIMMABLE")

	# Contaminate the water with toxic poison
	var contam = _ContaminantComponent.new()
	contam.toxicity = 0.7
	World.add_component(water_eid, contam)

	World._run_tick()

	assert(not signals.has_affordance(water_pos, _TileAffordance.DRINKABLE), "Contaminated water tile must NOT be DRINKABLE")
	assert(signals.get_signal(_SignalTypes.HAZARD, water_pos) >= 0.69, "Contaminated water must register as hazard")

	# Clean up
	World.remove_component(water_eid, &"FluidComponent")
	World.remove_component(water_eid, &"ContaminantComponent")
	print("  -> PASSED: Water hydration and contamination filtering verified.")

# ---------------------------------------------------------------------------
# Test 5: Wind Advection & Gradient Sampling
# ---------------------------------------------------------------------------
func _test_scent_wind_advection_and_gradient(signals) -> void:
	print("[Test 5] Scent Wind Advection & Spatial Gradients...")
	var scent_pos = Vector2i(64, 64)
	signals.emit_scent(_SignalTypes.SCENT_PREDATOR, scent_pos, 1.0, 1)

	var initial_val = signals.get_signal(_SignalTypes.SCENT_PREDATOR, scent_pos)
	assert(initial_val >= 0.9, "Scent puff must be present at emission point")

	# Find WeatherSystem and disable temporarily so it doesn't overwrite our test wind vector
	var weather_sys = null
	for sys in World._sim_systems:
		if sys.get_script().resource_path.ends_with("WeatherSystem.gd"):
			weather_sys = sys
			weather_sys.enabled = false
			break

	# Set wind blowing strongly EAST (+X)
	World.wind_direction = Vector2(1.0, 0.0)
	World.wind_strength  = 1.0

	# Advance 3 ticks
	for _i in range(3):
		World._run_tick()

	if weather_sys != null:
		weather_sys.enabled = true

	var east_tile = scent_pos + Vector2i(1, 0)
	var east_val  = signals.get_signal(_SignalTypes.SCENT_PREDATOR, east_tile)
	assert(east_val > 0.0, "Scent must have drifted east into adjacent tile")

	# Test gradient sampling:
	# At east_tile (65, 64), the scent is higher to the west at (64, 64).
	# So sample_gradient() must point west (-X) towards the scent peak!
	var grad = signals.get_gradient(_SignalTypes.SCENT_PREDATOR, east_tile)
	assert(grad.x < 0.0, "Gradient must point west towards the higher scent source")
	print("  -> PASSED: Scent wind advection and gradient ascent work as expected.")

# ---------------------------------------------------------------------------
# Test 6: Signal Intensity & Emission
# ---------------------------------------------------------------------------
func _test_signal_intensity(signals) -> void:
	print("[Test 6] Signal Intensity & Emission...")
	var test_pos = Vector2i(75, 75)

	# Initially, no predator scent on tile -> intensity 0.0
	var val_none = signals.get_signal(_SignalTypes.SCENT_PREDATOR, test_pos)
	assert(val_none == 0.0, "Unset signal must have 0.0 intensity")
	assert(not signals.has_signal_at(_SignalTypes.SCENT_PREDATOR, test_pos), "has_signal_at must return false for 0.0 intensity")

	# Emit faint scent -> intensity 0.25
	signals.broadcast_signal(_SignalTypes.SCENT_PREDATOR, test_pos, 0.25, 0)
	var val_faint = signals.get_signal(_SignalTypes.SCENT_PREDATOR, test_pos)
	assert(is_equal_approx(val_faint, 0.25), "Faint signal must have 0.25 intensity")
	assert(signals.has_signal_at(_SignalTypes.SCENT_PREDATOR, test_pos), "has_signal_at must return true when intensity > 0")

	# Emit full signal -> intensity 1.0
	signals.broadcast_signal(_SignalTypes.SCENT_PREDATOR, test_pos, 1.0, 0)
	var val_full = signals.get_signal(_SignalTypes.SCENT_PREDATOR, test_pos)
	assert(val_full == 1.0, "Full signal must have 1.0 intensity")

	# Test get_signals_at inspection (returns all active signals on tile)
	signals.emit_sound(test_pos, 0.8, 0)
	var all_signals: Dictionary = signals.get_signals_at(test_pos)
	assert(all_signals.has(_SignalTypes.SCENT_PREDATOR), "get_signals_at must list SCENT_PREDATOR")
	assert(all_signals.has(_SignalTypes.SOUND), "get_signals_at must list SOUND")
	assert(is_equal_approx(all_signals[_SignalTypes.SOUND], 0.8), "Sound intensity must be approx 0.8")

	# Test SignalEmitterComponent with intensity
	var emitter_eid = World.get_entity_at(test_pos)
	var emitter = _SignalEmitterComponent.new()
	emitter.channel = _SignalTypes.SCENT_SMOKE
	emitter.intensity = 0.65
	World.add_component(emitter_eid, emitter)

	World._run_tick()

	var smoke_val = signals.get_signal(_SignalTypes.SCENT_SMOKE, test_pos)
	assert(smoke_val >= 0.5, "SignalEmitterComponent must broadcast configured intensity into channel")

	# Clean up
	World.remove_component(emitter_eid, &"SignalEmitterComponent")
	print("  -> PASSED: Signal intensity and emission verified.")

# ---------------------------------------------------------------------------
# Test 7: Custom External Provider Hook
# ---------------------------------------------------------------------------
func _test_custom_modular_provider(signals) -> void:
	print("[Test 7] Pluggable External Signal Provider...")
	var test_marker = Vector2i(10, 80)
	signals.register_channel(&"arcane_energy", _SignalTypes.PropagationType.STATIC_SNAPSHOT)

	# Register custom provider callable
	signals.register_provider(func(_reg, sig_sys):
		var grid = sig_sys.get_channel(&"arcane_energy")
		if grid != null:
			grid.set_value(test_marker, 0.77)
	)

	World._run_tick()

	var custom_val = signals.get_signal(&"arcane_energy", test_marker)
	assert(is_equal_approx(custom_val, 0.77), "Custom provider must write into registered channel")
	print("  -> PASSED: Modular signal provider executed seamlessly in tick loop.")

# ---------------------------------------------------------------------------
# Test 8: Dynamic Terrain Cache Invalidation & Stale Data Prevention
# ---------------------------------------------------------------------------
func _test_dynamic_terrain_invalidation(signals) -> void:
	print("[Test 8] Dynamic Terrain Cache Invalidation...")
	var test_pos = Vector2i(25, 25)

	# 1. Dynamically transform tile into MUD (as done during rain flooding)
	signals.notify_tile_type_changed(test_pos, _TileTypes.Type.MUD)
	World._run_tick()

	var trav_mud: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav_mud, 0.6), "Traversability on MUD must be 0.6 after dynamic update")
	assert(signals.has_affordance(test_pos, _TileAffordance.HAZARD_SLOW), "MUD tile must have HAZARD_SLOW affordance")
	print("  -> PASSED: Dynamic MUD transition correctly updated traversability and affordance.")

	# 2. Dynamically transform tile into STONE (as done by geologic crystallization)
	signals.notify_tile_type_changed(test_pos, _TileTypes.Type.STONE)
	World._run_tick()

	var trav_stone: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav_stone, 0.9), "Traversability on STONE must be 0.9 after dynamic update")
	assert(not signals.has_affordance(test_pos, _TileAffordance.HAZARD_SLOW), "STONE tile must not have HAZARD_SLOW affordance")
	print("  -> PASSED: Dynamic STONE transition correctly updated traversability and affordance.")

	# 3. Restore to GRASS
	signals.notify_tile_type_changed(test_pos, _TileTypes.Type.GRASS)
	World._run_tick()

	var trav_grass: float = signals.get_signal(_SignalTypes.TRAVERSABILITY, test_pos)
	assert(is_equal_approx(trav_grass, 1.0), "Traversability on GRASS must be 1.0 after dynamic update")
	print("  -> PASSED: Zero stale data confirmed on dynamic terrain cache updates.")

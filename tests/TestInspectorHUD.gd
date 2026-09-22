## TestInspectorHUD.gd
## Automated test suite for Spire's Inspector HUD CanvasLayer.
## Validates Tabbed UI (Environment & Creature tabs), dynamic phenomena,
## toggle mechanics via [I], auto-selection, and creature thought/body/mind.
extends Node2D

const _InspectorHUDScene = preload("res://ui/InspectorHUD.tscn")
const _CreatureFactory   = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes     = preload("res://modules/creature/data/CreatureTypes.gd")
const _MaterialTypes     = preload("res://modules/matter/data/MaterialTypes.gd")
const _BurningComponent  = preload("res://modules/matter/components/BurningComponent.gd")
const _FluidComponent    = preload("res://modules/matter/components/FluidComponent.gd")
const _WorldCameraScript  = preload("res://scenes/WorldCamera.gd")

var _inspector = null
var _camera = null

func _ready() -> void:
	print("\n=== STARTING INSPECTOR HUD AUTOMATED TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_inspector = _InspectorHUDScene.instantiate()
	add_child(_inspector)
	await get_tree().process_frame

	_camera = Camera2D.new()
	_camera.set_script(_WorldCameraScript)
	_camera.name = "WorldCamera"
	add_child(_camera)

	_test_inspector_initialization()
	_test_toggle_shortcut_from_cold_start()
	_test_inspect_environment_tile()
	_test_inspect_dynamic_phenomena()
	_test_inspect_creature()
	_test_toggle_and_deselect()
	await _test_live_tick_updates()
	_test_camera_pause_and_creature_snap()

	print("\n>>> ALL INSPECTOR HUD TESTS PASSED SUCCESSFULLY! <<<\n")
	_save_test_log()
	World.paused = false
	get_tree().quit(0)

func _test_inspector_initialization() -> void:
	print("[Test 1] Inspector HUD Initialization...")
	assert(_inspector is CanvasLayer, "Inspector HUD must be a CanvasLayer")
	assert(_inspector.layer == 100, "Inspector HUD layer should be 100")
	assert(_inspector.main_panel != null, "MainPanel must exist")
	assert(not _inspector.main_panel.visible, "Inspector should start hidden until activated")
	assert(_inspector.toggle_btn != null, "ToggleBtn must exist")
	assert(_inspector.toggle_btn.visible, "ToggleBtn should be visible on screen")
	assert(_inspector.toggle_btn.text == "[I] INSPECTOR", "ToggleBtn should initially read '[I] INSPECTOR'")
	assert(_inspector.coord_label != null, "CoordLabel must exist")
	assert(_inspector.close_btn != null, "CloseBtn must exist")
	assert(_inspector.tab_container != null, "TabContainer must exist")
	assert(_inspector.tab_container.get_tab_count() == 2, "TabContainer must have 2 tabs")
	print("  -> PASSED: Inspector HUD initialized cleanly with TabContainer and onscreen toggle button.")

func _test_toggle_shortcut_from_cold_start() -> void:
	print("[Test 2] Toggle via 'I' key from cold start...")
	assert(_inspector.selected_tile == Vector2i(-1, -1), "No tile initially selected")
	# Simulate pressing 'I' when nothing was selected
	_inspector.toggle_inspector()
	assert(_inspector.main_panel.visible, "Inspector MUST open when user toggles 'I'")
	assert(_inspector.selected_tile != Vector2i(-1, -1), "Auto-selected a valid world tile")
	assert(_inspector.toggle_btn.text == "[I] CLOSE", "ToggleBtn should read '[I] CLOSE' when panel is open")
	_inspector.deselect()
	assert(not _inspector.main_panel.visible, "Deselect closes panel")
	assert(_inspector.toggle_btn.text == "[I] INSPECTOR", "ToggleBtn reverts to '[I] INSPECTOR'")
	print("  -> PASSED: Pressing 'I' reliably opens inspector and auto-selects active tile.")

func _test_inspect_environment_tile() -> void:
	print("[Test 3] Inspecting Environment Tile in Environment Tab...")
	var test_pos := Vector2i(20, 20)
	_inspector.inspect_tile(test_pos)

	assert(_inspector.main_panel.visible, "MainPanel must become visible when tile is inspected")
	assert(_inspector.selected_tile == test_pos, "selected_tile must match test_pos")
	assert(_inspector.coord_label.text == "[20, 20]", "CoordLabel must display [20, 20]")

	var env_summary: String = _inspector.env_summary_label.text
	assert(env_summary.contains("Terrain:"), "Environment summary must display Terrain")
	assert(env_summary.contains("Biome:"), "Environment summary must display Biome")
	assert(env_summary.contains("Material:"), "Environment summary must display Material")
	assert(env_summary.contains("Temp:"), "Environment summary must display Temperature")
	assert(env_summary.contains("Moisture:"), "Environment summary must display Moisture")

	assert(_inspector.no_creature_vbox.visible, "No-creature notice should be visible for empty tile in Creature tab")
	assert(not _inspector.creature_section.visible, "CreatureSection should be hidden for empty tile")
	print("  -> PASSED: Environment tab inspected with terrain, biome, and climate: %s" % env_summary.replace("\n", " | "))

func _test_inspect_dynamic_phenomena() -> void:
	print("[Test 4] Inspecting Dynamic Phenomena (Combustion & Fluid)...")
	var reg = World.get_registry()
	assert(reg != null, "ECS registry must exist")

	# 1. Fire on tile (25, 25)
	var fire_pos := Vector2i(25, 25)
	var fire_eid: int = World.get_entity_at(fire_pos)
	assert(fire_eid != -1, "Tile (25, 25) must exist")

	var burn := _BurningComponent.new()
	burn.intensity = 0.85
	burn.fuel = 0.60
	burn.heat_output = 25.0
	reg.add(fire_eid, burn)

	_inspector.inspect_tile(fire_pos)
	var act_text: String = _inspector.env_activity_label.text
	assert(act_text.contains("ACTIVE COMBUSTION"), "Activity label must report active combustion")
	assert(act_text.contains("85%"), "Activity label must display combustion intensity")

	# 2. Fluid on tile (26, 26)
	var fluid_pos := Vector2i(26, 26)
	var fluid_eid: int = World.get_entity_at(fluid_pos)
	assert(fluid_eid != -1, "Tile (26, 26) must exist")

	var fluid := _FluidComponent.new()
	fluid.volume = 0.75
	fluid.material_id = _MaterialTypes.Type.WATER
	fluid.settled = true
	reg.add(fluid_eid, fluid)

	_inspector.inspect_tile(fluid_pos)
	var fluid_text: String = _inspector.env_activity_label.text
	assert(fluid_text.contains("SURFACE FLUID"), "Activity label must report surface fluid")
	assert(fluid_text.contains("0.75m"), "Activity label must report fluid depth")

	print("  -> PASSED: Dynamic physical phenomena (combustion & surface fluid) correctly identified and displayed.")

func _test_inspect_creature() -> void:
	print("[Test 5] Inspecting Creature in Creature Tab (Identity, Thought, Body, Mind)...")
	var creature_pos := Vector2i(32, 32)
	var creature_eid: int = _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, creature_pos, "Bramble")
	assert(creature_eid != -1, "Creature creation must succeed")

	_inspector.inspect_tile(creature_pos)

	assert(_inspector.tab_container.current_tab == 1, "TabContainer should automatically switch to Creature tab when creature is clicked")
	assert(_inspector.creature_section.visible, "CreatureSection must be visible when creature is present")
	assert(not _inspector.no_creature_vbox.visible, "No-creature notice should be hidden")

	# Identity
	var header_text: String = _inspector.creature_header_label.text
	assert(header_text.contains("Grazer"), "Header must show species 'Grazer'")
	assert(header_text.contains("Bramble"), "Header must show creature name 'Bramble'")
	assert(header_text.contains("[ALIVE]"), "Header must indicate creature is alive")

	# Thought & Action
	var thought_text: String = _inspector.creature_thought_label.text
	assert(thought_text.contains("Current Action:"), "Thought label must include Current Action")
	assert(thought_text.contains("Thought:"), "Thought label must include Thought interpretation")

	# Decision utilities
	var util_text: String = _inspector.creature_utilities_label.text
	assert(util_text.contains("Decision Utilities:"), "Utilities label must report evaluated decision utilities")

	# Body Condition
	assert(_inspector.health_bar.value >= 99.0, "Initial health should be ~100%")
	assert(_inspector.stamina_bar.value >= 99.0, "Initial stamina should be ~100%")

	var body_text: String = _inspector.creature_body_label.text
	assert(body_text.contains("Nutrition:"), "Body label must show nutrition status")
	assert(body_text.contains("Blood:"), "Body label must show blood volume")
	assert(body_text.contains("Core Temp:"), "Body label must show core temperature")

	var anatomy_text: String = _inspector.creature_anatomy_label.text
	assert(anatomy_text.contains("Limbs:"), "Anatomy label must show limbs")
	assert(anatomy_text.contains("Vitals:"), "Anatomy label must show vitals")

	# Mind Condition
	var mood_text: String = _inspector.creature_mood_label.text
	assert(mood_text.contains("Mood:"), "Mood label must display mood summary")

	var drives_text: String = _inspector.creature_drives_label.text
	assert(drives_text.contains("Hunger:"), "Drives label must report Hunger")
	assert(drives_text.contains("Thirst:"), "Drives label must report Thirst")
	assert(drives_text.contains("Fear:"), "Drives label must report Fear")
	assert(drives_text.contains("Curiosity:"), "Drives label must report Curiosity")

	print("  -> PASSED: Creature tab displays identity, thought, body vitals, and mind drives accurately.")

func _test_toggle_and_deselect() -> void:
	print("[Test 6] Toggle and Deselect Mechanics...")
	_inspector.deselect()
	assert(not _inspector.main_panel.visible, "Inspector should hide upon deselect")
	assert(_inspector.selected_tile == Vector2i(-1, -1), "selected_tile must be cleared")

	_inspector.inspect_tile(Vector2i(32, 32))
	assert(_inspector.main_panel.visible, "Inspector should re-open when inspecting tile")
	print("  -> PASSED: Deselection and re-inspection toggle panel visibility accurately.")

func _test_live_tick_updates() -> void:
	print("[Test 7] Live Simulation Tick Updates...")
	var reg = World.get_registry()
	# Step simulation 3 ticks
	for i in range(3):
		World._run_tick()
		await get_tree().process_frame

	_inspector.update_inspector()

	assert(_inspector.main_panel.visible, "Inspector remains active during live simulation")
	print("  -> PASSED: Inspector updates live across simulation ticks without errors.")

func _test_camera_pause_and_creature_snap() -> void:
	print("[Test 8] Camera Movement Auto-Pause and Creature Snapping...")
	assert(_camera != null, "WorldCamera must exist in test tree")
	assert(_camera.has_method("snap_to"), "WorldCamera must have snap_to method")

	# 1. Test Camera snap_to
	var test_snap_pos := Vector2(720.0, 540.0)
	_camera.snap_to(test_snap_pos)
	assert(_camera.position == test_snap_pos, "snap_to should immediately set camera position")
	assert(_camera._target_position == test_snap_pos, "snap_to should immediately set _target_position")
	assert(not _camera.is_moving, "snap_to should not leave camera in moving state")

	# 2. Test Camera Movement Auto-Pause when simulation is running
	World.paused = false
	assert(not World.paused, "Simulation should be unpaused")

	# Start moving camera by shifting target position
	_camera._target_position = test_snap_pos + Vector2(200.0, 0.0)
	_camera._process(0.016)
	assert(_camera.is_moving, "Camera should detect active movement/interpolation")
	assert(World.paused, "Simulation MUST automatically pause while camera is moving")

	# Complete camera movement by processing sufficient time for exponential lerp to settle
	for i in range(30):
		_camera._process(0.05)
	assert(not _camera.is_moving, "Camera should settle and stop moving")
	assert(not World.paused, "Simulation MUST automatically resume after camera stops moving")

	# 3. Test that manual pause is preserved across camera movement
	World.paused = true
	_camera._target_position = test_snap_pos + Vector2(400.0, 0.0)
	_camera._process(0.016)
	assert(_camera.is_moving, "Camera is moving")
	assert(World.paused, "Simulation remains paused")

	# Settle camera
	for i in range(30):
		_camera._process(0.05)
	assert(not _camera.is_moving, "Camera settled")
	assert(World.paused, "Simulation MUST remain paused if it was already paused before camera moved")

	# 4. Test Inspector HUD find_and_select_nearest_creature snaps camera
	var creature_tile := Vector2i(42, 42)
	var ceid := _CreatureFactory.create(World, _CreatureTypes.Type.GRAZER, creature_tile, "Tracker")
	assert(ceid != -1, "Creature creation succeeded")

	# Deselect any prior tile and position camera near (42, 42)
	_inspector.deselect()
	var offset_cam_pos := Vector2(45.0 * 18.0, 45.0 * 18.0)
	_camera.snap_to(offset_cam_pos)
	assert(_camera.position == offset_cam_pos, "Camera positioned near test creature")

	# Click find creature
	_inspector.find_and_select_nearest_creature()

	var expected_world_pos := Vector2(creature_tile.x * 18.0 + 9.0, creature_tile.y * 18.0 + 9.0)
	assert(_inspector.selected_tile == creature_tile, "Inspector should select nearest creature tile")
	assert(_inspector.tab_container.current_tab == 1, "Should switch to Creature tab")
	assert(_camera.position == expected_world_pos, "Camera MUST snap directly to creature world coordinates")

	# 5. Test SnapCreatureBtn in CreatureSection
	_camera.snap_to(Vector2(50.0, 50.0))
	assert(_camera.position == Vector2(50.0, 50.0), "Camera moved away")
	_inspector._on_snap_creature_pressed()
	assert(_camera.position == expected_world_pos, "Snap button in CreatureSection MUST re-snap camera to creature")

	print("  -> PASSED: Camera movement auto-pauses simulation and Inspector HUD snaps camera to creatures.")

func _save_test_log() -> void:
	var file = FileAccess.open("res://logs/test_inspector_hud.log", FileAccess.WRITE)
	if file != null:
		file.store_string("PASSED: Tabbed Inspector HUD fully verified.\n")
		file.store_string("Environment summary: %s\n" % _inspector.env_summary_label.text)
		file.store_string("Creature header:     %s\n" % _inspector.creature_header_label.text)
		file.store_string("Creature thought:    %s\n" % _inspector.creature_thought_label.text)
		file.store_string("Creature body:       %s\n" % _inspector.creature_body_label.text)
		file.store_string("Creature drives:     %s\n" % _inspector.creature_drives_label.text)
		file.close()

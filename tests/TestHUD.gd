## TestHUD.gd
## Automated test suite for Spire's HUD monitor CanvasLayer.
## Validates HUD initialization, toggleability, live item count updates,
## and per-system latency tree population.
extends Node2D

const _ItemTypes   = preload("res://modules/item/data/ItemTypes.gd")
const _MaterialTypes = preload("res://modules/matter/data/MaterialTypes.gd")
const _ItemFactory = preload("res://modules/item/systems/ItemFactory.gd")
const _HUDScene    = preload("res://ui/HUD.tscn")

var _hud = null

func _ready() -> void:
	print("\n=== STARTING HUD MONITOR AUTOMATED TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_hud = _HUDScene.instantiate()
	add_child(_hud)
	await get_tree().process_frame

	_test_hud_initialization()
	_test_hud_toggle()
	_test_live_item_metrics_update()
	_test_live_vegetation_metrics_update()
	await _test_live_system_timings_update()

	print("\n>>> ALL HUD MONITOR TESTS PASSED SUCCESSFULLY! <<<\n")
	_save_test_log()
	World.paused = false
	get_tree().quit(0)

func _test_hud_initialization() -> void:
	print("[Test 1] HUD Initialization...")
	assert(_hud is CanvasLayer, "HUD must be a CanvasLayer")
	assert(_hud.layer == 100, "HUD layer should be 100 for top-level overlay")
	assert(_hud.main_panel != null, "MainPanel must exist")
	assert(_hud.main_panel.visible, "HUD should start visible")
	assert(_hud.toggle_btn != null, "ToggleBtn must exist")
	assert(_hud.toggle_btn.text == "[F3] HIDE", "ToggleBtn should initially read '[F3] HIDE'")
	print("  -> PASSED: HUD initialized with correct CanvasLayer layout.")

func _test_hud_toggle() -> void:
	print("[Test 2] HUD Toggleability...")
	_hud.toggle_hud()
	assert(not _hud.main_panel.visible, "HUD main_panel should become hidden after toggle")
	assert(_hud.toggle_btn.text == "[F3] STATS", "ToggleBtn should read '[F3] STATS' when hidden")

	_hud.toggle_hud()
	assert(_hud.main_panel.visible, "HUD main_panel should become visible after second toggle")
	assert(_hud.toggle_btn.text == "[F3] HIDE", "ToggleBtn should read '[F3] HIDE' when visible")
	print("  -> PASSED: HUD toggles visibility and button state cleanly.")

func _test_live_item_metrics_update() -> void:
	print("[Test 3] Live Item Metrics Update...")
	var test_eid: int = World.get_entity_at(Vector2i(15, 15))
	assert(test_eid != -1, "Test tile must exist")

	# Deposit 50 grass items
	_ItemFactory.create_and_deposit(World, _ItemTypes.Type.GRASS, _MaterialTypes.Type.ORGANIC, test_eid, 50)
	_hud.update_hud()

	var summary_text: String = _hud.items_summary_label.text
	assert(summary_text.contains("Total Item Stacks:"), "Summary label must display stack counts")
	assert(summary_text.contains("Total Units (Quantity):"), "Summary label must display unit counts")

	var breakdown_text: String = _hud.items_breakdown_label.text
	assert(breakdown_text.contains("Grass:"), "Breakdown label must list 'Grass' archetype")
	print("  -> PASSED: Item counts and archetype breakdown reflect live world state: %s" % summary_text)

func _test_live_vegetation_metrics_update() -> void:
	print("[Test 4] Live Vegetation Metrics Update...")
	_hud.update_hud(0.0, true)

	assert(_hud.veg_summary_label != null, "veg_summary_label must exist")
	assert(_hud.veg_breakdown_label != null, "veg_breakdown_label must exist")

	var veg_summary: String = _hud.veg_summary_label.text
	assert(veg_summary.contains("Vegetated:"), "Summary must report vegetated tile count")
	assert(veg_summary.contains("Yield Plants:"), "Summary must report yield plant count")
	assert(veg_summary.contains("Growth:"), "Summary must report growth modifier")

	var veg_breakdown: String = _hud.veg_breakdown_label.text
	assert(veg_breakdown.contains("Species:"), "Breakdown must display species distribution")
	assert(veg_breakdown.contains("Stages:"), "Breakdown must display growth stages")

	print("  -> PASSED: Vegetation metrics accurately reflect map flora: %s" % veg_summary)

func _test_live_system_timings_update() -> void:
	print("[Test 5] Live System Timings Tree...")
	# Run 5 simulation ticks to generate profiling data
	for i in range(5):
		World._run_tick()
		await get_tree().process_frame

	_hud.update_hud()
	var root: TreeItem = _hud.systems_tree.get_root()
	assert(root != null, "Systems tree must have a root item")

	var first_child: TreeItem = root.get_first_child()
	assert(first_child != null, "Systems tree must have children for active simulation systems")

	var sys_count: int = 0
	var curr: TreeItem = first_child
	while curr != null:
		sys_count += 1
		var sys_name: String = curr.get_text(0)
		var last_ms: String  = curr.get_text(1)
		var avg_ms: String   = curr.get_text(2)
		assert(last_ms.ends_with("ms"), "Column 1 must be formatted in ms, got: %s" % last_ms)
		assert(avg_ms.ends_with("ms"), "Column 2 must be formatted in ms, got: %s" % avg_ms)
		curr = curr.get_next()

	assert(sys_count >= 5, "At least 5 simulation systems should be listed in the tree, got: %d" % sys_count)
	print("  -> PASSED: %d simulation systems rendered with live millisecond metrics." % sys_count)

func _save_test_log() -> void:
	var file = FileAccess.open("res://logs/test_hud.log", FileAccess.WRITE)
	if file != null:
		file.store_string("PASSED: HUD Monitor CanvasLayer initialized, toggled, and verified with live item counts, vegetation metrics, and system latencies in ms.\n")
		if _hud != null:
			file.store_string("Item Summary: %s\n" % _hud.items_summary_label.text)
			file.store_string("Veg Summary:  %s\n" % _hud.veg_summary_label.text)
			file.store_string("Veg Breakdown:\n%s\n" % _hud.veg_breakdown_label.text)
		file.close()

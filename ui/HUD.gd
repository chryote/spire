## HUD.gd
## Real-time simulation monitor and performance diagnostic HUD for Spire.
## Displays live item counts (stacks & units) and per-system latencies in milliseconds.
## Toggleable via F3, Backquote (~), or on-screen button.
extends CanvasLayer

const _ItemFactory = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes   = preload("res://modules/item/data/ItemTypes.gd")
const _VegetationTypes = preload("res://modules/vegetation/data/VegetationTypes.gd")

@onready var main_panel: Control = $MainPanel
@onready var toggle_btn: Button = $ToggleBtn
@onready var fps_label: Label = $MainPanel/Margin/VBox/Header/FPSLabel
@onready var status_label: Label = $MainPanel/Margin/VBox/Header/StatusLabel
@onready var tick_bar: ProgressBar = $MainPanel/Margin/VBox/TickSection/TickBar
@onready var tick_label: Label = $MainPanel/Margin/VBox/TickSection/TickLabel
@onready var items_summary_label: Label = $MainPanel/Margin/VBox/ItemSection/ItemsSummaryLabel
@onready var items_breakdown_label: RichTextLabel = $MainPanel/Margin/VBox/ItemSection/ItemsBreakdownLabel
@onready var veg_summary_label: Label = $MainPanel/Margin/VBox/VegSection/VegSummaryLabel
@onready var veg_breakdown_label: RichTextLabel = $MainPanel/Margin/VBox/VegSection/VegBreakdownLabel
@onready var systems_tree: Tree = $MainPanel/Margin/VBox/SystemSection/SystemsTree

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1  # Update UI text 10 times per second

var _veg_timer: float = 0.0
const VEG_UPDATE_INTERVAL: float = 0.5  # Scan detailed vegetation distribution every 0.5s
var _cached_veg_breakdown_bbcode: String = ""

const SPECIES_NAMES: Dictionary = {
	_VegetationTypes.Type.GRASS_PATCH: "Grass",
	_VegetationTypes.Type.TALL_GRASS: "Tall Grass",
	_VegetationTypes.Type.SHRUB: "Shrub",
	_VegetationTypes.Type.WILDFLOWER: "Wildflower",
	_VegetationTypes.Type.PINE_TREE: "Pine",
	_VegetationTypes.Type.OAK_TREE: "Oak",
}

const STAGE_NAMES: Array[String] = [
	"Seedling",
	"Young",
	"Established",
	"Mature",
]

func _ready() -> void:
	layer = 100
	if toggle_btn != null:
		toggle_btn.pressed.connect(toggle_hud)

	_setup_systems_tree()

	# Ensure profiling is active when HUD is displayed
	if World != null:
		World.profiling_enabled = true

	update_hud(0.0, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F3 or key_event.keycode == KEY_QUOTELEFT or key_event.keycode == KEY_ASCIITILDE:
			toggle_hud()
			get_viewport().set_input_as_handled()

func toggle_hud() -> void:
	main_panel.visible = not main_panel.visible
	if main_panel.visible and World != null:
		World.profiling_enabled = true
		update_hud(0.0, true)
	if toggle_btn != null:
		toggle_btn.text = "[F3] HIDE" if main_panel.visible else "[F3] STATS"

func _process(delta: float) -> void:
	if not main_panel.visible:
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		var elapsed: float = _update_timer
		_update_timer = 0.0
		update_hud(elapsed)

func _setup_systems_tree() -> void:
	if systems_tree == null:
		return
	systems_tree.columns = 5
	systems_tree.set_column_title(0, "System Name")
	systems_tree.set_column_title(1, "Last")
	systems_tree.set_column_title(2, "Avg")
	systems_tree.set_column_title(3, "Max")
	systems_tree.set_column_title(4, "% Tick")
	systems_tree.column_titles_visible = true
	systems_tree.set_column_expand(0, true)
	systems_tree.set_column_custom_minimum_width(0, 150)
	systems_tree.set_column_custom_minimum_width(1, 65)
	systems_tree.set_column_custom_minimum_width(2, 65)
	systems_tree.set_column_custom_minimum_width(3, 65)
	systems_tree.set_column_custom_minimum_width(4, 55)
	systems_tree.hide_root = true

func update_hud(delta: float = 0.1, force_veg: bool = false) -> void:
	if World == null:
		return

	# --- 1. Frame & Simulation Header ---
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(1.0, fps)
	if fps_label != null:
		fps_label.text = "FPS: %.0f (%.1f ms)" % [fps, frame_ms]

	var state_str: String = "PAUSED" if World.paused else "RUNNING (%.0f TPS)" % World.ticks_per_second
	if status_label != null:
		status_label.text = "Tick: %d | %s" % [World.tick_count, state_str]

	# --- 2. Simulation Tick Budget ---
	var sys_perf: Dictionary = World.get_system_performance_data()
	var total_tick_ms: float = float(sys_perf.get("total_tick_usec", 0)) / maxf(1.0, float(World.tick_count)) / 1000.0
	var recent_ticks: Array = sys_perf.get("recent_ticks", [])
	var last_tick_ms: float = (float(recent_ticks.back()) / 1000.0) if not recent_ticks.is_empty() else 0.0
	var max_tick_ms: float  = float(sys_perf.get("max_tick_usec", 0)) / 1000.0
	var budget_pct: float   = (last_tick_ms / 100.0) * 100.0  # 100ms target budget

	if tick_bar != null:
		tick_bar.value = clampf(budget_pct, 0.0, 100.0)
	if tick_label != null:
		tick_label.text = "Tick: %.2f ms (Avg: %.2f ms | Max: %.1f ms) - %.1f%% of 100ms budget" % [
			last_tick_ms, total_tick_ms, max_tick_ms, budget_pct
		]

	# --- 3. Item Module Metrics ---
	var reg = World.get_registry()
	var total_stacks: int = 0
	if reg != null:
		total_stacks = reg.get_store(&"ItemComponent").size()
	var total_units: int = _ItemFactory.get_total_quantity()

	if items_summary_label != null:
		items_summary_label.text = "Total Item Stacks: %s  |  Total Units (Quantity): %s" % [
			_format_number(total_stacks), _format_number(total_units)
		]

	if items_breakdown_label != null:
		var counts: Dictionary = _ItemFactory.get_all_global_counts()
		var breakdown_parts: Array[String] = []
		for item_type: int in counts:
			var qty: int = counts[item_type]
			if qty > 0:
				var mold = _ItemTypes.get_data(item_type)
				var base_name: String = mold.get("base_name", "Item_%d" % item_type)
				breakdown_parts.append("[b]%s:[/b] %s" % [base_name, _format_number(qty)])
		if breakdown_parts.is_empty():
			items_breakdown_label.text = "[color=#778899]No items active in world.[/color]"
		else:
			items_breakdown_label.text = "  •  ".join(breakdown_parts)

	# --- 4. Vegetation Module Metrics ---
	_update_vegetation_metrics(reg, delta, force_veg)

	# --- 5. Live Per-System Timings ---
	_update_systems_list(sys_perf)

func _update_vegetation_metrics(reg, delta: float, force: bool = false) -> void:
	if reg == null:
		return

	var veg_store: Dictionary = reg.get_store(&"VegetationComponent")
	var total_veg: int = veg_store.size()
	var yield_store: Dictionary = reg.get_store(&"ItemYieldComponent")
	var total_yield: int = yield_store.size()
	var total_tiles: int = World.MAP_WIDTH * World.MAP_HEIGHT
	var coverage_pct: float = (float(total_veg) / maxf(1.0, float(total_tiles))) * 100.0
	var growth_pct: float = World.growth_rate_mod * 100.0

	if veg_summary_label != null:
		veg_summary_label.text = "Vegetated: %s / %s (%.1f%%)  |  Yield Plants: %s  |  Growth: %.0f%%" % [
			_format_number(total_veg), _format_number(total_tiles), coverage_pct, _format_number(total_yield), growth_pct
		]

	_veg_timer += delta
	if not force and _veg_timer < VEG_UPDATE_INTERVAL and not _cached_veg_breakdown_bbcode.is_empty():
		if veg_breakdown_label != null:
			veg_breakdown_label.text = _cached_veg_breakdown_bbcode
		return

	_veg_timer = 0.0

	if total_veg == 0:
		_cached_veg_breakdown_bbcode = "[color=#778899]No vegetation active in world.[/color]"
		if veg_breakdown_label != null:
			veg_breakdown_label.text = _cached_veg_breakdown_bbcode
		return

	# Tally species and stages
	var species_counts: Dictionary = {
		_VegetationTypes.Type.GRASS_PATCH: 0,
		_VegetationTypes.Type.TALL_GRASS: 0,
		_VegetationTypes.Type.SHRUB: 0,
		_VegetationTypes.Type.WILDFLOWER: 0,
		_VegetationTypes.Type.PINE_TREE: 0,
		_VegetationTypes.Type.OAK_TREE: 0,
	}
	var stage_counts: Array[int] = [0, 0, 0, 0]

	for entity_id in veg_store:
		var veg: VegetationComponent = veg_store[entity_id]
		if veg != null:
			species_counts[veg.veg_type] = species_counts.get(veg.veg_type, 0) + 1
			var st: int = clampi(veg.growth_stage, 0, 3)
			stage_counts[st] += 1

	var spec_parts: Array[String] = []
	for stype in [_VegetationTypes.Type.GRASS_PATCH, _VegetationTypes.Type.TALL_GRASS, _VegetationTypes.Type.SHRUB, _VegetationTypes.Type.WILDFLOWER, _VegetationTypes.Type.PINE_TREE, _VegetationTypes.Type.OAK_TREE]:
		var cnt: int = species_counts.get(stype, 0)
		if cnt > 0:
			spec_parts.append("%s: %s" % [SPECIES_NAMES.get(stype, "Plant"), _format_number(cnt)])

	var stage_parts: Array[String] = []
	for i in range(stage_counts.size()):
		var cnt: int = stage_counts[i]
		if cnt > 0:
			stage_parts.append("%s: %s" % [STAGE_NAMES[i], _format_number(cnt)])

	var line1: String = "[b]Species:[/b] " + (" • ".join(spec_parts) if not spec_parts.is_empty() else "None")
	var line2: String = "[b]Stages:[/b] " + (" • ".join(stage_parts) if not stage_parts.is_empty() else "None")
	_cached_veg_breakdown_bbcode = line1 + "\n" + line2

	if veg_breakdown_label != null:
		veg_breakdown_label.text = _cached_veg_breakdown_bbcode

func _update_systems_list(sys_perf: Dictionary) -> void:
	if systems_tree == null:
		return

	systems_tree.clear()
	var root: TreeItem = systems_tree.create_item()

	var systems_data: Dictionary = sys_perf.get("systems", {})
	if systems_data.is_empty():
		var empty_item: TreeItem = systems_tree.create_item(root)
		empty_item.set_text(0, "Collecting system metrics...")
		return

	# Sort systems by last execution time descending
	var sorted_names: Array = systems_data.keys()
	sorted_names.sort_custom(func(a, b) -> bool:
		var usec_a: int = systems_data[a].get("last_usec", 0)
		var usec_b: int = systems_data[b].get("last_usec", 0)
		return usec_a > usec_b
	)

	for sys_name: String in sorted_names:
		var s: Dictionary = systems_data[sys_name]
		var calls: int = max(1, s.get("calls", 1))
		var last_ms: float = float(s.get("last_usec", 0)) / 1000.0
		var avg_ms: float  = (float(s.get("total_usec", 0)) / float(calls)) / 1000.0
		var max_ms: float  = float(s.get("max_usec", 0)) / 1000.0
		var pct_budget: float = (avg_ms / 100.0) * 100.0

		var item: TreeItem = systems_tree.create_item(root)
		item.set_text(0, sys_name)
		item.set_text(1, "%.2f ms" % last_ms)
		item.set_text(2, "%.2f ms" % avg_ms)
		item.set_text(3, "%.2f ms" % max_ms)
		item.set_text(4, "%.1f%%" % pct_budget)

		# Color coding by performance health
		var color: Color = Color(0.4, 0.9, 0.5) # Green (< 2ms)
		if avg_ms >= 10.0 or last_ms >= 15.0:
			color = Color(1.0, 0.35, 0.35)     # Red (> 10ms)
		elif avg_ms >= 2.0 or last_ms >= 5.0:
			color = Color(1.0, 0.85, 0.3)      # Yellow (2-10ms)

		item.set_custom_color(0, color)
		item.set_custom_color(1, color)
		item.set_custom_color(2, color)
		item.set_custom_color(3, color)
		item.set_custom_color(4, color)

func _format_number(n: int) -> String:
	var s: String = str(n)
	var result: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i > 0:
			result = "," + result
	return result

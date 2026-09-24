## InspectorHUD.gd
## Real-time Tile and Entity Inspector HUD for Spire.
## Features Tabbed UI:
##   - Tab 1: Environment (Terrain, climate, active phenomena, flora, items, signals)
##   - Tab 2: Creature (Identity, thoughts, utilities, body condition, mind drives)
## Toggleable via [I] key, [Esc], on-screen [I] INSPECT button, or tile left-click.
extends CanvasLayer

const _TileTypes           = preload("res://modules/terrain/data/TileTypes.gd")
const _BiomeTypes          = preload("res://modules/terrain/data/BiomeTypes.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")
const _VegetationTypes     = preload("res://modules/vegetation/data/VegetationTypes.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _GrowthComponent     = preload("res://modules/creature/components/GrowthComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _TileComponent       = preload("res://modules/terrain/components/TileComponent.gd")
const _BiomeComponent      = preload("res://modules/terrain/components/BiomeComponent.gd")
const _MatterComponent     = preload("res://modules/matter/components/MatterComponent.gd")
const _BurningComponent    = preload("res://modules/matter/components/BurningComponent.gd")
const _FluidComponent      = preload("res://modules/matter/components/FluidComponent.gd")
const _FrozenComponent     = preload("res://modules/matter/components/FrozenComponent.gd")
const _RainComponent       = preload("res://modules/weather/components/RainComponent.gd")
const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")

signal tile_selected(tile_pos: Vector2i)
signal tile_deselected()

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var main_panel: Control = $MainPanel
@onready var toggle_btn: Button = $ToggleBtn
@onready var header_title: Label = $MainPanel/Margin/VBox/Header/TitleLabel
@onready var coord_label: Label = $MainPanel/Margin/VBox/Header/CoordLabel
@onready var close_btn: Button = $MainPanel/Margin/VBox/Header/CloseBtn
@onready var tab_container: TabContainer = $MainPanel/Margin/VBox/TabContainer

# Environment tab controls
@onready var env_summary_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Environment/Margin/VBox/EnvSection/EnvSummaryLabel
@onready var env_activity_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Environment/Margin/VBox/EnvSection/EnvActivityLabel
@onready var env_veg_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Environment/Margin/VBox/EnvSection/EnvVegLabel
@onready var env_items_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Environment/Margin/VBox/EnvSection/EnvItemsLabel
@onready var env_affordance_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Environment/Margin/VBox/EnvSection/EnvAffordanceLabel

# Creature tab controls
@onready var creature_section: Control = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection
@onready var no_creature_vbox: Control = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/NoCreatureVBox
@onready var find_creature_btn: Button = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/NoCreatureVBox/FindCreatureBtn
@onready var snap_creature_btn: Button = get_node_or_null("MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/SnapCreatureBtn")

@onready var creature_header_label: Label = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/CreatureHeaderLabel
@onready var creature_thought_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/CreatureThoughtLabel
@onready var creature_utilities_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/CreatureUtilitiesLabel
@onready var health_bar: ProgressBar = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/BodyVBox/HealthRow/HealthBar
@onready var health_val_label: Label = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/BodyVBox/HealthRow/HealthVal
@onready var stamina_bar: ProgressBar = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/BodyVBox/StaminaRow/StaminaBar
@onready var stamina_val_label: Label = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/BodyVBox/StaminaRow/StaminaVal
@onready var creature_body_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/BodyVBox/BodyDetailsLabel
@onready var creature_anatomy_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/BodyVBox/AnatomyLabel
@onready var creature_mood_label: Label = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/MindVBox/MoodLabel
@onready var creature_drives_label: RichTextLabel = $MainPanel/Margin/VBox/TabContainer/Creature/Margin/VBox/CreatureSection/MindVBox/DrivesLabel

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var selected_tile: Vector2i = Vector2i(-1, -1)
var selected_creature_eid: int = -1
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1

var creature_traits_label: RichTextLabel = null

var _selection_box: Node2D = null

# ---------------------------------------------------------------------------
# In-world Selection Box Drawer
# ---------------------------------------------------------------------------
class SelectionBoxDrawer extends Node2D:
	var tile_coords: Vector2i = Vector2i(-1, -1)
	var pulse_time: float = 0.0

	func _process(delta: float) -> void:
		if visible:
			pulse_time += delta * 4.0
			queue_redraw()

	func _draw() -> void:
		if tile_coords.x < 0 or tile_coords.y < 0:
			return
		var alpha: float = 0.65 + 0.30 * sin(pulse_time)
		var stroke_col := Color(0.3, 0.85, 1.0, alpha)
		var fill_col   := Color(0.2, 0.75, 1.0, 0.15)
		var rect       := Rect2(Vector2.ZERO, Vector2(18.0, 18.0))

		draw_rect(rect, fill_col, true)
		draw_rect(rect, stroke_col, false, 1.5)

		# Corner tick accents
		var tick_len: float = 4.0
		var c_col := Color(1.0, 1.0, 1.0, alpha)
		draw_line(Vector2(0, 0), Vector2(tick_len, 0), c_col, 2.0)
		draw_line(Vector2(0, 0), Vector2(0, tick_len), c_col, 2.0)
		draw_line(Vector2(18, 0), Vector2(18 - tick_len, 0), c_col, 2.0)
		draw_line(Vector2(18, 0), Vector2(18, tick_len), c_col, 2.0)
		draw_line(Vector2(0, 18), Vector2(tick_len, 18), c_col, 2.0)
		draw_line(Vector2(0, 18), Vector2(0, 18 - tick_len), c_col, 2.0)
		draw_line(Vector2(18, 18), Vector2(18 - tick_len, 18), c_col, 2.0)
		draw_line(Vector2(18, 18), Vector2(18, 18 - tick_len), c_col, 2.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	layer = 100
	if close_btn != null:
		close_btn.pressed.connect(deselect)
	if toggle_btn != null:
		toggle_btn.pressed.connect(toggle_inspector)
	if find_creature_btn != null:
		find_creature_btn.pressed.connect(find_and_select_nearest_creature)
	if snap_creature_btn != null:
		snap_creature_btn.pressed.connect(_on_snap_creature_pressed)

	_setup_selection_box()

	# Start closed until user clicks a tile or presses 'I'
	if main_panel != null:
		main_panel.visible = false
	_update_toggle_btn()

func _setup_selection_box() -> void:
	var world_scene = get_parent()
	if world_scene is Node2D:
		_selection_box = SelectionBoxDrawer.new()
		_selection_box.name = "InspectorSelectionBox"
		_selection_box.visible = false
		world_scene.add_child.call_deferred(_selection_box)

func _exit_tree() -> void:
	if _selection_box != null and is_instance_valid(_selection_box):
		_selection_box.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	# Toggle via 'I' key
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_I:
			toggle_inspector()
			get_viewport().set_input_as_handled()
			return
		elif ke.keycode == KEY_ESCAPE:
			if main_panel.visible:
				deselect()
				get_viewport().set_input_as_handled()
				return

	# Left-click to inspect tile
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
			# Prevent click-through when clicking inspector panel or toggle button
			if main_panel.visible and main_panel.get_global_rect().has_point(mbe.position):
				return
			if toggle_btn != null and toggle_btn.visible and toggle_btn.get_global_rect().has_point(mbe.position):
				return

			var world_pos := _screen_to_world(mbe.position)
			var tile_pos := Vector2i(floori(world_pos.x / 18.0), floori(world_pos.y / 18.0))

			if World != null and World.is_valid_position(tile_pos):
				inspect_tile(tile_pos)
				get_viewport().set_input_as_handled()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		return cam.get_global_mouse_position()
	if get_parent() is Node2D:
		return (get_parent() as Node2D).get_global_mouse_position()
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _process(delta: float) -> void:
	if not main_panel.visible or selected_tile == Vector2i(-1, -1):
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		update_inspector()

# ---------------------------------------------------------------------------
# Toggle & Navigation API
# ---------------------------------------------------------------------------

func toggle_inspector() -> void:
	if main_panel.visible:
		deselect()
	else:
		if selected_tile == Vector2i(-1, -1):
			# Auto-select the starter creature or center of map
			var target_pos := _find_any_creature_pos()
			inspect_tile(target_pos)
		else:
			main_panel.visible = true
			if _selection_box != null:
				_selection_box.visible = true
			update_inspector()
	_update_toggle_btn()

func _update_toggle_btn() -> void:
	if toggle_btn != null:
		toggle_btn.text = "[I] CLOSE" if main_panel.visible else "[I] INSPECTOR"

func _get_camera() -> Camera2D:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		return cam
	var world_scene = get_parent()
	if world_scene != null:
		return world_scene.get_node_or_null("WorldCamera") as Camera2D
	return null

func snap_camera_to_tile(tile_pos: Vector2i) -> void:
	var cam := _get_camera()
	if cam != null:
		var world_pos := Vector2(tile_pos.x * 18.0 + 9.0, tile_pos.y * 18.0 + 9.0)
		if cam.has_method("snap_to"):
			cam.snap_to(world_pos)
		else:
			cam.position = world_pos
			if "_target_position" in cam:
				cam._target_position = world_pos

func _find_any_creature_pos() -> Vector2i:
	return _find_nearest_creature_pos(Vector2i(64, 64))

func _find_nearest_creature_pos(ref_pos: Vector2i) -> Vector2i:
	if World != null:
		var reg = World.get_registry()
		if reg != null:
			var pos_store: Dictionary = reg.get_store(&"PositionComponent")
			if not pos_store.is_empty():
				var best_pos := Vector2i(-1, -1)
				var min_dist_sq: float = INF
				for ceid: int in pos_store:
					var cpos: Vector2i = pos_store[ceid].position
					var d_sq: float = float((cpos.x - ref_pos.x) * (cpos.x - ref_pos.x) + (cpos.y - ref_pos.y) * (cpos.y - ref_pos.y))
					if d_sq < min_dist_sq:
						min_dist_sq = d_sq
						best_pos = cpos
				if best_pos != Vector2i(-1, -1):
					return best_pos
	return Vector2i(64, 80)

func find_and_select_nearest_creature() -> void:
	var cam := _get_camera()
	var ref_pos := selected_tile
	if ref_pos == Vector2i(-1, -1) and cam != null:
		ref_pos = Vector2i(floori(cam.position.x / 18.0), floori(cam.position.y / 18.0))
	elif ref_pos == Vector2i(-1, -1):
		ref_pos = Vector2i(64, 64)

	var target_pos := _find_nearest_creature_pos(ref_pos)
	inspect_tile(target_pos)
	if tab_container != null:
		tab_container.current_tab = 1
	snap_camera_to_tile(target_pos)

func _on_snap_creature_pressed() -> void:
	if selected_creature_eid != -1 and World != null:
		var reg = World.get_registry()
		if reg != null:
			var pos_comp = reg.get_component(selected_creature_eid, &"PositionComponent")
			if pos_comp != null:
				snap_camera_to_tile(pos_comp.position)
				inspect_tile(pos_comp.position, selected_creature_eid)
				return
	if selected_tile != Vector2i(-1, -1):
		snap_camera_to_tile(selected_tile)

# ---------------------------------------------------------------------------
# Inspection & Selection API
# ---------------------------------------------------------------------------

func inspect_tile(tile_pos: Vector2i, forced_creature_eid: int = -1) -> void:
	selected_tile = tile_pos

	if forced_creature_eid != -1:
		selected_creature_eid = forced_creature_eid
	else:
		selected_creature_eid = World.get_creature_at(tile_pos) if World != null else -1

	# Update visual selection indicator
	if _selection_box != null:
		_selection_box.tile_coords = tile_pos
		_selection_box.position = Vector2(tile_pos.x * 18, tile_pos.y * 18)
		_selection_box.visible = true

	main_panel.visible = true
	_update_toggle_btn()

	# If clicked directly on a creature, switch tab to Creature; otherwise stay or show Environment
	if tab_container != null:
		if selected_creature_eid != -1 and tab_container.current_tab == 0:
			tab_container.current_tab = 1

	update_inspector()
	tile_selected.emit(tile_pos)

func deselect() -> void:
	selected_tile = Vector2i(-1, -1)
	selected_creature_eid = -1
	if _selection_box != null:
		_selection_box.visible = false
	if main_panel != null:
		main_panel.visible = false
	_update_toggle_btn()
	tile_deselected.emit()

# ---------------------------------------------------------------------------
# Inspector Refresh
# ---------------------------------------------------------------------------

func update_inspector() -> void:
	if World == null or selected_tile == Vector2i(-1, -1):
		return

	var reg = World.get_registry()
	if reg == null:
		return

	var tile_eid: int = World.get_entity_at(selected_tile)

	# --- 1. Header & Position ---
	if coord_label != null:
		coord_label.text = "[%d, %d]" % [selected_tile.x, selected_tile.y]

	# --- 2. Environment Section ---
	_render_environment(reg, tile_eid)

	# --- 3. Creature Section ---
	if selected_creature_eid != -1:
		var c_comp: _CreatureComponent = reg.get_component(selected_creature_eid, &"CreatureComponent")
		if c_comp == null:
			selected_creature_eid = World.get_creature_at(selected_tile)
	else:
		selected_creature_eid = World.get_creature_at(selected_tile)

	_render_creature(reg, selected_creature_eid)

# ---------------------------------------------------------------------------
# Environment Rendering
# ---------------------------------------------------------------------------

func _render_environment(reg, tile_eid: int) -> void:
	if tile_eid == -1:
		if env_summary_label != null:
			env_summary_label.text = "[color=#8899aa]Empty Void Tile[/color]"
		return

	var tile_comp: _TileComponent    = reg.get_component(tile_eid, &"TileComponent")
	var biome_comp: _BiomeComponent  = reg.get_component(tile_eid, &"BiomeComponent")
	var matter_comp: _MatterComponent= reg.get_component(tile_eid, &"MatterComponent")
	var fluid_comp: _FluidComponent  = reg.get_component(tile_eid, &"FluidComponent")

	# 1. Summary (Terrain, Biome, Material, Climate)
	var tile_name: String = "Ground"
	if tile_comp != null:
		match tile_comp.tile_type:
			_TileTypes.Type.GROUND: tile_name = "Bare Ground"
			_TileTypes.Type.GRASS:  tile_name = "Lush Grass"
			_TileTypes.Type.DIRT:   tile_name = "Dry Dirt"
			_TileTypes.Type.STONE:  tile_name = "Rocky Stone"
			_TileTypes.Type.MUD:    tile_name = "Wet Mud"

	if fluid_comp != null and fluid_comp.volume > 0.01 and fluid_comp.material_id == _MaterialTypes.Type.WATER:
		if fluid_comp.volume >= 0.4:
			tile_name = "Deep Water (%s)" % tile_name
		else:
			tile_name = "Shallow Water (%s)" % tile_name

	var biome_name: String = "Plains"
	var moisture_pct: float = 50.0
	var temp_c: float = 20.0
	if biome_comp != null:
		match biome_comp.biome:
			_BiomeTypes.Type.PLAINS:      biome_name = "Plains"
			_BiomeTypes.Type.FOREST_EDGE: biome_name = "Forest Edge"
			_BiomeTypes.Type.WETLAND:     biome_name = "Wetland"
			_BiomeTypes.Type.BARREN:      biome_name = "Barren Highlands"
			_BiomeTypes.Type.TUNDRA:      biome_name = "Frozen Tundra"
		moisture_pct = biome_comp.moisture * 100.0

	var mat_name: String = "Soil"
	if matter_comp != null:
		temp_c = matter_comp.temperature_c
		var mat_data: Dictionary = _MaterialTypes.get_data(matter_comp.material_id)
		mat_name = mat_data.get("display_name", "Soil")

	if fluid_comp != null and fluid_comp.volume > 0.01:
		var fmat: String = _MaterialTypes.get_data(fluid_comp.material_id).get("display_name", "Water")
		mat_name = "%s / %s" % [fmat, mat_name]

	var season_names := ["Spring", "Summer", "Autumn", "Winter"]
	var s_idx: int = clampi(World.season, 0, 3) if World != null else 0
	var day_num: int = (World.tick_count / World.TICKS_PER_DAY) + 1 if World != null else 1
	var season_display: String = "%s (Day %d)" % [season_names[s_idx], day_num]

	if env_summary_label != null:
		env_summary_label.text = (
			"[b]Terrain:[/b] [color=#90ee90]%s[/color]   [b]Biome:[/b] [color=#87ceeb]%s[/color]\n" +
			"[b]Material:[/b] %s   [b]Temp:[/b] [color=#ffcc66]%.1f °C[/color]   [b]Moisture:[/b] [color=#66ccff]%.0f%%[/color]   [b]Season:[/b] [color=#ffb6c1]%s[/color]"
		) % [tile_name, biome_name, mat_name, temp_c, moisture_pct, season_display]

	# 2. Dynamic Activity / Phenomena ("What happens on that tile")
	var activity_parts: Array[String] = []
	var burn_comp: _BurningComponent = reg.get_component(tile_eid, &"BurningComponent")
	if burn_comp != null:
		activity_parts.append("[color=#ff4500]• [b]ACTIVE COMBUSTION[/b]: Intensity %.0f%% | Fuel %.0f%% (+%.0f°C/tick)[/color]" % [
			burn_comp.intensity * 100.0, burn_comp.fuel * 100.0, burn_comp.heat_output
		])

	if fluid_comp != null and fluid_comp.volume > 0.01:
		var fmat: String = _MaterialTypes.get_data(fluid_comp.material_id).get("display_name", "Fluid")
		var settled_str: String = "Settled" if fluid_comp.settled else "Flowing"
		activity_parts.append("[color=#00e5ff]• [b]SURFACE FLUID[/b]: %s (Depth: %.2fm, %s)[/color]" % [
			fmat, fluid_comp.volume, settled_str
		])

	var frozen_comp: _FrozenComponent = reg.get_component(tile_eid, &"FrozenComponent")
	if frozen_comp != null:
		activity_parts.append("[color=#b0e0e6]• [b]FROZEN SOLID[/b]: Ice layer active[/color]")

	var rain_comp: _RainComponent = reg.get_component(tile_eid, &"RainComponent")
	if rain_comp != null and rain_comp.intensity > 0.01:
		activity_parts.append("[color=#6495ed]• [b]PRECIPITATION[/b]: Rain intensity %.0f%%[/color]" % [
			rain_comp.intensity * 100.0
		])

	if activity_parts.is_empty():
		activity_parts.append("[color=#778899]• Calm & stable (No active hazards or phase changes)[/color]")

	if env_activity_label != null:
		env_activity_label.text = "\n".join(activity_parts)

	# 3. Vegetation
	var veg_comp: _VegetationComponent = reg.get_component(tile_eid, &"VegetationComponent")
	if veg_comp != null:
		var veg_data: Dictionary = _VegetationTypes.get_data(veg_comp.veg_type)
		var veg_name: String = veg_data.get("display_name", "Plant")
		var stage_names := ["Seedling", "Young", "Established", "Mature"]
		var stage_str: String = stage_names[clampi(veg_comp.growth_stage, 0, 3)]

		var yield_str: String = ""
		var yield_comp = reg.get_component(tile_eid, &"ItemYieldComponent")
		if yield_comp != null:
			var remaining: int = max(0, yield_comp.ticks_per_yield - yield_comp.ticks_since_yield)
			yield_str = " | Yield: Ready in %d ticks" % remaining

		if env_veg_label != null:
			env_veg_label.text = "[color=#7cd97c][b]%s[/b][/color] — Stage: [b]%s[/b] (Age: %.0f ticks)%s" % [
				veg_name, stage_str, veg_comp.age, yield_str
			]
	else:
		if env_veg_label != null:
			env_veg_label.text = "[color=#778899]No plant life present on this tile.[/color]"

	# 4. Ground Items
	var item_parts: Array[String] = []
	var inv_comp = reg.get_component(tile_eid, &"InventoryComponent")
	if inv_comp != null and not inv_comp.items.is_empty():
		var item_store: Dictionary = reg.get_store(&"ItemComponent")
		for item_eid: int in inv_comp.items:
			var item = item_store.get(item_eid, null)
			if item != null:
				item_parts.append("%s x%d (%.2f kg)" % [item.display_name, item.quantity, item.total_mass])

	if item_parts.is_empty():
		if env_items_label != null:
			env_items_label.text = "[color=#778899]None[/color]"
	else:
		if env_items_label != null:
			env_items_label.text = " • ".join(item_parts)

	# 5. Affordances & Signals
	if World.signals != null:
		var mask: int = World.signals.get_affordance(selected_tile)
		var mask_str: String = _TileAffordance.mask_to_string(mask)

		var sigs: Dictionary = World.signals.get_signals_at(selected_tile, 0.02)
		var sig_parts: Array[String] = []
		for s_name in sigs:
			sig_parts.append("%s: %.2f" % [String(s_name), sigs[s_name]])
		var sig_str: String = (" | Signals: " + ", ".join(sig_parts)) if not sig_parts.is_empty() else ""

		if env_affordance_label != null:
			env_affordance_label.text = "[b]Affordances:[/b] [color=#e0ffff]%s[/color]%s" % [mask_str, sig_str]

# ---------------------------------------------------------------------------
# Creature Rendering
# ---------------------------------------------------------------------------

func _render_creature(reg, ceid: int) -> void:
	if ceid == -1:
		if creature_section != null:
			creature_section.visible = false
		if no_creature_vbox != null:
			no_creature_vbox.visible = true
		if tab_container != null:
			tab_container.set_tab_title(1, "Creature (None)")
		return

	var creature: _CreatureComponent = reg.get_component(ceid, &"CreatureComponent")
	if creature == null:
		if creature_section != null:
			creature_section.visible = false
		if no_creature_vbox != null:
			no_creature_vbox.visible = true
		if tab_container != null:
			tab_container.set_tab_title(1, "Creature (None)")
		return

	if creature_section != null:
		creature_section.visible = true
	if no_creature_vbox != null:
		no_creature_vbox.visible = false

	var c_data: Dictionary = _CreatureTypes.get_data(creature.species_type)
	var species_name: String = c_data.get("display_name", "Creature")
	var status_str: String = "[ALIVE]" if creature.is_alive else "[DEAD / CARCASS]"

	if tab_container != null:
		tab_container.set_tab_title(1, "Creature (%s)" % species_name)

	var growth: _GrowthComponent = reg.get_component(ceid, &"CreatureGrowthComponent")
	var stage_str: String = ""
	if growth != null:
		var s_name: String = _CreatureTypes.get_stage_name(growth.current_stage)
		var scale_pct: int = int(round(growth.current_scale * 100.0))
		stage_str = " [%s, %d%% Scale]" % [s_name, scale_pct]

	if creature_header_label != null:
		var diet_name: String = _DietTypes.get_category_name(creature.diet)
		creature_header_label.text = "%s \"%s\" (eid=%d)%s [%s] — %s (Age: %d)" % [
			species_name, creature.creature_name, ceid, stage_str, diet_name, status_str, creature.age_ticks
		]

	# --- Thought & Action ---
	var plan: _ActionPlanComponent = reg.get_component(ceid, &"ActionPlanComponent")
	var mind: _MindComponent       = reg.get_component(ceid, &"MindComponent")

	var act_name: String = "IDLE"
	var thought_text: String = "Observing the area calmly."
	var dest_text: String = ""

	if plan != null:
		match plan.current_goal:
			_MindEmbeddings.Action.EAT:
				act_name = "EAT"
				if plan.target_tile == selected_tile or plan.path_queue.is_empty():
					thought_text = "Consuming compatible food to satiate hunger."
				else:
					thought_text = "Seeking food at %s (hunger drive: %.0f%%)." % [
						plan.target_tile, mind.hunger * 100.0 if mind != null else 50.0
					]
			_MindEmbeddings.Action.DRINK:
				act_name = "DRINK"
				if plan.target_tile == selected_tile or plan.path_queue.is_empty():
					thought_text = "Drinking clean water to quench thirst."
				else:
					thought_text = "Seeking clean hydration source at %s (thirst drive: %.0f%%)." % [
						plan.target_tile, mind.thirst * 100.0 if mind != null else 50.0
					]
			_MindEmbeddings.Action.FLEE:
				act_name = "FLEE"
				thought_text = "Fleeing in panic from dangerous hazards!"
			_MindEmbeddings.Action.REST:
				act_name = "REST"
				if plan.target_tile != selected_tile and not plan.path_queue.is_empty():
					thought_text = "Seeking cover at %s to rest safely (fatigue: %.0f%%)." % [
						plan.target_tile, mind.fatigue * 100.0 if mind != null else 50.0
					]
				else:
					thought_text = "Resting to recover depleted energy (fatigue: %.0f%%)." % [
						mind.fatigue * 100.0 if mind != null else 50.0
					]
			_MindEmbeddings.Action.WANDER:
				act_name = "WANDER"
				thought_text = "Curiously exploring terrain (curiosity drive: %.0f%%)." % [
					mind.curiosity * 100.0 if mind != null else 50.0
				]
			_MindEmbeddings.Action.IDLE:
				act_name = "IDLE"
				thought_text = "Standing alert and surveying surroundings."

		if plan.target_tile != Vector2i(-1, -1):
			dest_text = "  •  Target: %s (%d steps remaining)" % [plan.target_tile, plan.path_queue.size()]

	if creature_thought_label != null:
		creature_thought_label.text = (
			"[b]Current Action:[/b] [color=#ffd700][b]%s[/b][/color]%s\n" +
			"[b]Thought:[/b] [i]\"%s\"[/i]"
		) % [act_name, dest_text, thought_text]

	# Action Utilities Breakdown
	if creature_utilities_label != null and mind != null and not mind.action_utilities.is_empty():
		var util_parts: Array[String] = []
		for act: int in [
			_MindEmbeddings.Action.EAT,
			_MindEmbeddings.Action.DRINK,
			_MindEmbeddings.Action.FLEE,
			_MindEmbeddings.Action.REST,
			_MindEmbeddings.Action.WANDER,
			_MindEmbeddings.Action.IDLE
		]:
			var u_val: float = mind.action_utilities.get(act, 0.0)
			var a_str: String = _MindEmbeddings.Action.keys()[act]
			var is_selected: bool = (plan != null and plan.current_goal == act)
			if is_selected:
				util_parts.append("[b][color=#ffd700]%s: %.2f[/color][/b]" % [a_str, u_val])
			else:
				util_parts.append("[color=#99aacc]%s: %.2f[/color]" % [a_str, u_val])
		creature_utilities_label.text = "[b]Decision Utilities:[/b] " + ("  |  ".join(util_parts))

	# --- Traits & Status Section ---
	if creature_traits_label == null and creature_section != null:
		var trait_vbox := VBoxContainer.new()
		trait_vbox.name = "TraitsVBox"
		var trait_title := Label.new()
		trait_title.text = "Genetic Profile & Active Status:"
		trait_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 1.0))
		trait_title.add_theme_font_size_override("font_size", 11)
		trait_vbox.add_child(trait_title)

		creature_traits_label = RichTextLabel.new()
		creature_traits_label.name = "CreatureTraitsLabel"
		creature_traits_label.bbcode_enabled = true
		creature_traits_label.fit_content = true
		creature_traits_label.scroll_active = false
		creature_traits_label.add_theme_font_size_override("normal_font_size", 10)
		creature_traits_label.add_theme_font_size_override("bold_font_size", 10)
		trait_vbox.add_child(creature_traits_label)

		creature_section.add_child(trait_vbox)
		if creature_utilities_label != null:
			creature_section.move_child(trait_vbox, creature_utilities_label.get_index() + 1)

	if creature_traits_label != null:
		var traits: _TraitComponent = reg.get_component(ceid, &"TraitComponent")
		if traits != null:
			var t_lines: Array[String] = []

			# Life Stage & Growth Progress
			var growth_c: _GrowthComponent = reg.get_component(ceid, &"CreatureGrowthComponent")
			if growth_c != null:
				var st_name: String = _CreatureTypes.get_stage_name(growth_c.current_stage)
				var prog_pct: int = int(round(growth_c.growth_progress * 100.0))
				var stunt_str: String = " [color=#ff6666](Growth Stunted: Malnourished)[/color]" if growth_c.is_stunted else ""
				t_lines.append("[b]Life Stage:[/b] [color=#e0ffff]%s[/color] (Maturation: %d%%)%s" % [st_name, prog_pct, stunt_str])

			# Genetic traits
			var g_parts: Array[String] = []
			for tid: int in traits.genetic_traits:
				var tdata: Dictionary = _TraitTypes.get_data(tid)
				var tname: String = tdata.get("name", "Unknown")
				var tcol: Color = tdata.get("color", Color.WHITE)
				g_parts.append("[color=#%s][b]%s[/b][/color]" % [tcol.to_html(false), tname])
			if g_parts.is_empty():
				t_lines.append("[b]Genetics:[/b] [color=#888888]None (Standard Profile)[/color]")
			else:
				t_lines.append("[b]Genetics:[/b] " + ", ".join(g_parts))

			# Active Buffs
			var b_parts: Array[String] = []
			for bid: int in traits.active_buffs:
				var binfo = traits.active_buffs[bid]
				var bdata: Dictionary = _TraitTypes.get_data(bid)
				var bname: String = bdata.get("name", "Buff")
				var bcol: Color = bdata.get("color", Color(0.4, 0.9, 0.4))
				b_parts.append("[color=#%s]%s (%dt)[/color]" % [bcol.to_html(false), bname, binfo["duration"]])

			# Active Debuffs
			var d_parts: Array[String] = []
			for did: int in traits.active_debuffs:
				var dinfo = traits.active_debuffs[did]
				var ddata: Dictionary = _TraitTypes.get_data(did)
				var dname: String = ddata.get("name", "Debuff")
				var dcol: Color = ddata.get("color", Color(0.9, 0.4, 0.3))
				d_parts.append("[color=#%s]%s (%dt)[/color]" % [dcol.to_html(false), dname, dinfo["duration"]])

			if not b_parts.is_empty() or not d_parts.is_empty():
				var effects_str: String = ""
				if not b_parts.is_empty():
					effects_str += "[b]Buffs:[/b] " + ", ".join(b_parts)
				if not d_parts.is_empty():
					if effects_str != "":
						effects_str += "  |  "
					effects_str += "[b]Debuffs:[/b] " + ", ".join(d_parts)
				t_lines.append(effects_str)
			else:
				t_lines.append("[b]Status Effects:[/b] [color=#888888]No active buffs/debuffs[/color]")

			creature_traits_label.text = "\n".join(t_lines)
		else:
			creature_traits_label.text = "[color=#888888]No trait component attached[/color]"

	# --- Body Condition ---
	var body: _BodyComponent = reg.get_component(ceid, &"BodyComponent")

	var health_pct: float = creature.health * 100.0
	if health_bar != null:
		health_bar.value = health_pct
	if health_val_label != null:
		health_val_label.text = "%.0f%%" % health_pct

	var stamina_pct: float = creature.stamina * 100.0
	if stamina_bar != null:
		stamina_bar.value = stamina_pct
	if stamina_val_label != null:
		stamina_val_label.text = "%.0f%%" % stamina_pct

	var mass: float = body.get_total_mass(reg) if body != null else 20.0
	var blood_vol: float = body.blood_volume if body != null else 2.0
	var max_blood: float = body.max_blood_volume if body != null else 2.0
	var bleed_rate: float = body.bleed_rate if body != null else 0.0
	var core_temp: float = body.body_temperature_c if body != null else 38.0
	var stomach_fill: float = creature.stomach_fill
	var stomach_cap: float = creature.stomach_capacity

	var bleed_alert: String = ""
	if bleed_rate > 0.001:
		bleed_alert = "  [color=#ff4500][b]BLEEDING: -%.2f L/tick![/b][/color]" % bleed_rate

	if creature_body_label != null:
		creature_body_label.text = (
			"[b]Nutrition:[/b] %.1f / %.1f pts (%.0f%%)   [b]Mobility:[/b] %.0f%%   [b]Mass:[/b] %.1f kg\n" +
			"[b]Blood:[/b] %.2f / %.2f L%s   [b]Core Temp:[/b] %.1f °C"
		) % [stomach_fill, stomach_cap, (stomach_fill / maxf(1.0, stomach_cap)) * 100.0,
			creature.mobility_factor * 100.0, mass, blood_vol, max_blood, bleed_alert, core_temp]

	# Limbs & Organs breakdown
	if creature_anatomy_label != null and body != null:
		var item_store: Dictionary = reg.get_store(&"ItemComponent")
		var limb_parts: Array[String] = []
		for l_name: String in body.limbs:
			var l_eid: int = body.limbs[l_name]
			var l_item = item_store.get(l_eid, null)
			var status: String = "[color=#55ff55]OK[/color]"
			if l_item != null:
				var wear: float = maxf(l_item.parts.get("flesh", {}).get("wear", 0.0), l_item.parts.get("bone", {}).get("wear", 0.0))
				if wear >= 1.0:
					status = "[color=#ff4500]Severed[/color]"
				elif wear >= 0.5:
					status = "[color=#ffaa00]Damaged[/color]"
			limb_parts.append("%s: %s" % [l_name, status])

		var organ_parts: Array[String] = []
		for o_name: String in body.organs:
			var o_eid: int = body.organs[o_name]
			var o_item = item_store.get(o_eid, null)
			var status: String = "[color=#55ff55]Intact[/color]"
			if o_item != null:
				var wear: float = o_item.parts.get("tissue", {}).get("wear", 0.0)
				if wear >= 1.0:
					status = "[color=#ff0000]Destroyed[/color]"
				elif wear >= 0.5:
					status = "[color=#ffaa00]Compromised[/color]"
			organ_parts.append("%s: %s" % [o_name, status])

		creature_anatomy_label.text = (
			"[b]Limbs:[/b] %s\n[b]Vitals:[/b] %s"
		) % [", ".join(limb_parts), ", ".join(organ_parts)]

	# --- Mind Condition ---
	if mind != null:
		var mood_str: String = "Calm & Content"
		var mood_col: Color = Color(0.6, 0.9, 0.6)
		if mind.fear > 0.4:
			mood_str = "Terrified & Panicked!"
			mood_col = Color(1.0, 0.3, 0.3)
		elif mind.pain > 0.3:
			mood_str = "In Acute Pain"
			mood_col = Color(1.0, 0.4, 0.2)
		elif mind.hunger > 0.6:
			mood_str = "Starving & Foraging"
			mood_col = Color(1.0, 0.8, 0.3)
		elif mind.thirst > 0.6:
			mood_str = "Dehydrated & Seeking Water"
			mood_col = Color(0.4, 0.8, 1.0)
		elif mind.fatigue > 0.7:
			mood_str = "Exhausted & Seeking Rest"
			mood_col = Color(0.7, 0.7, 0.9)
		elif mind.curiosity > 0.5:
			mood_str = "Curious & Exploring"
			mood_col = Color(0.8, 0.9, 0.5)

		if creature_mood_label != null:
			creature_mood_label.text = "Mood: %s" % mood_str
			creature_mood_label.modulate = mood_col

		var drives_text: String = (
			"[b]Hunger:[/b] [color=#ffaa33]%.0f%%[/color]   " +
			"[b]Thirst:[/b] [color=#33ccff]%.0f%%[/color]   " +
			"[b]Fear:[/b] [color=#ff5555]%.0f%%[/color]   " +
			"[b]Fatigue:[/b] [color=#cc99ff]%.0f%%[/color]\n" +
			"[b]Curiosity:[/b] [color=#ffee55]%.0f%%[/color]   " +
			"[b]Pain:[/b] [color=#ff4444]%.0f%%[/color]   " +
			"[b]Comfort:[/b] [color=#66ff99]%.0f%%[/color]   " +
			"[b]Social:[/b] [color=#ff99cc]%.0f%%[/color]"
		) % [
			mind.hunger * 100.0,
			mind.thirst * 100.0,
			mind.fear * 100.0,
			mind.fatigue * 100.0,
			mind.curiosity * 100.0,
			mind.pain * 100.0,
			(mind.drives[_MindEmbeddings.Drive.COMFORT] if mind.drives.size() > 6 else 0.0) * 100.0,
			(mind.drives[_MindEmbeddings.Drive.SOCIABILITY] if mind.drives.size() > 7 else 0.0) * 100.0
		]

		if creature_drives_label != null:
			creature_drives_label.text = drives_text

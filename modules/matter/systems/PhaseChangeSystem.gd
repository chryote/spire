## PhaseChangeSystem.gd
## Priority 15 — runs every 10 ticks, after climate/rain have updated
## BiomeComponent.temperature and .moisture.
##
## Per entity with MatterComponent:
##   1. Sync temperature_c and moisture from BiomeComponent.
##   2. Freeze check  : LIQUID + temp < melting_point  → add FrozenComponent, state=SOLID
##   3. Melt check    : SOLID  + temp > melting_point  → add MeltedComponent, state=LIQUID
##   4. Boil check    : LIQUID + temp > boiling_point  → state=GAS (tile visually empties)
##   5. Moisture drying: high temperature gradually dries out materials.
class_name PhaseChangeSystem
extends "res://core/SystemBase.gd"

const _FrozenComponent  = preload("res://modules/matter/components/FrozenComponent.gd")
const _MeltedComponent  = preload("res://modules/matter/components/MeltedComponent.gd")
const _BurningComponent = preload("res://modules/matter/components/BurningComponent.gd")
const _FluidComponent   = preload("res://modules/matter/components/FluidComponent.gd")
const _GasComponent     = preload("res://modules/matter/components/GasComponent.gd")

## Celsius conversion constants matching World.TEMP_MIN_C (-20.0) and World.TEMP_MAX_C (50.0).
const TEMP_MIN_C: float = -20.0
const TEMP_RANGE_C: float = 70.0  # 50.0 - (-20.0)

## Lerp rate for moisture syncing toward BiomeComponent.moisture per cycle.
## Sliced across 20 ticks (Rare Tick interval) so rate is scaled accordingly.
const MOISTURE_SYNC_RATE: float = 0.08

## Number of slices to distribute 16,384 entities evenly across ticks (~819/tick).
const SLICE_COUNT: int = 20

## Temperature above which materials start drying out (deg C).
const DRY_THRESHOLD_C: float = 60.0

var _tile_slices: Array[PackedInt32Array] = []
var _slice_matter: Array[Array] = []
var _slice_biome: Array[Array] = []
var _initialized_tiles: bool = false
var _total_tiles: int = 16384
var _item_slices: Array[PackedInt32Array] = []
var _cached_item_store_size: int = -1

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	pass

func _init_tile_slices() -> void:
	_tile_slices.clear()
	_slice_matter.clear()
	_slice_biome.clear()
	for i in range(SLICE_COUNT):
		_tile_slices.append(PackedInt32Array())
		_slice_matter.append([])
		_slice_biome.append([])

	_total_tiles = 128 * 128
	if world != null:
		_total_tiles = world.MAP_WIDTH * world.MAP_HEIGHT

	var reg = world.get_registry() if world != null else null
	var matter_store: Dictionary = reg.get_store(&"MatterComponent") if reg != null else {}
	var biome_store:  Dictionary = reg.get_store(&"BiomeComponent") if reg != null else {}

	for eid: int in range(_total_tiles):
		var slice_idx: int = eid % SLICE_COUNT
		_tile_slices[slice_idx].append(eid)
		_slice_matter[slice_idx].append(matter_store.get(eid, null))
		_slice_biome[slice_idx].append(biome_store.get(eid, null))

	_initialized_tiles = true

func _rebuild_item_slices(item_store: Dictionary, biome_store: Dictionary) -> void:
	_item_slices.clear()
	for i in range(SLICE_COUNT):
		_item_slices.append(PackedInt32Array())
	for item_eid: int in item_store:
		if biome_store.has(item_eid):
			_item_slices[item_eid % SLICE_COUNT].append(item_eid)
	_cached_item_store_size = item_store.size()

func tick(tick_number: int) -> void:
	var reg = world.get_registry()
	var matter_store: Dictionary = reg.get_store(&"MatterComponent")
	var biome_store:  Dictionary = reg.get_store(&"BiomeComponent")
	var veg_store:    Dictionary = reg.get_store(&"VegetationComponent")
	var slice_mod: int = tick_number % SLICE_COUNT

	if not _initialized_tiles:
		_init_tile_slices()
	elif _total_tiles > 0 and not _slice_matter.is_empty() and not _slice_matter[0].is_empty() and _slice_matter[0][0] == null:
		_init_tile_slices()

	# 1. Process static tiles assigned to this slice (~819 tiles)
	var tile_slice: PackedInt32Array = _tile_slices[slice_mod]
	var mat_slice: Array = _slice_matter[slice_mod]
	var bio_slice: Array = _slice_biome[slice_mod]
	var slice_count: int = tile_slice.size()

	for i: int in range(slice_count):
		var matter: MatterComponent = mat_slice[i]
		if matter == null:
			matter = matter_store.get(tile_slice[i], null)
			mat_slice[i] = matter
			if matter == null:
				continue

		var biome: BiomeComponent = bio_slice[i]
		if biome == null:
			biome = biome_store.get(tile_slice[i], null)
			bio_slice[i] = biome
			if biome == null:
				continue

		var entity_id: int = tile_slice[i]

		# --- 1. Sync temperature ---
		matter.temperature_c = TEMP_MIN_C + biome.temperature * TEMP_RANGE_C

		# --- 1b. Auto-ignition ---
		if matter.flammability > 0.05 and matter.temperature_c >= matter.ignition_temp_c:
			if not reg.has(entity_id, &"BurningComponent"):
				var b = _BurningComponent.new()
				b.intensity  = matter.flammability
				b.fuel       = 1.0
				b.heat_output = 20.0 + matter.flammability * 15.0
				reg.add(entity_id, b)

		# --- 2. Sync moisture (skip for vegetation — VegetationGrowthSystem owns it) ---
		if not veg_store.has(entity_id):
			matter.moisture = lerpf(matter.moisture, biome.moisture, MOISTURE_SYNC_RATE)

		# --- 3. Moisture drying from heat ---
		if matter.temperature_c > DRY_THRESHOLD_C:
			var dry_rate: float = (matter.temperature_c - DRY_THRESHOLD_C) / 200.0 * 0.005
			matter.moisture = maxf(0.0, matter.moisture - dry_rate)

		# --- 4. Freeze check (LIQUID → SOLID) ---
		if matter.state == 1:
			if matter.temperature_c < matter.melting_point_c:
				# Thermal lag: high specific_heat = more ticks needed to freeze.
				if matter._freeze_lag <= 0:
					matter._freeze_lag = int(matter.specific_heat / 500.0)
				matter._freeze_lag -= 1
				if matter._freeze_lag <= 0 and not reg.has(entity_id, &"FrozenComponent"):
					reg.add(entity_id, _FrozenComponent.new())
					if reg.has(entity_id, &"MeltedComponent"):
						reg.remove(entity_id, &"MeltedComponent")
					if reg.has(entity_id, &"FluidComponent"):
						reg.remove(entity_id, &"FluidComponent")
					matter.state = 0  # SOLID
					_on_frozen(entity_id, matter, reg)
				continue
			else:
				if matter._freeze_lag != 0:
					matter._freeze_lag = 0

			# --- 6. Boil check (LIQUID -> GAS) ---
			if matter.boiling_point_c < 200.0 and matter.temperature_c > matter.boiling_point_c:
				matter.state = 2  # GAS
				if reg.has(entity_id, &"MeltedComponent"):
					reg.remove(entity_id, &"MeltedComponent")
				if reg.has(entity_id, &"FluidComponent"):
					reg.remove(entity_id, &"FluidComponent")
				_on_boiled(entity_id, matter, reg)

		# --- 5. Melt check (SOLID -> LIQUID) ---
		elif matter.state == 0 and matter.melting_point_c < 200.0:
			if matter.temperature_c > matter.melting_point_c:
				# Thermal lag: high specific_heat = more ticks needed to melt.
				if matter._melt_lag <= 0:
					matter._melt_lag = int(matter.specific_heat / 500.0)
				matter._melt_lag -= 1
				if matter._melt_lag <= 0 and not reg.has(entity_id, &"MeltedComponent"):
					reg.add(entity_id, _MeltedComponent.new())
					if reg.has(entity_id, &"FrozenComponent"):
						reg.remove(entity_id, &"FrozenComponent")
					matter.state = 1  # LIQUID
					_on_melted(entity_id, matter, reg)
				continue
			elif matter._melt_lag != 0:
				matter._melt_lag = 0

	# 2. Process dynamic items with BiomeComponent (pre-bucketed)
	# Optimization: Items never have BiomeComponent unless explicitly added.
	# If biome_store only contains static terrain tiles, skip item scanning completely in O(1).
	if biome_store.size() > _total_tiles:
		var item_store: Dictionary = reg.get_store(&"ItemComponent")
		if not item_store.is_empty():
			if _cached_item_store_size != item_store.size():
				_rebuild_item_slices(item_store, biome_store)
			var item_slice: PackedInt32Array = _item_slices[slice_mod]
			for item_eid: int in item_slice:
				var matter = matter_store.get(item_eid, null)
				if matter == null:
					continue
				var biome = biome_store.get(item_eid, null)
				if biome != null:
					_process_matter_entity(item_eid, matter, biome, reg, veg_store)

func _process_matter_entity(entity_id: int, matter, biome, reg, veg_store: Dictionary = {}) -> void:
	# --- 1. Sync temperature ---
	matter.temperature_c = TEMP_MIN_C + biome.temperature * TEMP_RANGE_C

	# --- 1b. Auto-ignition (Gap 1) ---
	if matter.flammability > 0.05 and matter.temperature_c >= matter.ignition_temp_c:
		if not reg.has(entity_id, &"BurningComponent"):
			var b = _BurningComponent.new()
			b.intensity  = matter.flammability
			b.fuel       = 1.0
			b.heat_output = 20.0 + matter.flammability * 15.0
			reg.add(entity_id, b)

	# --- 2. Sync moisture (skip for vegetation — VegetationGrowthSystem owns it) ---
	var is_veg: bool = veg_store.has(entity_id) if not veg_store.is_empty() else reg.has(entity_id, &"VegetationComponent")
	if not is_veg:
		matter.moisture = lerpf(matter.moisture, biome.moisture, MOISTURE_SYNC_RATE)

	# --- 3. Moisture drying from heat ---
	if matter.temperature_c > DRY_THRESHOLD_C:
		var dry_rate: float = (matter.temperature_c - DRY_THRESHOLD_C) / 200.0 * 0.005
		matter.moisture = maxf(0.0, matter.moisture - dry_rate)

	# --- 4. Freeze check (LIQUID → SOLID) ---
	if matter.state == 1:
		if matter.temperature_c < matter.melting_point_c:
			if matter._freeze_lag <= 0:
				matter._freeze_lag = int(matter.specific_heat / 500.0)
			matter._freeze_lag -= 1
			if matter._freeze_lag <= 0 and not reg.has(entity_id, &"FrozenComponent"):
				reg.add(entity_id, _FrozenComponent.new())
				if reg.has(entity_id, &"MeltedComponent"):
					reg.remove(entity_id, &"MeltedComponent")
				if reg.has(entity_id, &"FluidComponent"):
					reg.remove(entity_id, &"FluidComponent")
				matter.state = 0  # SOLID
				_on_frozen(entity_id, matter, reg)
			return
		else:
			if matter._freeze_lag != 0:
				matter._freeze_lag = 0

		# --- 6. Boil check (LIQUID -> GAS) ---
		if matter.temperature_c > matter.boiling_point_c:
			matter.state = 2  # GAS
			if reg.has(entity_id, &"MeltedComponent"):
				reg.remove(entity_id, &"MeltedComponent")
			if reg.has(entity_id, &"FluidComponent"):
				reg.remove(entity_id, &"FluidComponent")
			_on_boiled(entity_id, matter, reg)

	# --- 5. Melt check (SOLID -> LIQUID) ---
	elif matter.state == 0:
		if matter.temperature_c > matter.melting_point_c:
			if matter._melt_lag <= 0:
				matter._melt_lag = int(matter.specific_heat / 500.0)
			matter._melt_lag -= 1
			if matter._melt_lag <= 0 and not reg.has(entity_id, &"MeltedComponent"):
				reg.add(entity_id, _MeltedComponent.new())
				if reg.has(entity_id, &"FrozenComponent"):
					reg.remove(entity_id, &"FrozenComponent")
				matter.state = 1  # LIQUID
				_on_melted(entity_id, matter, reg)
			return
		else:
			if matter._melt_lag != 0:
				matter._melt_lag = 0

# ---------------------------------------------------------------------------
# State change callbacks (update RenderComponent)
# ---------------------------------------------------------------------------

func _on_frozen(_entity_id: int, _matter, _reg) -> void:
	# Frozen state is visualised in AsciiRenderSystem via FrozenComponent.
	pass

func _on_melted(entity_id: int, matter, reg) -> void:
	# Add FluidComponent if not present
	if not reg.has(entity_id, &"FluidComponent"):
		var fluid = _FluidComponent.new()
		fluid.volume = 1.0
		fluid.material_id = matter.material_id
		fluid.settled = false
		reg.add(entity_id, fluid)
	else:
		var fluid = reg.get_component(entity_id, &"FluidComponent")
		fluid.volume = 1.0
		fluid.settled = false

	# Melted state can darken the render slightly.
	var render = reg.get_component(entity_id, &"RenderComponent")
	if render == null:
		return
	render.bg_color = render.bg_color.darkened(0.15)
	if world != null:
		world.mark_render_dirty()

func _on_boiled(entity_id: int, matter, reg) -> void:
	# Add GasComponent if not present
	if not reg.has(entity_id, &"GasComponent"):
		var gas = _GasComponent.new()
		gas.concentration = 1.0
		gas.material_id = matter.material_id
		reg.add(entity_id, gas)
	else:
		var gas = reg.get_component(entity_id, &"GasComponent")
		gas.concentration = 1.0

	# Gas state - tile becomes nearly invisible (empty/vapour).
	var render = reg.get_component(entity_id, &"RenderComponent")
	if render == null:
		return
	render.glyph    = " "
	render.fg_color = Color(0.5, 0.5, 0.7, 0.3)
	render.bg_color = Color(0.0, 0.0, 0.05)
	if world != null:
		world.mark_render_dirty()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _to_celsius(t: float) -> float:
	return TEMP_MIN_C + t * TEMP_RANGE_C

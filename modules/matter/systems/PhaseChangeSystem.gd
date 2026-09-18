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


## Lerp rate for moisture syncing toward BiomeComponent.moisture per cycle.
const MOISTURE_SYNC_RATE: float = 0.04

## Temperature above which materials start drying out (deg C).
const DRY_THRESHOLD_C: float = 60.0

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	pass

func tick(tick_number: int) -> void:
	if tick_number % 10 != 0:
		return

	var reg = world.get_registry()
	var matter_store: Dictionary = reg.get_store(&"MatterComponent")

	for entity_id: int in matter_store:
		var matter = matter_store[entity_id]
		var biome  = reg.get_component(entity_id, &"BiomeComponent")
		if biome == null:
			continue

		# --- 1. Sync temperature ---
		matter.temperature_c = _to_celsius(biome.temperature)

		# --- 1b. Auto-ignition (Gap 1) ---
		# If temperature exceeds ignition_temp_c and the material is flammable,
		# seed a BurningComponent — no external trigger required.
		if matter.ignition_temp_c < INF and matter.flammability > 0.05:
			if matter.temperature_c >= matter.ignition_temp_c:
				if not reg.has(entity_id, &"BurningComponent"):
					var b = _BurningComponent.new()
					b.intensity  = matter.flammability
					b.fuel       = 1.0
					b.heat_output = 20.0 + matter.flammability * 15.0
					reg.add(entity_id, b)

		# --- 2. Sync moisture (skip for vegetation — VegetationGrowthSystem owns it) ---
		if not reg.has(entity_id, &"VegetationComponent"):
			matter.moisture = lerpf(matter.moisture, biome.moisture, MOISTURE_SYNC_RATE)

		# --- 3. Moisture drying from heat ---
		if matter.temperature_c > DRY_THRESHOLD_C:
			var dry_rate: float = (matter.temperature_c - DRY_THRESHOLD_C) / 200.0 * 0.005
			matter.moisture = maxf(0.0, matter.moisture - dry_rate)

		# --- 4. Freeze check (LIQUID → SOLID) ---
		if matter.state == 1 and matter.melting_point_c < INF:
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
				matter._freeze_lag = 0  # reset lag if no longer cold enough

		# --- 5. Melt check (SOLID -> LIQUID) ---
		elif matter.state == 0 and matter.melting_point_c < INF:
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
			else:
				matter._melt_lag = 0  # reset lag if no longer hot enough

		# --- 6. Boil check (LIQUID -> GAS) ---
		if matter.state == 1 and matter.boiling_point_c < INF:
			if matter.temperature_c > matter.boiling_point_c:
				matter.state = 2  # GAS
				# Remove liquid markers
				if reg.has(entity_id, &"MeltedComponent"):
					reg.remove(entity_id, &"MeltedComponent")
				if reg.has(entity_id, &"FluidComponent"):
					reg.remove(entity_id, &"FluidComponent")
				_on_boiled(entity_id, matter, reg)

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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _to_celsius(t: float) -> float:
	return World.TEMP_MIN_C + t * (World.TEMP_MAX_C - World.TEMP_MIN_C)

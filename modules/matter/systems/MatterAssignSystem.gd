## MatterAssignSystem.gd
## Priority 1 — one-shot terrain assignment + per-tick vegetation sync.
##
## initialize(): assigns MatterComponent to every terrain tile entity
##               using TILE_MATERIAL_MAP. Temperature is synced from
##               BiomeComponent at that moment.
##
## tick() (every 5 ticks): ensures entities with VegetationComponent have
##               the correct vegetation material, and reverts to terrain
##               material when vegetation is removed (e.g. after fire).
class_name MatterAssignSystem
extends "res://core/SystemBase.gd"

const _MatterComponent = preload("res://modules/matter/components/MatterComponent.gd")
const _MaterialTypes   = preload("res://modules/matter/data/MaterialTypes.gd")

# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

func initialize() -> void:
	var reg = world.get_registry()
	var tile_store: Dictionary = reg.get_store(&"TileComponent")
	var count: int = 0

	for entity_id: int in tile_store:
		var tile = tile_store[entity_id]
		var mat_id: int = _MaterialTypes.TILE_MATERIAL_MAP.get(tile.tile_type, _MaterialTypes.Type.GROUND)
		var matter = _MatterComponent.new()
		matter.material_id = mat_id
		_apply_data(matter, _MaterialTypes.get_data(mat_id))

		# Sync initial temperature from BiomeComponent
		var biome = reg.get_component(entity_id, &"BiomeComponent")
		if biome != null:
			matter.temperature_c = _to_celsius(biome.temperature)
			# Terrain moisture sourced from biome moisture
			matter.moisture = lerpf(
				matter.moisture,
				biome.moisture,
				0.5
			)

		if reg.has(entity_id, &"FluidComponent"):
			matter.state = 1  # LIQUID

		reg.add(entity_id, matter)
		count += 1

	print("[Matter] Assigned MatterComponent to %d tile entities." % count)

func tick(tick_number: int) -> void:
	if world != null and not world.is_rare_tick(tick_number):
		return

	var reg = world.get_registry()
	var veg_store: Dictionary = reg.get_store(&"VegetationComponent")

	for entity_id: int in veg_store:
		var matter = reg.get_component(entity_id, &"MatterComponent")
		if matter == null:
			continue
		var veg = veg_store[entity_id]
		var expected_id: int = _MaterialTypes.VEG_MATERIAL_MAP.get(veg.veg_type, -1)
		if expected_id >= 0 and matter.material_id != expected_id:
			var old_moisture: float = matter.moisture
			matter.material_id = expected_id
			_apply_data(matter, _MaterialTypes.get_data(expected_id))
			matter.moisture = lerpf(old_moisture, matter.moisture, 0.3)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _apply_data(matter, d: Dictionary) -> void:
	matter.state           = d.get("state",           0) as int
	matter.density         = d.get("density",         1000.0) as float
	matter.melting_point_c = d.get("melting_point_c", INF) as float
	matter.boiling_point_c = d.get("boiling_point_c", INF) as float
	matter.ignition_temp_c = d.get("ignition_temp_c", INF) as float
	matter.conductivity    = d.get("conductivity",    1.0) as float
	matter.specific_heat   = d.get("specific_heat",   1000.0) as float
	matter.flammability    = d.get("flammability",    0.0) as float
	matter.acidity_ph      = d.get("acidity_ph",      7.0) as float
	matter.corrosiveness   = d.get("corrosiveness",   0.0) as float
	matter.moisture        = d.get("moisture",        0.0) as float
	matter.rot_rate        = d.get("rot_rate",        0.0) as float
	matter.toxicity        = d.get("toxicity",        0.0) as float
	matter.hardness        = d.get("hardness",        5.0) as float
	matter.yield_strength  = d.get("yield_strength",  100.0) as float
	matter.elasticity      = d.get("elasticity",      0.3) as float

static func _to_celsius(t: float) -> float:
	return World.TEMP_MIN_C + t * (World.TEMP_MAX_C - World.TEMP_MIN_C)

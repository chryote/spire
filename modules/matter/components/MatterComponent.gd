## MatterComponent.gd
## Holds all physical, thermodynamic, chemical, and organic properties
## for a tangible material entity.
##
## material_id tracks which MaterialTypes preset is currently loaded so
## MatterAssignSystem can detect when vegetation or terrain changes
## require a material swap.
##
## temperature_c is synced from BiomeComponent.temperature by
## PhaseChangeSystem each cycle (using World.TEMP_MIN_C / TEMP_MAX_C).
class_name MatterComponent
extends Resource

## Tracks the MaterialTypes.Type int currently loaded (-1 = unset).
var material_id: int = -1

# ---------------------------------------------------------------------------
# Physical
# ---------------------------------------------------------------------------
## State enum: SOLID=0, LIQUID=1, GAS=2, COLLOID=3
var state: int = 0
var density: float = 1000.0      # kg/m3

# ---------------------------------------------------------------------------
# Thermodynamic
# ---------------------------------------------------------------------------
## Current local temperature in real Celsius (synced from BiomeComponent).
var temperature_c: float = 20.0
## INF = does not melt.
var melting_point_c: float = INF
## INF = does not boil.
var boiling_point_c: float = INF
## INF = non-flammable. Must be set externally for fire to ever spread.
var ignition_temp_c: float = INF
## Higher conductivity = heat spreads faster to neighbours.
var conductivity: float = 1.0
## Higher specific_heat = harder to change temperature (J/kg).
var specific_heat: float = 1000.0
## Internal: ticks remaining before freeze transition completes (thermal lag).
@warning_ignore("unused_private_class_variable")
var _freeze_lag: int = 0
## Internal: ticks remaining before melt transition completes (thermal lag).
@warning_ignore("unused_private_class_variable")
var _melt_lag: int = 0
## Internal: cumulative decay progress 0.0 to 1.0. Written by DecaySystem.
@warning_ignore("unused_private_class_variable")
var _decay_progress: float = 0.0


# ---------------------------------------------------------------------------
# Chemical
# ---------------------------------------------------------------------------
## 0.0 (inert) to 1.0 (explosive). Drives fire spread probability.
var flammability: float = 0.0
## pH 0.0 (extreme acid) to 14.0 (extreme base).
var acidity_ph: float = 7.0
## 0.0 to 1.0. Future: corrodes metal armour over time.
var corrosiveness: float = 0.0

# ---------------------------------------------------------------------------
# Organic
# ---------------------------------------------------------------------------
## 0.0 (bone dry) to 1.0 (saturated). Wet materials resist ignition.
var moisture: float = 0.0
## 0.0 (inert) to 1.0 (rots quickly). Future: decay simulation.
var rot_rate: float = 0.0
## 0.0 to 1.0. Future: damages biological entities on contact.
var toxicity: float = 0.0

# ---------------------------------------------------------------------------
# Mechanical
# ---------------------------------------------------------------------------
var hardness: float = 5.0
## Megapascals — resistance to permanent deformation.
var yield_strength: float = 100.0
## 0.0 (shatters) to 1.0 (stretches indefinitely).
var elasticity: float = 0.3

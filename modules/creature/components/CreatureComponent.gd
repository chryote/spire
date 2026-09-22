## CreatureComponent.gd
## Core identity and high-level biological state for a living creature entity.
class_name CreatureComponent
extends Resource

## Species archetype from CreatureTypes.Type.
var species_type: int = 0

## Human-readable individual name.
var creature_name: String = "Creature"

## Alive / dead state.
var is_alive: bool = true

## Monotonically increasing age in simulation ticks.
var age_ticks: int = 0

## Overall normalized health [0.0, 1.0] aggregated from organs and blood volume.
var health: float = 1.0

## Current stamina [0.0, 1.0] for locomotion and strenuous actions.
var stamina: float = 1.0

## Accumulated nutrients currently digesting in the stomach.
var stomach_fill: float = 15.0

## Maximum nutritional capacity of the stomach.
var stomach_capacity: float = 50.0

## Speed multiplier derived from leg mobility and terrain.
var mobility_factor: float = 1.0

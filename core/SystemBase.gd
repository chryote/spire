## SystemBase.gd
## Abstract base class for all simulation systems.
## Systems with class_name can be instantiated directly by World — no preload needed.
##
## Subclass contract:
##   - Override initialize() for one-shot setup (runs before first tick).
##   - Override tick(tick_number) for per-tick logic.
##   - Set enabled = false to suspend without unregistering.
class_name SystemBase
extends RefCounted

## Simulation systems only run when enabled.
var enabled: bool = true

## Lower priority value = runs earlier in the tick.
var priority: int = 0

## Injected by World during registration. Use this to access the registry,
## entity API, and spatial index.
var world: Node = null

# ---------------------------------------------------------------------------
# Virtual interface
# ---------------------------------------------------------------------------

## Called once after all systems are registered but before the first tick.
## Use for initial data generation or event subscriptions.
func initialize() -> void:
	pass

## Called every simulation tick in priority order.
## [param tick_number] is a monotonically increasing counter starting at 1.
func tick(tick_number: int) -> void:
	pass

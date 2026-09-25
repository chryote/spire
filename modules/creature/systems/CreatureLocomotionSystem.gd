## CreatureLocomotionSystem.gd
## Priority 235 -- runs between CreatureAISystem (230) and CreatureAbilitySystem (240).
##
## Pure spatial locomotion layer:
## 1. Steps creatures along their planned waypoints respecting movement cooldowns and mobility.
## 2. Updates position, facing direction, and spatial movement memory.
## 3. Emits acoustic footstep impulses and marks renderer dirty when actors move.
class_name CreatureLocomotionSystem
extends "res://core/SystemBase.gd"

const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _ImpactEventComponent = preload("res://modules/matter/components/ImpactEventComponent.gd")

func initialize() -> void:
	print("[CreatureLocomotionSystem] Initialized. Priority 235.")

func tick(tick_number: int) -> void:
	if world == null:
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var pos_store: Dictionary      = reg.get_store(&"PositionComponent")
	var plan_store: Dictionary     = reg.get_store(&"ActionPlanComponent")
	var mem_store: Dictionary      = reg.get_store(&"MemoryComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")

	var any_moved: bool = false

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var pos_comp: _PositionComponent = pos_store.get(eid, null)
		var plan: _ActionPlanComponent   = plan_store.get(eid, null)
		var mem: _MemoryComponent        = mem_store.get(eid, null)
		var traits: _TraitComponent      = trait_store.get(eid, null)

		if pos_comp == null or plan == null:
			continue

		# -------------------------------------------------------------------
		# Step Movement Execution
		# -------------------------------------------------------------------
		if pos_comp.move_cooldown_ticks > 0:
			pos_comp.move_cooldown_ticks -= 1
		elif not plan.path_queue.is_empty():
			var next_pos: Vector2i = plan.path_queue.pop_front()
			if world.is_valid_position(next_pos) and world.signals != null and world.signals.has_affordance(next_pos, _TileAffordance.WALKABLE):
				var move_delta: Vector2i = next_pos - pos_comp.position
				if move_delta != Vector2i.ZERO:
					pos_comp.facing = move_delta

				pos_comp.position = next_pos
				any_moved = true

				# Cooldown modified by leg mobility and traits
				var interval: int = pos_comp.base_move_interval
				if traits != null:
					interval += int(traits.get_stat_offset(&"move_cooldown"))
				if creature.mobility_factor < 0.99:
					interval = int(float(interval) / maxf(0.2, creature.mobility_factor))
				pos_comp.move_cooldown_ticks = maxi(1, interval)

				if mem != null:
					mem.record_event(next_pos, &"stepped", tick_number, 0.5)

				if world.signals != null:
					world.signals.emit_sound(next_pos, 0.1, 1)

	if any_moved:
		world.mark_render_dirty()

## Backward-compatibility forwarding stub for queue_creature_impact
func queue_creature_impact(
	creature_eid: int,
	target_eid: int,
	attack_name: String = "",
	target_velocity: Vector2 = Vector2.ZERO
) -> _ImpactEventComponent:
	if world != null and world.creature_abilities != null:
		return world.creature_abilities.queue_creature_impact(creature_eid, target_eid, attack_name, target_velocity)
	return null

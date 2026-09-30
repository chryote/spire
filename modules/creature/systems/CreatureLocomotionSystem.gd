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
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _ImpactEventComponent = preload("res://modules/matter/components/ImpactEventComponent.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")

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
			var next_pos: Vector2i = plan.path_queue[0]

			# 1. Map bounds and terrain walkability / swimmability
			var can_swim: bool = creature.can_swim or (traits != null and (traits.has_trait(_TraitTypes.Type.SWIMMER) or traits.get_stat_offset(&"can_swim") > 0.0 or traits.get_stat_multiplier(&"can_swim", 0.0) > 0.0))
			if not is_tile_traversable(world, next_pos, can_swim):
				plan.clear_path()
				continue

			# 2. Strict 1-creature-per-tile occupancy enforcement
			var occupant_eid: int = world.get_creature_at(next_pos)
			if occupant_eid != -1 and occupant_eid != eid:
				# If already adjacent to our target tile and that tile is occupied by another creature,
				# we have reached interaction range (e.g. attack/mate/socialize) - stop here.
				if next_pos == plan.target_tile and pos_comp.position.distance_squared_to(next_pos) <= 2:
					plan.clear_path()
					continue

				# Otherwise, tile is an intermediate obstruction: attempt sidestep detour
				var sidestep: Vector2i = _find_sidestep(world, pos_comp.position, next_pos, plan.target_tile, eid, can_swim)
				if sidestep != Vector2i(-1, -1):
					next_pos = sidestep
					plan.path_queue[0] = sidestep
				else:
					# Obstruction cannot be bypassed immediately; pause and wait
					pos_comp.move_cooldown_ticks = 1
					plan.blocked_ticks += 1
					if plan.blocked_ticks >= 3:
						plan.clear_path()
					continue

			# Tile is clear: pop waypoint from queue and execute step
			plan.path_queue.pop_front()
			plan.blocked_ticks = 0

			var move_delta: Vector2i = next_pos - pos_comp.position
			if move_delta != Vector2i.ZERO:
				pos_comp.facing = move_delta

			var old_pos: Vector2i = pos_comp.position
			pos_comp.position = next_pos
			world.update_creature_position(eid, old_pos, next_pos)
			any_moved = true

			var is_swimming: bool = world.signals != null and world.signals.has_affordance(next_pos, _TileAffordance.SWIMMABLE)

			# Cooldown modified by leg mobility, traits, and water drag
			var interval: int = pos_comp.base_move_interval
			if traits != null:
				interval += int(traits.get_stat_offset(&"move_cooldown"))
			if creature.mobility_factor < 0.99:
				interval = int(float(interval) / maxf(0.2, creature.mobility_factor))
			if is_swimming:
				var swim_mult: float = creature.swim_speed_mult
				if traits != null:
					swim_mult += traits.get_stat_offset(&"swim_speed_mult")
				swim_mult = clampf(swim_mult, 0.1, 2.0)
				interval = maxi(interval + 1, int(ceil(float(interval) / swim_mult)))

			pos_comp.move_cooldown_ticks = maxi(1, interval)

			if mem != null:
				mem.record_event(next_pos, &"stepped", tick_number, 0.5)

			if world.signals != null:
				var sound_vol: float = 0.25 if is_swimming else 0.10
				world.signals.emit_sound(next_pos, sound_vol, 2 if is_swimming else 1)
				if creature.diet == _DietTypes.Category.CARNIVORE:
					world.signals.emit_scent(_SignalTypes.SCENT_PREDATOR, next_pos, 0.60, 1)
				elif creature.diet == _DietTypes.Category.HERBIVORE:
					world.signals.emit_scent(_SignalTypes.SCENT_PREY, next_pos, 0.35, 1)

	if any_moved:
		world.mark_render_dirty()

## Helper to determine if a tile is traversable considering walkability and swimming capability.
static func is_tile_traversable(world: Node, pos: Vector2i, can_swim: bool = false) -> bool:
	if world == null or not world.is_valid_position(pos):
		return false
	if world.signals == null:
		return true
	if world.signals.has_affordance(pos, _TileAffordance.HAZARD_LETHAL):
		return false
	if world.signals.has_affordance(pos, _TileAffordance.WALKABLE):
		return true
	if can_swim and world.signals.has_affordance(pos, _TileAffordance.SWIMMABLE):
		return true
	return false

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

## Attempts to find an orthogonal unoccupied walkable tile to detour around an obstacle.
static func _find_sidestep(world: Node, cur_pos: Vector2i, blocked_pos: Vector2i, target_pos: Vector2i, self_eid: int, can_swim: bool = false) -> Vector2i:
	var delta: Vector2i = blocked_pos - cur_pos
	var candidates: Array[Vector2i] = []
	if delta.x != 0 and delta.y == 0:
		candidates.append(cur_pos + Vector2i(0, 1))
		candidates.append(cur_pos + Vector2i(0, -1))
	elif delta.y != 0 and delta.x == 0:
		candidates.append(cur_pos + Vector2i(1, 0))
		candidates.append(cur_pos + Vector2i(-1, 0))
	elif delta.x != 0 and delta.y != 0:
		candidates.append(cur_pos + Vector2i(delta.x, 0))
		candidates.append(cur_pos + Vector2i(0, delta.y))
	else:
		return Vector2i(-1, -1)

	var best_pos := Vector2i(-1, -1)
	var best_dist: float = 999.0

	for cand in candidates:
		if not is_tile_traversable(world, cand, can_swim):
			continue
		var occ: int = world.get_creature_at(cand)
		if occ != -1 and occ != self_eid:
			continue
		var d: float = cur_pos.distance_to(cand) if target_pos == Vector2i(-1, -1) else cand.distance_to(target_pos)
		if d < best_dist:
			best_dist = d
			best_pos = cand

	return best_pos

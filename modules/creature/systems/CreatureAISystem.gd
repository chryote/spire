## CreatureAISystem.gd
## Priority 230 -- runs between CreatureBodySystem (225) and CreatureLocomotionSystem (235).
##
## Cognitive decision-making layer:
## 1. Samples spatial signals and affordances from SignalSystem at the creature's location.
## 2. Computes utility scores across action prototypes using state-space vector embeddings.
## 3. Consults short-term memory (to avoid oscillation) and long-term memory (for distant resources).
## 4. Generates an ActionPlan with navigation waypoints.
class_name CreatureAISystem
extends "res://core/SystemBase.gd"

const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")

func initialize() -> void:
	print("[CreatureAISystem] Initialized. Priority 230.")

func tick(tick_number: int) -> void:
	if world == null or world.signals == null:
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var pos_store: Dictionary      = reg.get_store(&"PositionComponent")
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")
	var mem_store: Dictionary      = reg.get_store(&"MemoryComponent")
	var plan_store: Dictionary     = reg.get_store(&"ActionPlanComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var pos_comp: _PositionComponent = pos_store.get(eid, null)
		var mind: _MindComponent         = mind_store.get(eid, null)
		var mem: _MemoryComponent        = mem_store.get(eid, null)
		var plan: _ActionPlanComponent   = plan_store.get(eid, null)

		if pos_comp == null or mind == null or plan == null:
			continue

		var cur_pos: Vector2i = pos_comp.position

		# -------------------------------------------------------------------
		# 1. Environmental Perception via SignalSystem
		# -------------------------------------------------------------------
		var sig_data: Dictionary = world.signals.get_signals_at(cur_pos, 0.01)
		mind.perceived_signals = sig_data

		var hazard: float = sig_data.get(_SignalTypes.HAZARD, 0.0) as float
		if hazard > 0.05:
			mind.fear = clampf(mind.fear + hazard * 0.4, 0.0, 1.0)
		else:
			mind.fear = maxf(0.0, mind.fear - 0.02)

		# -------------------------------------------------------------------
		# 2. Embedding Utility Evaluation
		# -------------------------------------------------------------------
		var best_action: int = _MindEmbeddings.Action.IDLE
		var highest_utility: float = -1.0
		mind.action_utilities.clear()

		for act: int in [
			_MindEmbeddings.Action.FLEE,
			_MindEmbeddings.Action.GRAZE,
			_MindEmbeddings.Action.DRINK,
			_MindEmbeddings.Action.REST,
			_MindEmbeddings.Action.WANDER,
			_MindEmbeddings.Action.IDLE
		]:
			var u: float = _MindEmbeddings.evaluate_utility(mind.drives, sig_data, act)
			mind.action_utilities[act] = u
			if u > highest_utility:
				highest_utility = u
				best_action = act

		mind.current_action = best_action
		plan.current_goal = best_action

		# -------------------------------------------------------------------
		# 3. Action Planning & Path Selection
		# -------------------------------------------------------------------
		match best_action:
			_MindEmbeddings.Action.GRAZE:
				_plan_graze(cur_pos, plan, mem, tick_number)

			_MindEmbeddings.Action.DRINK:
				_plan_drink(cur_pos, plan, pos_comp, mem, tick_number)

			_MindEmbeddings.Action.FLEE:
				_plan_flee(cur_pos, plan)

			_MindEmbeddings.Action.WANDER:
				_plan_wander(cur_pos, plan, pos_comp, mem, tick_number)

			_MindEmbeddings.Action.REST, _MindEmbeddings.Action.IDLE:
				plan.clear_path()

func _plan_drink(cur_pos: Vector2i, plan: _ActionPlanComponent, pos_comp: _PositionComponent, mem: _MemoryComponent, tick_number: int) -> void:
	# 1. If already standing in or adjacent to drinkable water, stay and drink!
	var immediate_water: Vector2i = _find_drinkable_tile_at_or_adjacent(cur_pos)
	if immediate_water != Vector2i(-1, -1):
		plan.clear_path()
		plan.target_tile = immediate_water
		return

	# 2. If already en-route to a valid drink approach, keep following path
	if not plan.path_queue.is_empty() and plan.target_tile != Vector2i(-1, -1):
		if _find_drinkable_tile_at_or_adjacent(plan.target_tile) != Vector2i(-1, -1):
			return

	# 3. Search local area (radius 16) for the best uncontaminated drinkable water
	var best_approach := Vector2i(-1, -1)
	var best_water := Vector2i(-1, -1)
	var best_score: float = -999.0

	for dy in range(-16, 17):
		for dx in range(-16, 17):
			var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			if not world.is_valid_position(candidate):
				continue
			if not world.signals.has_affordance(candidate, _TileAffordance.DRINKABLE):
				continue
			if world.signals.has_affordance(candidate, _TileAffordance.HAZARD_LETHAL):
				continue

			var approach: Vector2i = _find_approach_for_water(candidate, cur_pos)
			if approach == Vector2i(-1, -1):
				continue

			var dist: float = cur_pos.distance_to(approach)
			var hydra_val: float = world.signals.get_signal(_SignalTypes.HYDRATION, candidate)

			# Penalize recently visited tiles to prevent looping
			var recency_penalty: float = 0.0
			if mem != null and mem.was_recently_at(approach, 30, tick_number):
				recency_penalty = 0.5

			var score: float = (hydra_val * 2.0) - (dist * 0.15) - recency_penalty
			if score > best_score:
				best_score = score
				best_approach = approach
				best_water = candidate

	# 4. Check long-term memory if no water found in immediate view
	if best_approach == Vector2i(-1, -1) and mem != null:
		var remembered_water := mem.get_closest_landmark(&"water_source", cur_pos)
		if remembered_water != Vector2i(-1, -1) and world.is_valid_position(remembered_water):
			best_approach = _find_approach_for_water(remembered_water, cur_pos)
			best_water = remembered_water

	# 5. Build path to approach tile or wander if no water located
	if best_approach != Vector2i(-1, -1):
		plan.target_tile = best_approach
		plan.path_queue = _build_simple_path(cur_pos, best_approach)
		if mem != null:
			mem.remember_landmark(best_water, &"water_source", 1.0, tick_number)
		if plan.path_queue.is_empty() and best_approach != cur_pos:
			_plan_wander(cur_pos, plan, pos_comp, mem, tick_number)
	else:
		# No water visible or remembered -- wander in search of hydration
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number)

## Checks whether pos or any adjacent tile (8 directions) contains drinkable water.
## Returns the coordinate of the drinkable water tile, or Vector2i(-1, -1) if none.
func _find_drinkable_tile_at_or_adjacent(pos: Vector2i) -> Vector2i:
	if not world.is_valid_position(pos):
		return Vector2i(-1, -1)
	if world.signals.has_affordance(pos, _TileAffordance.DRINKABLE) and not world.signals.has_affordance(pos, _TileAffordance.HAZARD_LETHAL):
		return pos
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var adj := Vector2i(pos.x + dx, pos.y + dy)
			if world.is_valid_position(adj):
				if world.signals.has_affordance(adj, _TileAffordance.DRINKABLE) and not world.signals.has_affordance(adj, _TileAffordance.HAZARD_LETHAL):
					return adj
	return Vector2i(-1, -1)

## Finds the best walkable tile from which a creature at from_pos can drink water_pos.
## If water_pos itself is walkable, it is a candidate. If deep/non-walkable, selects
## the closest walkable shore/bank neighbor.
func _find_approach_for_water(water_pos: Vector2i, from_pos: Vector2i) -> Vector2i:
	var best_approach := Vector2i(-1, -1)
	var min_dist: float = INF

	# Check water tile itself if walkable
	if world.signals.has_affordance(water_pos, _TileAffordance.WALKABLE) and not world.signals.has_affordance(water_pos, _TileAffordance.HAZARD_LETHAL):
		best_approach = water_pos
		min_dist = from_pos.distance_to(water_pos)

	# Check all adjacent tiles (shore / riverbank)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var adj := Vector2i(water_pos.x + dx, water_pos.y + dy)
			if not world.is_valid_position(adj):
				continue
			if world.signals.has_affordance(adj, _TileAffordance.WALKABLE) and not world.signals.has_affordance(adj, _TileAffordance.HAZARD_LETHAL):
				var d: float = from_pos.distance_to(adj)
				if d < min_dist:
					min_dist = d
					best_approach = adj

	return best_approach


func _plan_graze(cur_pos: Vector2i, plan: _ActionPlanComponent, mem: _MemoryComponent, tick_number: int) -> void:
	# If current tile has edible grass, stay and graze!
	if world.signals.has_affordance(cur_pos, _TileAffordance.GRAZEABLE):
		plan.clear_path()
		plan.target_tile = cur_pos
		return

	# If already en-route to a valid grazeable target, keep following path
	if not plan.path_queue.is_empty() and world.signals.has_affordance(plan.target_tile, _TileAffordance.GRAZEABLE):
		return

	# Search local area (radius 8) for the best grazeable tile
	var best_tile := Vector2i(-1, -1)
	var best_score: float = -999.0

	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			if not world.is_valid_position(candidate):
				continue
			if not world.signals.has_affordance(candidate, _TileAffordance.WALKABLE):
				continue
			if not world.signals.has_affordance(candidate, _TileAffordance.GRAZEABLE):
				continue

			var dist: float = cur_pos.distance_to(candidate)
			var food_val: float = world.signals.get_signal(_SignalTypes.FOOD_PLANT, candidate)

			# Penalize recently visited/grazed tiles to prevent looping
			var recency_penalty: float = 0.0
			if mem != null and mem.was_recently_at(candidate, 30, tick_number):
				recency_penalty = 0.5

			var score: float = (food_val * 2.0) - (dist * 0.15) - recency_penalty
			if score > best_score:
				best_score = score
				best_tile = candidate

	# Check long-term memory if no food found in immediate view
	if best_tile == Vector2i(-1, -1) and mem != null:
		var remembered_pos := mem.get_closest_landmark(&"pasture", cur_pos)
		if remembered_pos != Vector2i(-1, -1) and world.is_valid_position(remembered_pos):
			best_tile = remembered_pos

	if best_tile != Vector2i(-1, -1):
		plan.target_tile = best_tile
		plan.path_queue = _build_simple_path(cur_pos, best_tile)
		if mem != null:
			mem.remember_landmark(best_tile, &"pasture", 1.0, tick_number)

func _plan_flee(cur_pos: Vector2i, plan: _ActionPlanComponent) -> void:
	var grad: Vector2 = world.signals.get_gradient(_SignalTypes.HAZARD, cur_pos)
	# Flee in opposite direction of hazard gradient
	var flee_dir := Vector2i(-signi(int(grad.x)), -signi(int(grad.y)))
	if flee_dir == Vector2i.ZERO:
		flee_dir = Vector2i(1, 0)

	var target := cur_pos + flee_dir
	if world.is_valid_position(target) and world.signals.has_affordance(target, _TileAffordance.WALKABLE):
		plan.target_tile = target
		plan.path_queue = [target]

func _plan_wander(cur_pos: Vector2i, plan: _ActionPlanComponent, pos_comp: _PositionComponent, mem: _MemoryComponent, tick_number: int) -> void:
	if not plan.path_queue.is_empty():
		return

	# Prefer forward/sideways exploration over 180-degree backtracking
	var candidates: Array[Vector2i] = [
		cur_pos + pos_comp.facing,
		cur_pos + Vector2i(-pos_comp.facing.y, pos_comp.facing.x),
		cur_pos + Vector2i(pos_comp.facing.y, -pos_comp.facing.x),
		cur_pos - pos_comp.facing,
	]

	for next_pos in candidates:
		if world.is_valid_position(next_pos) and world.signals.has_affordance(next_pos, _TileAffordance.WALKABLE):
			if mem != null and mem.was_recently_at(next_pos, 8, tick_number):
				continue
			plan.target_tile = next_pos
			plan.path_queue = [next_pos]
			return

## Simple greedy Bresenham/step line towards target tile.
func _build_simple_path(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur: Vector2i = from_pos
	var max_steps: int = 24

	while cur != to_pos and max_steps > 0:
		max_steps -= 1
		var step := Vector2i.ZERO
		var dx: int = to_pos.x - cur.x
		var dy: int = to_pos.y - cur.y

		if absi(dx) >= absi(dy):
			step.x = signi(dx)
		else:
			step.y = signi(dy)

		var next_pos: Vector2i = cur + step
		if world.is_valid_position(next_pos) and world.signals.has_affordance(next_pos, _TileAffordance.WALKABLE):
			cur = next_pos
			path.append(cur)
		else:
			# Try orthogonal fallback
			var alt_step := Vector2i.ZERO
			if step.x != 0:
				alt_step.y = 1 if dy >= 0 else -1
			else:
				alt_step.x = 1 if dx >= 0 else -1
			var alt_pos: Vector2i = cur + alt_step
			if world.is_valid_position(alt_pos) and world.signals.has_affordance(alt_pos, _TileAffordance.WALKABLE):
				cur = alt_pos
				path.append(cur)
			else:
				break

	return path

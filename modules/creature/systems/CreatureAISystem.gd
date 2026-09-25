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
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _SocialComponent     = preload("res://modules/creature/components/SocialComponent.gd")

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
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")
	var social_store: Dictionary   = reg.get_store(&"SocialComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var pos_comp: _PositionComponent = pos_store.get(eid, null)
		var mind: _MindComponent         = mind_store.get(eid, null)
		var mem: _MemoryComponent        = mem_store.get(eid, null)
		var plan: _ActionPlanComponent   = plan_store.get(eid, null)
		var traits: _TraitComponent      = trait_store.get(eid, null)
		var social: _SocialComponent     = social_store.get(eid, null)

		if pos_comp == null or mind == null or plan == null:
			continue

		var cur_pos: Vector2i = pos_comp.position

		# -------------------------------------------------------------------
		# 1. Environmental Perception via SignalSystem
		# -------------------------------------------------------------------
		var sig_data: Dictionary = world.signals.get_signals_at(cur_pos, 0.01)
		# Merge dynamic social perception flags from SocialSystem
		for k in mind.perceived_signals:
			sig_data[k] = mind.perceived_signals[k]
		mind.perceived_signals = sig_data

		var hazard_sens: float = traits.get_stat_multiplier(&"hazard_sensitivity", 1.0) if traits != null else 1.0
		var hazard: float = sig_data.get(_SignalTypes.HAZARD, 0.0) as float
		if hazard > 0.05:
			mind.fear = clampf(mind.fear + hazard * 0.4 * hazard_sens, 0.0, 1.0)
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
			_MindEmbeddings.Action.ATTACK,
			_MindEmbeddings.Action.EAT,
			_MindEmbeddings.Action.DRINK,
			_MindEmbeddings.Action.REST,
			_MindEmbeddings.Action.MATE,
			_MindEmbeddings.Action.SOCIALIZE,
			_MindEmbeddings.Action.WANDER,
			_MindEmbeddings.Action.IDLE
		]:
			var u: float = _MindEmbeddings.evaluate_utility(mind.drives, sig_data, act, creature.diet)
			if traits != null:
				u = traits.apply_action_weight(act, u)
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
			_MindEmbeddings.Action.EAT:
				_plan_eat(cur_pos, plan, creature, mem, tick_number)

			_MindEmbeddings.Action.DRINK:
				_plan_drink(cur_pos, plan, pos_comp, mem, tick_number)

			_MindEmbeddings.Action.FLEE:
				_plan_flee(cur_pos, plan)

			_MindEmbeddings.Action.WANDER:
				_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind)

			_MindEmbeddings.Action.SOCIALIZE:
				_plan_socialize(cur_pos, plan, eid, pos_comp, mem, social, mind, tick_number)

			_MindEmbeddings.Action.REST:
				_plan_rest(cur_pos, plan, mem, tick_number)

			_MindEmbeddings.Action.ATTACK:
				_plan_attack(cur_pos, plan, pos_comp)

			_MindEmbeddings.Action.MATE:
				_plan_mate(cur_pos, plan, eid, pos_comp, mem, tick_number, social)

			_MindEmbeddings.Action.IDLE:
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


func _has_compatible_food(pos: Vector2i, diet: int) -> bool:
	match diet:
		_DietTypes.Category.HERBIVORE:
			return world.signals.has_affordance(pos, _TileAffordance.HERBIVORE_FOOD)
		_DietTypes.Category.CARNIVORE:
			return world.signals.has_affordance(pos, _TileAffordance.CARNIVORE_FOOD)
		_DietTypes.Category.OMNIVORE:
			return world.signals.has_affordance(pos, _TileAffordance.HERBIVORE_FOOD) or world.signals.has_affordance(pos, _TileAffordance.CARNIVORE_FOOD)
		_:
			return world.signals.has_affordance(pos, _TileAffordance.HERBIVORE_FOOD)

func _get_compatible_food_signal(pos: Vector2i, diet: int) -> float:
	match diet:
		_DietTypes.Category.HERBIVORE:
			return world.signals.get_signal(_SignalTypes.FOOD_PLANT, pos)
		_DietTypes.Category.CARNIVORE:
			return world.signals.get_signal(_SignalTypes.FOOD_MEAT, pos)
		_DietTypes.Category.OMNIVORE:
			return maxf(world.signals.get_signal(_SignalTypes.FOOD_PLANT, pos), world.signals.get_signal(_SignalTypes.FOOD_MEAT, pos))
		_:
			return world.signals.get_signal(_SignalTypes.FOOD_PLANT, pos)

func _plan_eat(cur_pos: Vector2i, plan: _ActionPlanComponent, creature: _CreatureComponent, mem: _MemoryComponent, tick_number: int) -> void:
	# If current tile has compatible food, stay and eat!
	if _has_compatible_food(cur_pos, creature.diet):
		plan.clear_path()
		plan.target_tile = cur_pos
		return

	# If already en-route to a valid food target, keep following path
	if not plan.path_queue.is_empty() and _has_compatible_food(plan.target_tile, creature.diet):
		return

	# Search local area (radius 8) for the best compatible food tile
	var best_tile := Vector2i(-1, -1)
	var best_score: float = -999.0

	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			if not world.is_valid_position(candidate):
				continue
			if not world.signals.has_affordance(candidate, _TileAffordance.WALKABLE):
				continue
			if not _has_compatible_food(candidate, creature.diet):
				continue

			var dist: float = cur_pos.distance_to(candidate)
			var food_val: float = _get_compatible_food_signal(candidate, creature.diet)

			# Penalize recently visited/eaten tiles to prevent looping
			var recency_penalty: float = 0.0
			if mem != null and mem.was_recently_at(candidate, 30, tick_number):
				recency_penalty = 0.5

			var score: float = (food_val * 2.0) - (dist * 0.15) - recency_penalty
			if score > best_score:
				best_score = score
				best_tile = candidate

	var landmark: StringName = &"carrion" if creature.diet == _DietTypes.Category.CARNIVORE else &"pasture"

	# Check long-term memory if no food found in immediate view
	if best_tile == Vector2i(-1, -1) and mem != null:
		var remembered_pos := mem.get_closest_landmark(landmark, cur_pos)
		if remembered_pos != Vector2i(-1, -1) and world.is_valid_position(remembered_pos):
			best_tile = remembered_pos

	if best_tile != Vector2i(-1, -1):
		plan.target_tile = best_tile
		plan.path_queue = _build_simple_path(cur_pos, best_tile)
		if mem != null:
			mem.remember_landmark(best_tile, landmark, 1.0, tick_number)

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

func _plan_wander(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	pos_comp: _PositionComponent,
	mem: _MemoryComponent,
	tick_number: int,
	social: _SocialComponent = null,
	mind: _MindComponent = null
) -> void:
	if not plan.path_queue.is_empty():
		return

	# Prefer forward/sideways exploration over 180-degree backtracking
	var candidates: Array[Vector2i] = [
		cur_pos + pos_comp.facing,
		cur_pos + Vector2i(-pos_comp.facing.y, pos_comp.facing.x),
		cur_pos + Vector2i(pos_comp.facing.y, -pos_comp.facing.x),
		cur_pos - pos_comp.facing,
	]

	var best_tile := Vector2i(-1, -1)
	var best_score: float = -999.0

	for next_pos in candidates:
		if not world.is_valid_position(next_pos) or not world.signals.has_affordance(next_pos, _TileAffordance.WALKABLE):
			continue
		if world.signals.has_affordance(next_pos, _TileAffordance.HAZARD_LETHAL):
			continue
		if world.get_creature_at(next_pos) != -1:
			continue

		var score: float = 0.0

		# Forward momentum
		if next_pos == cur_pos + pos_comp.facing:
			score += 1.0
		elif next_pos == cur_pos - pos_comp.facing:
			score -= 0.5

		# Short-term memory avoidance
		if mem != null and mem.was_recently_at(next_pos, 8, tick_number):
			score -= 3.0

		# Emergent herd cohesion bias
		if social != null and social.herd_centroid != Vector2.ZERO and social.sociality > 0.25:
			var cur_dist_c: float = Vector2(cur_pos).distance_to(social.herd_centroid)
			var next_dist_c: float = Vector2(next_pos).distance_to(social.herd_centroid)
			var soc_drive: float = mind.sociability if mind != null else 0.5

			if next_dist_c < cur_dist_c:
				score += 2.0 * social.sociality * (0.5 + soc_drive * 0.5)
			else:
				if cur_dist_c > float(social.comfort_dist_max):
					score -= 3.0 * social.sociality

			# Juvenile following mother bias
			if social.has_mother():
				var mother_pos = _get_creature_position(social.mother_eid)
				if mother_pos != Vector2i(-1, -1):
					var cur_m_dist: float = Vector2(cur_pos).distance_to(Vector2(mother_pos))
					var next_m_dist: float = Vector2(next_pos).distance_to(Vector2(mother_pos))
					if next_m_dist < cur_m_dist:
						score += 3.5 * social.kinship_tendency

		if score > best_score:
			best_score = score
			best_tile = next_pos

	if best_tile != Vector2i(-1, -1):
		plan.target_tile = best_tile
		plan.path_queue = [best_tile]

func _plan_rest(cur_pos: Vector2i, plan: _ActionPlanComponent, mem: _MemoryComponent, tick_number: int) -> void:
	# 1. If current tile already provides COVER, stay and rest right here!
	if world.signals.has_affordance(cur_pos, _TileAffordance.COVER) and not world.signals.has_affordance(cur_pos, _TileAffordance.HAZARD_LETHAL):
		plan.clear_path()
		plan.target_tile = cur_pos
		return

	# 2. If already en-route to a valid COVER target, keep following path
	if not plan.path_queue.is_empty() and plan.target_tile != Vector2i(-1, -1):
		if world.signals.has_affordance(plan.target_tile, _TileAffordance.COVER) and not world.signals.has_affordance(plan.target_tile, _TileAffordance.HAZARD_LETHAL):
			return

	# 3. Search local area (radius 16) for the best walkable tile with priority affordance of COVER
	var best_cover_tile := Vector2i(-1, -1)
	var best_score: float = -999.0

	for dy in range(-16, 17):
		for dx in range(-16, 17):
			var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			if not world.is_valid_position(candidate):
				continue
			if not world.signals.has_affordance(candidate, _TileAffordance.WALKABLE):
				continue
			if not world.signals.has_affordance(candidate, _TileAffordance.COVER):
				continue
			if world.signals.has_affordance(candidate, _TileAffordance.HAZARD_LETHAL):
				continue

			var dist: float = cur_pos.distance_to(candidate)
			var cover_val: float = world.signals.get_signal(_SignalTypes.COVER, candidate)
			var hazard_val: float = world.signals.get_signal(_SignalTypes.HAZARD, candidate)

			# Prioritize higher cover quality, closer distance, lower hazard
			var score: float = (cover_val * 3.0) - (dist * 0.20) - (hazard_val * 5.0)
			if score > best_score:
				best_score = score
				best_cover_tile = candidate

	# 4. Check long-term memory for remembered shelter / cover landmark if none visible nearby
	if best_cover_tile == Vector2i(-1, -1) and mem != null:
		var remembered_pos := mem.get_closest_landmark(&"shelter", cur_pos)
		if remembered_pos != Vector2i(-1, -1) and world.is_valid_position(remembered_pos):
			if world.signals.has_affordance(remembered_pos, _TileAffordance.COVER) and world.signals.has_affordance(remembered_pos, _TileAffordance.WALKABLE):
				best_cover_tile = remembered_pos

	if best_cover_tile != Vector2i(-1, -1):
		var path = _build_simple_path(cur_pos, best_cover_tile)
		if not path.is_empty():
			plan.target_tile = best_cover_tile
			plan.path_queue = path
			if mem != null:
				mem.remember_landmark(best_cover_tile, &"shelter", 1.0, tick_number)
			return

	# 5. Fallback: No COVER tile found or reachable - rest wherever it currently is!
	plan.clear_path()
	plan.target_tile = cur_pos

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
 
func _plan_attack(cur_pos: Vector2i, plan: _ActionPlanComponent, pos_comp: _PositionComponent) -> void:
	if plan.target_tile != Vector2i(-1, -1) and cur_pos.distance_squared_to(plan.target_tile) <= 2:
		plan.clear_path()
		return
	var facing_pos: Vector2i = cur_pos + pos_comp.facing
	if world.is_valid_position(facing_pos):
		plan.target_tile = facing_pos
		plan.clear_path()

func _plan_mate(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	eid: int,
	pos_comp: _PositionComponent,
	mem: _MemoryComponent,
	tick_number: int,
	social: _SocialComponent = null
) -> void:
	var reg = world.get_registry()
	if reg == null or world.mating_system == null:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social)
		return

	var pos_store: Dictionary = reg.get_store(&"PositionComponent")
	var mating_sys = world.mating_system

	# 1. If currently targeting a valid mate and already adjacent, hold position to mate!
	if plan.target_tile != Vector2i(-1, -1) and cur_pos.distance_squared_to(plan.target_tile) <= 2:
		var target_eid: int = world.get_creature_at(plan.target_tile)
		if target_eid != -1 and mating_sys.can_mate(eid, target_eid):
			plan.clear_path()
			return

	# 2. If en-route to a valid partner, keep following path
	if not plan.path_queue.is_empty() and plan.target_tile != Vector2i(-1, -1):
		var target_eid: int = world.get_creature_at(plan.target_tile)
		if target_eid != -1 and mating_sys.can_mate(eid, target_eid):
			return

	# 3. Search for mating candidates
	var best_candidate: int = -1
	var best_pos := Vector2i(-1, -1)
	var best_score: float = -999.0

	# Pair-Bond Priority: If creature has an alive bonded partner, target them first!
	if social != null and social.has_bonded_partner() and social.is_partner_alive(reg):
		var partner_eid: int = social.bonded_partner_eid
		var partner_pos_c: _PositionComponent = pos_store.get(partner_eid, null)
		if partner_pos_c != null:
			if mating_sys.can_mate(eid, partner_eid):
				best_candidate = partner_eid
				best_pos = partner_pos_c.position
			elif social.monogamy_tendency >= 0.70:
				# High monogamy: refuse to pursue outside suitors; navigate towards partner
				best_candidate = partner_eid
				best_pos = partner_pos_c.position

	if best_candidate == -1:
		for cand_eid: int in pos_store:
			if cand_eid == eid:
				continue

			var cand_pos: Vector2i = pos_store[cand_eid].position
			var dist: float = cur_pos.distance_to(cand_pos)
			if dist > 16.0:
				continue

			if not mating_sys.can_mate(eid, cand_eid):
				continue

			# Trait matching preference score [0.0, 1.0]
			var pref: float = mating_sys.calculate_trait_matching_score(eid, cand_eid)
			# Score balances trait preference and distance
			var score: float = (pref * 3.0) - (dist * 0.10)
			if score > best_score:
				best_score = score
				best_candidate = cand_eid
				best_pos = cand_pos

	# 4. Check long-term memory for remembered mate encounter if none found nearby
	if best_candidate == -1 and mem != null:
		var remembered_mate := mem.get_closest_landmark(&"mate", cur_pos)
		if remembered_mate != Vector2i(-1, -1) and world.is_valid_position(remembered_mate):
			var cand_at_mem: int = world.get_creature_at(remembered_mate)
			if cand_at_mem != -1 and mating_sys.can_mate(eid, cand_at_mem):
				best_candidate = cand_at_mem
				best_pos = remembered_mate

	# 5. Pathfind towards best candidate or wander to search
	if best_candidate != -1 and best_pos != Vector2i(-1, -1):
		plan.target_tile = best_pos
		if cur_pos.distance_squared_to(best_pos) <= 2:
			plan.clear_path()
		else:
			plan.path_queue = _build_simple_path(cur_pos, best_pos)
		if mem != null:
			mem.remember_landmark(best_pos, &"mate", 1.0, tick_number)
	else:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social)

# ---------------------------------------------------------------------------
# Socializing Action Planning
# ---------------------------------------------------------------------------

func _plan_socialize(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	_eid: int,
	pos_comp: _PositionComponent,
	mem: _MemoryComponent,
	social: _SocialComponent,
	mind: _MindComponent,
	tick_number: int
) -> void:
	if social == null:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind)
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var pos_store: Dictionary = reg.get_store(&"PositionComponent")

	# 1. Determine highest priority companion (Partner > Mother > Closest Peer > Centroid)
	var target_eid: int = -1
	var target_pos := Vector2i(-1, -1)

	if social.has_bonded_partner():
		var p_pos = pos_store.get(social.bonded_partner_eid, null)
		if p_pos != null and Vector2(cur_pos).distance_to(Vector2(p_pos.position)) <= float(social.social_radius):
			target_eid = social.bonded_partner_eid
			target_pos = p_pos.position

	if target_eid == -1 and social.has_mother():
		var m_pos = pos_store.get(social.mother_eid, null)
		if m_pos != null and Vector2(cur_pos).distance_to(Vector2(m_pos.position)) <= float(social.social_radius):
			target_eid = social.mother_eid
			target_pos = m_pos.position

	if target_eid == -1 and social.closest_peer_eid != -1:
		var c_pos = pos_store.get(social.closest_peer_eid, null)
		if c_pos != null:
			target_eid = social.closest_peer_eid
			target_pos = c_pos.position

	if target_pos == Vector2i(-1, -1) and social.herd_centroid != Vector2.ZERO:
		target_pos = Vector2i(roundi(social.herd_centroid.x), roundi(social.herd_centroid.y))

	if target_pos == Vector2i(-1, -1):
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind)
		return

	var dist: float = Vector2(cur_pos).distance_to(Vector2(target_pos))

	# 2. If already in intimate social comfort range (1 to comfort_dist_min), stay nearby and face companion
	if dist >= 1.0 and dist <= float(social.comfort_dist_min):
		plan.clear_path()
		var dir_to: Vector2 = (Vector2(target_pos) - Vector2(cur_pos)).normalized()
		pos_comp.facing = Vector2i(roundi(dir_to.x), roundi(dir_to.y))
		return

	# If overlapping on exact same tile, perform separation step
	if dist < 1.0:
		var away_dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		away_dirs.shuffle()
		for d in away_dirs:
			var step: Vector2i = cur_pos + d
			if world.is_valid_position(step) and world.signals.has_affordance(step, _TileAffordance.WALKABLE) and world.get_creature_at(step) == -1:
				plan.target_tile = step
				plan.path_queue = [step]
				return

	# 3. Pathfind toward comfort ring around companion
	var approach_tiles: Array[Vector2i] = _find_approach_tiles_around(target_pos, social.comfort_dist_min)
	if approach_tiles.is_empty():
		approach_tiles = _find_approach_tiles_around(target_pos, 1)

	var best_app := Vector2i(-1, -1)
	var min_app_d: float = 999.0

	for app in approach_tiles:
		if world.is_valid_position(app) and world.signals.has_affordance(app, _TileAffordance.WALKABLE) and world.get_creature_at(app) == -1:
			var d: float = Vector2(cur_pos).distance_to(Vector2(app))
			if d < min_app_d:
				min_app_d = d
				best_app = app

	if best_app != Vector2i(-1, -1):
		plan.target_tile = best_app
		plan.path_queue = _build_simple_path(cur_pos, best_app)
	else:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind)

func _get_creature_position(target_eid: int) -> Vector2i:
	if world == null or target_eid == -1:
		return Vector2i(-1, -1)
	var reg = world.get_registry()
	if reg == null:
		return Vector2i(-1, -1)
	var pos_comp = reg.get_component(target_eid, &"PositionComponent")
	return pos_comp.position if pos_comp != null else Vector2i(-1, -1)

func _find_approach_tiles_around(center: Vector2i, radius: int = 2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if absi(dx) == radius or absi(dy) == radius:
				result.append(center + Vector2i(dx, dy))
	return result


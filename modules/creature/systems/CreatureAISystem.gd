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
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _SignalTypes         = preload("res://modules/signal/data/SignalTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _SocialComponent     = preload("res://modules/creature/components/SocialComponent.gd")
const _MatingComponent     = preload("res://modules/creature/components/MatingComponent.gd")

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
		# Merge dynamic social perception flags from SocialSystem cleanly
		for k in [&"peers_nearby", &"has_bonded_near", &"closest_peer_dist"]:
			if mind.perceived_signals.has(k):
				sig_data[k] = mind.perceived_signals[k]

		var hazard_sens: float = traits.get_stat_multiplier(&"hazard_sensitivity", 1.0) if traits != null else 1.0
		var hazard: float = sig_data.get(_SignalTypes.HAZARD, 0.0) as float

		# Predator / Prey cross-species perception
		if creature.diet == _DietTypes.Category.CARNIVORE:
			var c_data: Dictionary = _CreatureTypes.get_data(creature.species_type)
			var sight_r: float = float(c_data.get("sight_radius", 16.0))
			if traits != null:
				sight_r += float(traits.get_stat_offset(&"sight_radius_mod"))

			var nearby_eids: Array[int] = world.get_creatures_in_radius(cur_pos, sight_r)
			var has_prey_near: bool = false
			var has_prey_adj: bool = false
			for n_eid in nearby_eids:
				if n_eid == eid:
					continue
				var target_c: _CreatureComponent = creature_store.get(n_eid, null)
				if target_c != null and target_c.is_alive and target_c.species_type != creature.species_type:
					var target_pos_comp: _PositionComponent = pos_store.get(n_eid, null)
					if target_pos_comp != null:
						has_prey_near = true
						if cur_pos.distance_squared_to(target_pos_comp.position) <= 2:
							has_prey_adj = true
							break
			sig_data[&"prey_nearby"] = 0.8 if has_prey_near else 0.0
			sig_data[&"prey_adjacent"] = 1.0 if has_prey_adj else 0.0
		else:
			# Herbivores react to predator scent and nearby visual carnivores
			var pred_scent: float = sig_data.get(_SignalTypes.SCENT_PREDATOR, 0.0) as float
			if pred_scent > 0.05:
				hazard = maxf(hazard, pred_scent * 0.75)

			var c_data: Dictionary = _CreatureTypes.get_data(creature.species_type)
			var sight_r: float = float(c_data.get("sight_radius", 10.0))
			if traits != null:
				sight_r += float(traits.get_stat_offset(&"sight_radius_mod"))

			var nearby_eids: Array[int] = world.get_creatures_in_radius(cur_pos, sight_r)
			for n_eid in nearby_eids:
				if n_eid == eid:
					continue
				var other_c: _CreatureComponent = creature_store.get(n_eid, null)
				if other_c != null and other_c.is_alive and other_c.diet == _DietTypes.Category.CARNIVORE:
					var other_pos_c: _PositionComponent = pos_store.get(n_eid, null)
					if other_pos_c != null:
						var d: float = cur_pos.distance_to(other_pos_c.position)
						var prox_threat: float = clampf((sight_r - d) / sight_r, 0.2, 1.0)
						hazard = maxf(hazard, prox_threat)
						sig_data[&"predator_pos"] = other_pos_c.position
						break

		mind.perceived_signals = sig_data

		if hazard > 0.05:
			mind.fear = clampf(mind.fear + hazard * 0.4 * hazard_sens, 0.0, 1.0)
		else:
			mind.fear = maxf(0.0, mind.fear - 0.02)

		# Cooldown tick-downs for search throttling
		if plan.food_search_cooldown > 0:
			plan.food_search_cooldown -= 1
		if plan.water_search_cooldown > 0:
			plan.water_search_cooldown -= 1
		if plan.cover_search_cooldown > 0:
			plan.cover_search_cooldown -= 1

		# Time-slicing: If not in immediate danger and path queue is actively being traversed,
		# stagger utility re-evaluation across 5 frames
		var is_emergency: bool = (hazard > 0.2 or mind.fear > 0.35)
		var is_my_slice: bool = ((eid + tick_number) % 5 == 0)
		if not is_emergency and not is_my_slice and not plan.path_queue.is_empty():
			continue

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

		var can_swim: bool = creature.can_swim or (traits != null and (traits.has_trait(_TraitTypes.Type.SWIMMER) or traits.get_stat_offset(&"can_swim") > 0.0 or traits.get_stat_multiplier(&"can_swim", 0.0) > 0.0))

		# -------------------------------------------------------------------
		# 3. Action Planning & Path Selection
		# -------------------------------------------------------------------
		match best_action:
			_MindEmbeddings.Action.EAT:
				_plan_eat(cur_pos, plan, creature, mem, tick_number, eid, can_swim, pos_comp, mind, traits)

			_MindEmbeddings.Action.DRINK:
				_plan_drink(cur_pos, plan, pos_comp, mem, tick_number, can_swim)

			_MindEmbeddings.Action.FLEE:
				_plan_flee(cur_pos, plan, mind, can_swim)

			_MindEmbeddings.Action.WANDER:
				_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind, can_swim)

			_MindEmbeddings.Action.SOCIALIZE:
				_plan_socialize(cur_pos, plan, eid, pos_comp, mem, social, mind, tick_number, can_swim)

			_MindEmbeddings.Action.REST:
				_plan_rest(cur_pos, plan, mem, tick_number, can_swim)

			_MindEmbeddings.Action.ATTACK:
				_plan_attack(cur_pos, plan, pos_comp, eid)

			_MindEmbeddings.Action.MATE:
				_plan_mate(cur_pos, plan, eid, pos_comp, mem, tick_number, social, can_swim)

			_MindEmbeddings.Action.IDLE:
				plan.clear_path()

## Helper to check whether pos is traversable for walk or swim.
func _is_traversable(pos: Vector2i, can_swim: bool = false) -> bool:
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

func _plan_drink(cur_pos: Vector2i, plan: _ActionPlanComponent, pos_comp: _PositionComponent, mem: _MemoryComponent, tick_number: int, can_swim: bool = false) -> void:
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

	if plan.water_search_cooldown <= 0:
		for dy in range(-16, 17):
			for dx in range(-16, 17):
				var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
				if not world.is_valid_position(candidate):
					continue
				if not world.signals.has_affordance(candidate, _TileAffordance.DRINKABLE):
					continue
				if world.signals.has_affordance(candidate, _TileAffordance.HAZARD_LETHAL):
					continue

				var approach: Vector2i = _find_approach_for_water(candidate, cur_pos, can_swim)
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

		if best_approach == Vector2i(-1, -1):
			plan.water_search_cooldown = 20

	# 4. Check long-term memory if no water found in immediate view
	if best_approach == Vector2i(-1, -1) and mem != null:
		var remembered_water := mem.get_closest_landmark(&"water_source", cur_pos)
		if remembered_water != Vector2i(-1, -1) and world.is_valid_position(remembered_water):
			best_approach = _find_approach_for_water(remembered_water, cur_pos, can_swim)
			best_water = remembered_water

	# 5. Build path to approach tile or wander if no water located
	if best_approach != Vector2i(-1, -1):
		plan.target_tile = best_approach
		plan.path_queue = _build_simple_path(cur_pos, best_approach, can_swim)
		if mem != null:
			mem.remember_landmark(best_water, &"water_source", 1.0, tick_number)
		if plan.path_queue.is_empty() and best_approach != cur_pos:
			_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, null, null, can_swim)
	else:
		# No water visible or remembered -- wander in search of hydration
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, null, null, can_swim)

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

## Finds the best walkable/swimmable tile from which a creature at from_pos can drink water_pos.
func _find_approach_for_water(water_pos: Vector2i, from_pos: Vector2i, can_swim: bool = false) -> Vector2i:
	var best_approach := Vector2i(-1, -1)
	var min_dist: float = INF

	# Check water tile itself if walkable or swimmable
	if _is_traversable(water_pos, can_swim):
		var occ: int = world.get_creature_at(water_pos)
		if occ == -1 or water_pos == from_pos:
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
			if _is_traversable(adj, can_swim):
				var occ: int = world.get_creature_at(adj)
				if occ != -1 and adj != from_pos:
					continue
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

func _plan_eat(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	creature: _CreatureComponent,
	mem: _MemoryComponent,
	tick_number: int,
	eid: int = -1,
	can_swim: bool = false,
	pos_comp: _PositionComponent = null,
	mind: _MindComponent = null,
	traits: _TraitComponent = null
) -> void:
	# If current tile has compatible food, stay and eat!
	if _has_compatible_food(cur_pos, creature.diet):
		plan.clear_path()
		plan.target_tile = cur_pos
		return

	# If carnivore, execute dedicated hunting & prowling pipeline (never freeze!)
	if creature.diet == _DietTypes.Category.CARNIVORE:
		_plan_carnivore_hunt(cur_pos, plan, pos_comp, creature, mem, mind, traits, tick_number, eid, can_swim)
		return

	# Herbivore / Omnivore food planning
	# If already en-route to a valid food target, keep following path
	if not plan.path_queue.is_empty() and _has_compatible_food(plan.target_tile, creature.diet):
		return

	# Search local area (radius 8) for the best compatible food tile
	var best_tile := Vector2i(-1, -1)
	var best_score: float = -999.0

	if plan.food_search_cooldown <= 0:
		for dy in range(-8, 9):
			for dx in range(-8, 9):
				var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
				if not world.is_valid_position(candidate):
					continue
				if not _is_traversable(candidate, can_swim):
					continue
				if not _has_compatible_food(candidate, creature.diet):
					continue
				var occ: int = world.get_creature_at(candidate)
				if occ != -1 and occ != eid:
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

		if best_tile == Vector2i(-1, -1):
			plan.food_search_cooldown = 15

	var landmark: StringName = &"pasture"

	# Check long-term memory if no food found in immediate view
	if best_tile == Vector2i(-1, -1) and mem != null:
		var remembered_pos := mem.get_closest_landmark(landmark, cur_pos)
		if remembered_pos != Vector2i(-1, -1) and world.is_valid_position(remembered_pos):
			best_tile = remembered_pos

	if best_tile != Vector2i(-1, -1):
		plan.target_tile = best_tile
		plan.path_queue = _build_simple_path(cur_pos, best_tile, can_swim)
		if mem != null:
			mem.remember_landmark(best_tile, landmark, 1.0, tick_number)
	else:
		# If no food nearby, actively forage roam instead of freezing in place!
		if plan.path_queue.is_empty() and pos_comp != null:
			var roam_cand := cur_pos + pos_comp.facing * 6
			roam_cand.x = clampi(roam_cand.x, 2, 125)
			roam_cand.y = clampi(roam_cand.y, 2, 125)
			if _is_traversable(roam_cand, can_swim):
				plan.target_tile = roam_cand
				plan.path_queue = _build_simple_path(cur_pos, roam_cand, can_swim)

## Dedicated multi-tiered predator hunting pipeline:
## Tier 1: Target lock tracking & strike execution
## Tier 2: Dynamic visual sight scan across full sight_radius (e.g. 50 tiles)
## Tier 3: Olfactory prey scent tracking
## Tier 4: Memory recall (carrion / grazing pastures)
## Tier 5: Active territory hunting prowl (never freeze on same tile!)
func _plan_carnivore_hunt(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	pos_comp: _PositionComponent,
	creature: _CreatureComponent,
	mem: _MemoryComponent,
	mind: _MindComponent,
	traits: _TraitComponent,
	tick_number: int,
	eid: int,
	can_swim: bool = false
) -> void:
	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var pos_store: Dictionary = reg.get_store(&"PositionComponent")

	# Check adjacent tiles: if fresh carcass or meat exists immediately adjacent, step onto it and feed!
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var adj_tile := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			if world.is_valid_position(adj_tile) and _has_compatible_food(adj_tile, creature.diet):
				var occ: int = world.get_creature_at(adj_tile)
				if occ == -1 or occ == eid:
					plan.target_tile = adj_tile
					plan.target_eid = -1
					plan.path_queue = [adj_tile]
					return

	# Tier 1: Check active target lock on live prey
	if plan.target_eid != -1:
		var target_c: _CreatureComponent = creature_store.get(plan.target_eid, null)
		var target_pos_c: _PositionComponent = pos_store.get(plan.target_eid, null)
		if target_c != null and target_c.is_alive and target_pos_c != null:
			var prey_pos: Vector2i = target_pos_c.position
			plan.target_tile = prey_pos

			# If in attack strike range (adjacent), transition directly to ATTACK
			if cur_pos.distance_squared_to(prey_pos) <= 2:
				plan.path_queue.clear()
				plan.target_tile = prey_pos
				plan.target_eid = plan.target_eid
				plan.current_goal = _MindEmbeddings.Action.ATTACK
				if pos_comp != null and prey_pos != cur_pos:
					pos_comp.facing = prey_pos - cur_pos
				return

			# Continue pursuit; update path if prey moved or path is exhausted
			if plan.path_queue.is_empty() or plan.path_queue.back() != prey_pos:
				plan.path_queue = _build_simple_path(cur_pos, prey_pos, can_swim)
			return
		else:
			# Target was slain or disappeared; unlock
			plan.target_eid = -1

	# Search local area (radius 8) for loose meat / carcass items
	var best_carrion := Vector2i(-1, -1)
	var best_score: float = -999.0
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var candidate := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			if not world.is_valid_position(candidate) or not _is_traversable(candidate, can_swim):
				continue
			if not _has_compatible_food(candidate, creature.diet):
				continue
			var occ: int = world.get_creature_at(candidate)
			if occ != -1 and occ != eid:
				continue
			var dist: float = cur_pos.distance_to(candidate)
			var meat_val: float = _get_compatible_food_signal(candidate, creature.diet)
			var score: float = (meat_val * 2.0) - (dist * 0.15)
			if score > best_score:
				best_score = score
				best_carrion = candidate

	if best_carrion != Vector2i(-1, -1):
		plan.target_tile = best_carrion
		plan.target_eid = -1
		plan.path_queue = _build_simple_path(cur_pos, best_carrion, can_swim)
		return

	# Tier 2: Visual scan for live prey using creature's full sight_radius (e.g. 50 tiles for Wolf!)
	var c_data: Dictionary = _CreatureTypes.get_data(creature.species_type)
	var sight_r: float = float(c_data.get("sight_radius", 16.0))
	if traits != null:
		sight_r += float(traits.get_stat_offset(&"sight_radius_mod"))

	var closest_prey_eid: int = -1
	var closest_prey_pos := Vector2i(-1, -1)
	var min_dist: float = 9999.0

	var candidates: Array[int] = world.get_creatures_in_radius(cur_pos, sight_r)
	for cand_eid in candidates:
		if cand_eid == eid:
			continue
		var cand_c: _CreatureComponent = creature_store.get(cand_eid, null)
		if cand_c == null or not cand_c.is_alive or cand_c.species_type == creature.species_type:
			continue
		var cand_pos_c: _PositionComponent = pos_store.get(cand_eid, null)
		if cand_pos_c == null:
			continue
		var d: float = cur_pos.distance_to(cand_pos_c.position)
		if d < min_dist:
			min_dist = d
			closest_prey_eid = cand_eid
			closest_prey_pos = cand_pos_c.position

	if closest_prey_eid != -1 and closest_prey_pos != Vector2i(-1, -1):
		plan.target_eid = closest_prey_eid
		plan.target_tile = closest_prey_pos

		if cur_pos.distance_squared_to(closest_prey_pos) <= 2:
			plan.path_queue.clear()
			plan.current_goal = _MindEmbeddings.Action.ATTACK
			if pos_comp != null and closest_prey_pos != cur_pos:
				pos_comp.facing = closest_prey_pos - cur_pos
			return

		plan.path_queue = _build_simple_path(cur_pos, closest_prey_pos, can_swim)
		return

	# Tier 3: Olfactory tracking - follow SCENT_PREY gradient
	if world.signals != null:
		var prey_grad: Vector2 = world.signals.get_gradient(_SignalTypes.SCENT_PREY, cur_pos)
		if prey_grad != Vector2.ZERO:
			var scent_step := Vector2i(signi(int(round(prey_grad.x))), signi(int(round(prey_grad.y))))
			var scent_target: Vector2i = cur_pos + scent_step * 6
			scent_target.x = clampi(scent_target.x, 2, 125)
			scent_target.y = clampi(scent_target.y, 2, 125)
			if _is_traversable(scent_target, can_swim):
				plan.target_eid = -1
				plan.target_tile = scent_target
				plan.path_queue = _build_simple_path(cur_pos, scent_target, can_swim)
				return

	# Tier 4: Memory landmark recall (carrion or past herbivore pasture)
	if mem != null:
		var remembered_pos := mem.get_closest_landmark(&"carrion", cur_pos)
		if remembered_pos == Vector2i(-1, -1):
			remembered_pos = mem.get_closest_landmark(&"pasture", cur_pos)
		if remembered_pos != Vector2i(-1, -1) and world.is_valid_position(remembered_pos) and remembered_pos != cur_pos:
			plan.target_eid = -1
			plan.target_tile = remembered_pos
			plan.path_queue = _build_simple_path(cur_pos, remembered_pos, can_swim)
			return

	# Tier 5: Active Hunting Prowl - NEVER FREEZE!
	# If currently pathing a prowl, continue unless reached
	if not plan.path_queue.is_empty() and plan.target_tile != cur_pos:
		return

	# Pick forward-biased hunting prowl target across territory
	var facing_dir: Vector2i = pos_comp.facing if pos_comp != null and pos_comp.facing != Vector2i.ZERO else Vector2i(1, 0)
	var prowl_dirs: Array[Vector2i] = [
		facing_dir,
		Vector2i(-facing_dir.y, facing_dir.x),
		Vector2i(facing_dir.y, -facing_dir.x),
		-facing_dir
	]
	for p_dir in prowl_dirs:
		for dist in [14, 10, 6]:
			var prowl_cand: Vector2i = cur_pos + p_dir * dist
			prowl_cand.x = clampi(prowl_cand.x, 2, 125)
			prowl_cand.y = clampi(prowl_cand.y, 2, 125)
			if _is_traversable(prowl_cand, can_swim) and prowl_cand != cur_pos:
				plan.target_eid = -1
				plan.target_tile = prowl_cand
				plan.path_queue = _build_simple_path(cur_pos, prowl_cand, can_swim)
				return

func _plan_flee(cur_pos: Vector2i, plan: _ActionPlanComponent, mind: _MindComponent = null, can_swim: bool = false) -> void:
	var flee_dir := Vector2i.ZERO
	if mind != null and mind.perceived_signals.has(&"predator_pos"):
		var pred_pos: Vector2i = mind.perceived_signals[&"predator_pos"]
		flee_dir = Vector2i(signi(cur_pos.x - pred_pos.x), signi(cur_pos.y - pred_pos.y))

	if flee_dir == Vector2i.ZERO:
		var grad: Vector2 = world.signals.get_gradient(_SignalTypes.HAZARD, cur_pos)
		if grad == Vector2.ZERO:
			grad = world.signals.get_gradient(_SignalTypes.SCENT_PREDATOR, cur_pos)
		flee_dir = Vector2i(-signi(int(grad.x)), -signi(int(grad.y)))

	if flee_dir == Vector2i.ZERO:
		flee_dir = Vector2i(1, 0)

	var target := cur_pos + flee_dir
	if _is_traversable(target, can_swim):
		plan.target_tile = target
		plan.path_queue = [target]
	else:
		var alts: Array[Vector2i] = [
			cur_pos + Vector2i(-flee_dir.y, flee_dir.x),
			cur_pos + Vector2i(flee_dir.y, -flee_dir.x),
			cur_pos - flee_dir
		]
		for alt in alts:
			if _is_traversable(alt, can_swim):
				plan.target_tile = alt
				plan.path_queue = [alt]
				break

func _plan_wander(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	pos_comp: _PositionComponent,
	mem: _MemoryComponent,
	tick_number: int,
	social: _SocialComponent = null,
	mind: _MindComponent = null,
	can_swim: bool = false
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
		if not _is_traversable(next_pos, can_swim):
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
		var w_path: Array[Vector2i] = [best_tile]
		var step_dir: Vector2i = best_tile - cur_pos
		var walk_p: Vector2i = best_tile
		for _step in range(3):
			var next_w: Vector2i = walk_p + step_dir
			if _is_traversable(next_w, can_swim) and world.get_creature_at(next_w) == -1:
				w_path.append(next_w)
				walk_p = next_w
				plan.target_tile = next_w
			else:
				break
		plan.path_queue = w_path

func _plan_rest(cur_pos: Vector2i, plan: _ActionPlanComponent, mem: _MemoryComponent, tick_number: int, can_swim: bool = false) -> void:
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

	if plan.cover_search_cooldown <= 0:
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
				var occ: int = world.get_creature_at(candidate)
				if occ != -1 and candidate != cur_pos:
					continue

				var dist: float = cur_pos.distance_to(candidate)
				var cover_val: float = world.signals.get_signal(_SignalTypes.COVER, candidate)
				var hazard_val: float = world.signals.get_signal(_SignalTypes.HAZARD, candidate)

				# Prioritize higher cover quality, closer distance, lower hazard
				var score: float = (cover_val * 3.0) - (dist * 0.20) - (hazard_val * 5.0)
				if score > best_score:
					best_score = score
					best_cover_tile = candidate

		if best_cover_tile == Vector2i(-1, -1):
			plan.cover_search_cooldown = 20

	# 4. Check long-term memory for remembered shelter / cover landmark if none visible nearby
	if best_cover_tile == Vector2i(-1, -1) and mem != null:
		var remembered_pos := mem.get_closest_landmark(&"shelter", cur_pos)
		if remembered_pos != Vector2i(-1, -1) and world.is_valid_position(remembered_pos):
			if world.signals.has_affordance(remembered_pos, _TileAffordance.COVER) and world.signals.has_affordance(remembered_pos, _TileAffordance.WALKABLE):
				best_cover_tile = remembered_pos

	if best_cover_tile != Vector2i(-1, -1):
		var path = _build_simple_path(cur_pos, best_cover_tile, can_swim)
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
func _build_simple_path(from_pos: Vector2i, to_pos: Vector2i, can_swim: bool = false) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur: Vector2i = from_pos
	var max_steps: int = 64

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
		var is_next_occupied: bool = (world.get_creature_at(next_pos) != -1 and next_pos != to_pos)

		if not is_next_occupied and _is_traversable(next_pos, can_swim):
			cur = next_pos
			path.append(cur)
		else:
			# Try orthogonal fallbacks (both sides)
			var alt_steps: Array[Vector2i] = []
			if step.x != 0:
				alt_steps.append(Vector2i(0, 1 if dy >= 0 else -1))
				alt_steps.append(Vector2i(0, -1 if dy >= 0 else 1))
			else:
				alt_steps.append(Vector2i(1 if dx >= 0 else -1, 0))
				alt_steps.append(Vector2i(-1 if dx >= 0 else 1, 0))

			var stepped: bool = false
			for alt_s in alt_steps:
				var alt_pos: Vector2i = cur + alt_s
				var is_alt_occupied: bool = (world.get_creature_at(alt_pos) != -1 and alt_pos != to_pos)
				if not is_alt_occupied and _is_traversable(alt_pos, can_swim):
					cur = alt_pos
					path.append(cur)
					stepped = true
					break

			if not stepped:
				break

	return path
 
func _plan_attack(cur_pos: Vector2i, plan: _ActionPlanComponent, pos_comp: _PositionComponent, eid: int = -1) -> void:
	var reg = world.get_registry()
	if reg == null:
		plan.clear_path()
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var pos_store: Dictionary = reg.get_store(&"PositionComponent")

	# 1. If already targeting an adjacent alive creature by target_eid, keep target and face it
	if plan.target_eid != -1:
		var target_c: _CreatureComponent = creature_store.get(plan.target_eid, null)
		var target_pos_c: _PositionComponent = pos_store.get(plan.target_eid, null)
		if target_c != null and target_c.is_alive and target_pos_c != null:
			if cur_pos.distance_squared_to(target_pos_c.position) <= 2:
				plan.target_tile = target_pos_c.position
				plan.path_queue.clear()
				if pos_comp != null:
					var face_dir := target_pos_c.position - cur_pos
					if face_dir != Vector2i.ZERO:
						pos_comp.facing = face_dir
				return

	# 2. If targeting an adjacent tile with an alive creature, keep target and face it
	if plan.target_tile != Vector2i(-1, -1) and cur_pos.distance_squared_to(plan.target_tile) <= 2:
		var target_eid: int = world.get_creature_at(plan.target_tile)
		if target_eid != -1 and target_eid != eid:
			var target_c: _CreatureComponent = creature_store.get(target_eid, null)
			if target_c != null and target_c.is_alive:
				plan.target_eid = target_eid
				plan.path_queue.clear()
				if pos_comp != null:
					var face_dir := plan.target_tile - cur_pos
					if face_dir != Vector2i.ZERO:
						pos_comp.facing = face_dir
				return

	# 3. Check adjacent tiles for any living creature of another species
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var check_pos := Vector2i(cur_pos.x + dx, cur_pos.y + dy)
			var c_eid: int = world.get_creature_at(check_pos)
			if c_eid != -1 and c_eid != eid:
				var other_c: _CreatureComponent = creature_store.get(c_eid, null)
				if other_c != null and other_c.is_alive:
					plan.target_tile = check_pos
					plan.target_eid = c_eid
					plan.path_queue.clear()
					if pos_comp != null:
						pos_comp.facing = Vector2i(dx, dy)
					return

	# 4. No valid living target on adjacent tiles: abort ATTACK cleanly
	plan.clear_path()
	plan.current_goal = _MindEmbeddings.Action.IDLE

func _plan_mate(
	cur_pos: Vector2i,
	plan: _ActionPlanComponent,
	eid: int,
	pos_comp: _PositionComponent,
	mem: _MemoryComponent,
	tick_number: int,
	social: _SocialComponent = null,
	can_swim: bool = false
) -> void:
	var reg = world.get_registry()
	if reg == null or world.mating_system == null:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, null, can_swim)
		return

	var pos_store: Dictionary = reg.get_store(&"PositionComponent")
	var mating_sys = world.mating_system

	# 1. If currently targeting a valid mate and already adjacent, hold position to mate!
	if plan.target_tile != Vector2i(-1, -1) and cur_pos.distance_squared_to(plan.target_tile) <= 2:
		var target_eid: int = world.get_creature_at(plan.target_tile)
		if target_eid != -1 and mating_sys.can_mate(eid, target_eid):
			plan.target_eid = target_eid
			plan.path_queue.clear()
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
		var cand_neighbors: Array[int] = world.get_creatures_in_radius(cur_pos, 16.0)
		var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
		var mating_store: Dictionary = reg.get_store(&"MatingComponent")
		var my_creature: _CreatureComponent = creature_store.get(eid, null)
		var my_mating: _MatingComponent = mating_store.get(eid, null)

		for cand_eid: int in cand_neighbors:
			if cand_eid == eid:
				continue

			# Fast pre-filtering before expensive can_mate / trait matching
			if my_creature != null and my_mating != null:
				var cand_c: _CreatureComponent = creature_store.get(cand_eid, null)
				var cand_m: _MatingComponent = mating_store.get(cand_eid, null)
				if cand_c == null or not cand_c.is_alive or cand_c.species_type != my_creature.species_type:
					continue
				if cand_m == null or cand_m.gender == my_mating.gender:
					continue
				if not cand_m.is_ready_to_mate():
					continue

			var cand_pos_comp: _PositionComponent = pos_store.get(cand_eid, null)
			if cand_pos_comp == null:
				continue
			var cand_pos: Vector2i = cand_pos_comp.position
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
		plan.target_eid = best_candidate
		if cur_pos.distance_squared_to(best_pos) <= 2:
			plan.path_queue.clear()
		else:
			plan.path_queue = _build_simple_path(cur_pos, best_pos, can_swim)
		if mem != null:
			mem.remember_landmark(best_pos, &"mate", 1.0, tick_number)
	else:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, null, can_swim)

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
	tick_number: int,
	can_swim: bool = false
) -> void:
	if social == null:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind, can_swim)
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
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind, can_swim)
		return

	var dist: float = Vector2(cur_pos).distance_to(Vector2(target_pos))

	# 2. If already in intimate social comfort range (1 to comfort_dist_min), stay nearby and face companion
	if dist >= 1.0 and dist <= float(social.comfort_dist_min):
		plan.path_queue.clear()
		var dir_to: Vector2 = (Vector2(target_pos) - Vector2(cur_pos)).normalized()
		pos_comp.facing = Vector2i(roundi(dir_to.x), roundi(dir_to.y))
		return

	# If overlapping on exact same tile, perform separation step
	if dist < 1.0:
		var away_dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		away_dirs.shuffle()
		for d in away_dirs:
			var step: Vector2i = cur_pos + d
			if _is_traversable(step, can_swim) and world.get_creature_at(step) == -1:
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
		if _is_traversable(app, can_swim) and world.get_creature_at(app) == -1:
			var d: float = Vector2(cur_pos).distance_to(Vector2(app))
			if d < min_app_d:
				min_app_d = d
				best_app = app
				if min_app_d <= 1.5:
					break

	if best_app != Vector2i(-1, -1):
		plan.target_tile = best_app
		plan.path_queue = _build_simple_path(cur_pos, best_app, can_swim)
	else:
		_plan_wander(cur_pos, plan, pos_comp, mem, tick_number, social, mind, can_swim)

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


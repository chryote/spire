## CreatureLocomotionSystem.gd
## Priority 235 -- runs after CreatureAISystem (230).
##
## Physical execution layer:
## 1. Steps creatures along their planned waypoints respecting movement cooldowns and mobility.
## 2. Executes physical interactions (e.g. grazing/eating grass, emitting chewing/stepping sounds).
## 3. Updates short-term spatial memory and marks renderer dirty when actors move.
class_name CreatureLocomotionSystem
extends "res://core/SystemBase.gd"

const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _FluidComponent     = preload("res://modules/matter/components/FluidComponent.gd")
const _MaterialTypes      = preload("res://modules/matter/data/MaterialTypes.gd")
const _CreatureTypes      = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureKinematics = preload("res://modules/creature/data/CreatureKinematics.gd")
const _ImpactEventComponent = preload("res://modules/matter/components/ImpactEventComponent.gd")
const _BodyComponent      = preload("res://modules/creature/components/body/BodyComponent.gd")

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
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")
	var plan_store: Dictionary     = reg.get_store(&"ActionPlanComponent")
	var mem_store: Dictionary      = reg.get_store(&"MemoryComponent")
	var trait_store: Dictionary    = reg.get_store(&"TraitComponent")

	var any_moved: bool = false

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var pos_comp: _PositionComponent = pos_store.get(eid, null)
		var mind: _MindComponent         = mind_store.get(eid, null)
		var plan: _ActionPlanComponent   = plan_store.get(eid, null)
		var mem: _MemoryComponent        = mem_store.get(eid, null)
		var traits: _TraitComponent      = trait_store.get(eid, null)

		if pos_comp == null or plan == null:
			continue

		# -------------------------------------------------------------------
		# 1. Step Movement Execution
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
					interval += traits.get_stat_offset(&"move_cooldown")
				if creature.mobility_factor < 0.99:
					interval = int(float(interval) / maxf(0.2, creature.mobility_factor))
				pos_comp.move_cooldown_ticks = maxi(1, interval)

				if mem != null:
					mem.record_event(next_pos, &"stepped", tick_number, 0.5)

				if world.signals != null:
					world.signals.emit_sound(next_pos, 0.1, 1)

		# -------------------------------------------------------------------
		# 2. In-Place Action Execution
		# -------------------------------------------------------------------
		if plan.current_goal == _MindEmbeddings.Action.GRAZE:
			# Check if creature is at target or current tile has grass
			if pos_comp.position == plan.target_tile or plan.path_queue.is_empty():
				_execute_graze(eid, pos_comp.position, creature, mind, mem, plan, tick_number)
		elif plan.current_goal == _MindEmbeddings.Action.DRINK:
			# Check if creature is at target or current tile / adjacent tile has water
			if pos_comp.position == plan.target_tile or plan.path_queue.is_empty():
				_execute_drink(eid, pos_comp.position, pos_comp, creature, mind, mem, plan, tick_number)
		elif plan.current_goal == _MindEmbeddings.Action.REST:
			# Check if creature is at target or resting in place
			if pos_comp.position == plan.target_tile or plan.path_queue.is_empty():
				_execute_rest(eid, pos_comp.position, creature, mind, mem, plan, tick_number)
		elif plan.current_goal == _MindEmbeddings.Action.ATTACK:
			# Check if creature is adjacent to target or in range
			if pos_comp.position.distance_squared_to(plan.target_tile) <= 2 or plan.path_queue.is_empty():
				_execute_attack(eid, pos_comp, creature, mind, plan, traits, tick_number)

	if any_moved:
		world.mark_render_dirty()

func _execute_graze(
	_creature_eid: int,
	pos: Vector2i,
	creature: _CreatureComponent,
	mind: _MindComponent,
	mem: _MemoryComponent,
	plan: _ActionPlanComponent,
	tick_number: int
) -> void:
	var tile_eid: int = world.get_entity_at(pos)
	if tile_eid == -1:
		plan.clear_path()
		return

	var reg = world.get_registry()
	var veg: _VegetationComponent = reg.get_component(tile_eid, &"VegetationComponent")
	var grazed: bool = false
	var water_hydrated: bool = false
	var thirst_quenched: float = 0.0

	# 1. Prefer consuming loose grass items from tile inventory first (clearing yielded ground items)
	var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	if inv != null and not inv.items.is_empty():
		for item_eid: int in inv.items:
			var item: _ItemComponent = reg.get_component(item_eid, &"ItemComponent")
			if item != null and item.item_type == _ItemTypes.Type.GRASS:
				# Check if this grass item holds water material
				if item.get_part_material("water") == _MaterialTypes.Type.WATER:
					water_hydrated = true
					thirst_quenched = 0.20
				else:
					var item_matter = reg.get_component(item_eid, &"MatterComponent")
					if item_matter != null and item_matter.moisture >= 0.7:
						water_hydrated = true
						thirst_quenched = 0.20

				if item.quantity > 1:
					item.quantity -= 1
					_ItemFactory.notify_item_destroyed(item.item_type, 1)
				else:
					inv.remove_item(item_eid)
					world.destroy_entity(item_eid)
				grazed = true
				break

	# 2. Fallback: Graze directly from living vegetation
	if not grazed and veg != null and veg.growth_stage >= 1:
		veg.growth_stage = maxi(0, veg.growth_stage - 1)
		grazed = true
		# Living plant tissue also provides modest hydration
		var tile_matter = reg.get_component(tile_eid, &"MatterComponent")
		if tile_matter != null and tile_matter.moisture >= 0.2:
			water_hydrated = true
			thirst_quenched = 0.10

	if grazed:
		# Replenish stomach and reduce hunger
		creature.stomach_fill = minf(creature.stomach_capacity, creature.stomach_fill + 15.0)
		if mind != null:
			mind.hunger = maxf(0.0, mind.hunger - 0.35)
			if water_hydrated and thirst_quenched > 0.0:
				mind.thirst = maxf(0.0, mind.thirst - thirst_quenched)

		# Emit soft munching sound
		if world.signals != null:
			world.signals.emit_sound(pos, 0.25, 2)

		if mem != null:
			mem.record_event(pos, &"grazed", tick_number, 1.0)
			mem.remember_landmark(pos, &"pasture", 1.0, tick_number)

		plan.clear_path()
		world.mark_render_dirty()
		if water_hydrated:
			print("[Creature] Grazer ate fresh grass (with water) at %s. Hunger: %.2f, Thirst: %.2f." % [
				pos, mind.hunger if mind != null else 0.0, mind.thirst if mind != null else 0.0
			])
		else:
			print("[Creature] Grazer ate grass at %s. Hunger now %.2f." % [pos, mind.hunger if mind != null else 0.0])
	else:
		# Grass was already depleted
		plan.clear_path()

func _execute_drink(
	_creature_eid: int,
	pos: Vector2i,
	pos_comp: _PositionComponent,
	creature: _CreatureComponent,
	mind: _MindComponent,
	mem: _MemoryComponent,
	plan: _ActionPlanComponent,
	tick_number: int
) -> void:
	var water_pos := Vector2i(-1, -1)
	if world.signals != null and world.signals.has_affordance(pos, _TileAffordance.DRINKABLE) and not world.signals.has_affordance(pos, _TileAffordance.HAZARD_LETHAL):
		water_pos = pos
	else:
		var neighbors: Array[Vector2i] = [
			pos + Vector2i(0, -1),
			pos + Vector2i(-1, 0),
			pos + Vector2i(1, 0),
			pos + Vector2i(0, 1),
			pos + Vector2i(-1, -1),
			pos + Vector2i(1, -1),
			pos + Vector2i(-1, 1),
			pos + Vector2i(1, 1),
		]
		for n: Vector2i in neighbors:
			if world.is_valid_position(n):
				if world.signals != null and world.signals.has_affordance(n, _TileAffordance.DRINKABLE) and not world.signals.has_affordance(n, _TileAffordance.HAZARD_LETHAL):
					water_pos = n
					break

	if water_pos == Vector2i(-1, -1):
		# No drinkable water reachable from current location
		plan.clear_path()
		return

	# Face towards the water source
	if pos_comp != null and water_pos != pos:
		var face_dir := Vector2i(signi(water_pos.x - pos.x), signi(water_pos.y - pos.y))
		if face_dir != Vector2i.ZERO:
			pos_comp.facing = face_dir

	# Sip water: deplete fluid volume slightly and wake settled fluid
	var tile_eid: int = world.get_entity_at(water_pos)
	var reg = world.get_registry()
	if reg != null and tile_eid != -1:
		var fluid: _FluidComponent = reg.get_component(tile_eid, &"FluidComponent")
		if fluid != null:
			fluid.volume = maxf(0.0, fluid.volume - 0.02)
			fluid.settled = false

	# Quench creature thirst
	if mind != null:
		mind.thirst = maxf(0.0, mind.thirst - 0.40)

	# Sound & spatial memory
	if world.signals != null:
		world.signals.emit_sound(pos, 0.2, 2)

	if mem != null:
		mem.record_event(pos, &"drank", tick_number, 1.0)
		mem.remember_landmark(water_pos, &"water_source", 1.0, tick_number)

	plan.clear_path()
	world.mark_render_dirty()
	print("[Creature] %s drank water from %s. Thirst now %.2f." % [
		creature.creature_name, water_pos, mind.thirst if mind != null else 0.0
	])

func _execute_rest(
	_creature_eid: int,
	pos: Vector2i,
	creature: _CreatureComponent,
	mind: _MindComponent,
	mem: _MemoryComponent,
	plan: _ActionPlanComponent,
	tick_number: int
) -> void:
	plan.clear_path()
	if mind == null:
		return

	var has_cover: bool = world.signals != null and world.signals.has_affordance(pos, _TileAffordance.COVER)

	# Active resting recovery
	var fatigue_rec: float = 0.04 if has_cover else 0.02
	mind.fatigue = maxf(0.0, mind.fatigue - fatigue_rec)

	if has_cover:
		mind.fear = maxf(0.0, mind.fear - 0.03)
		if mem != null:
			mem.record_event(pos, &"rested", tick_number, 0.8)
			mem.remember_landmark(pos, &"shelter", 1.0, tick_number)
	else:
		if mem != null:
			mem.record_event(pos, &"rested", tick_number, 0.4)

	world.mark_render_dirty()
	if has_cover:
		print("[Creature] %s resting safely under COVER at %s. Fatigue: %.2f." % [
			creature.creature_name, pos, mind.fatigue
		])
	else:
		print("[Creature] %s resting at %s. Fatigue: %.2f." % [
			creature.creature_name, pos, mind.fatigue
		])

## Queues an asynchronous physical impact event (Option B) for a creature against a target entity.
func queue_creature_impact(
	creature_eid: int,
	target_eid: int,
	attack_name: String = "",
	target_velocity: Vector2 = Vector2.ZERO
) -> _ImpactEventComponent:
	if world == null:
		return null
	var reg = world.get_registry()
	if reg == null:
		return null

	var creature: _CreatureComponent = reg.get_component(creature_eid, &"CreatureComponent")
	var pos_comp: _PositionComponent = reg.get_component(creature_eid, &"PositionComponent")
	var body: _BodyComponent         = reg.get_component(creature_eid, &"BodyComponent")
	var traits: _TraitComponent      = reg.get_component(creature_eid, &"TraitComponent")
	if creature == null or body == null:
		return null

	var attacks: Dictionary = _CreatureTypes.get_natural_attacks(creature.species_type)
	if attacks.is_empty():
		return null

	var chosen_attack: String = attack_name
	if chosen_attack == "" or not attacks.has(chosen_attack):
		chosen_attack = attacks.keys()[0]
	var attack_cfg: Dictionary = attacks[chosen_attack]

	var limb_name: String = attack_cfg.get("limb", "head")
	var limb_eid: int = body.limbs.get(limb_name, -1)
	var striker_eid: int = limb_eid if limb_eid != -1 else creature_eid

	var strike_dir := Vector2.RIGHT
	if pos_comp != null and pos_comp.facing != Vector2i.ZERO:
		strike_dir = Vector2(pos_comp.facing)

	var params = _CreatureKinematics.build_attack_impact_params(
		reg,
		creature_eid,
		creature,
		body,
		traits,
		attack_cfg,
		strike_dir,
		target_velocity
	)

	var event = _ImpactEventComponent.new()
	event.target_eid = target_eid
	event.params = params
	event.remove_on_resolve = true
	reg.add(striker_eid, event)

	var cost: float = attack_cfg.get("stamina_cost", 0.15) as float
	creature.stamina = maxf(0.05, creature.stamina - cost)
	if pos_comp != null:
		pos_comp.move_cooldown_ticks = maxi(2, pos_comp.base_move_interval + 1)

	if world.signals != null and pos_comp != null:
		world.signals.emit_sound(pos_comp.position, 0.35, 2)

	return event

func _execute_attack(
	creature_eid: int,
	pos_comp: _PositionComponent,
	creature: _CreatureComponent,
	_mind: _MindComponent,
	plan: _ActionPlanComponent,
	_traits: _TraitComponent,
	_tick_number: int
) -> void:
	var target_pos: Vector2i = plan.target_tile
	if target_pos == Vector2i(-1, -1) or not world.is_valid_position(target_pos):
		plan.clear_path()
		return

	var strike_dir: Vector2i = target_pos - pos_comp.position
	if strike_dir != Vector2i.ZERO:
		pos_comp.facing = strike_dir

	var reg = world.get_registry()
	var effective_target_eid: int = -1

	# Check for creature entity at target tile first
	var pos_store: Dictionary = reg.get_store(&"PositionComponent")
	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	for other_eid: int in creature_store:
		if other_eid == creature_eid:
			continue
		var other_pos = pos_store.get(other_eid, null)
		if other_pos != null and other_pos.position == target_pos:
			effective_target_eid = other_eid
			break

	# Fallback to terrain tile entity
	if effective_target_eid == -1:
		effective_target_eid = world.get_entity_at(target_pos)

	if effective_target_eid == -1:
		plan.clear_path()
		return

	var event = queue_creature_impact(creature_eid, effective_target_eid)
	if event != null:
		plan.clear_path()
		world.mark_render_dirty()
		print("[Creature] %s (eid=%d) queued impact against target_eid=%d (E=%.1f J, form=%d)." % [
			creature.creature_name, creature_eid, effective_target_eid, event.params.kinetic_energy, event.params.form
		])
	else:
		plan.clear_path()



## CreatureAbilitySystem.gd
## Priority 240 -- runs immediately after CreatureLocomotionSystem (235).
##
## Wraps and executes all tangible creature abilities, skills, and in-place actions:
## - EAT: Consumes compatible food matter (living vegetation, meat/plant inventory items) based on diet
## - DRINK: Sips drinkable water from current or adjacent water sources
## - REST: Recovers fatigue, leveraging natural cover or shelter
## - ATTACK: Resolves physical impacts, kinetic energy, and natural attacks via CreatureKinematics
class_name CreatureAbilitySystem
extends "res://core/SystemBase.gd"

const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindEmbeddings      = preload("res://modules/creature/data/MindEmbeddings.gd")
const _VegetationComponent = preload("res://modules/vegetation/components/VegetationComponent.gd")
const _FluidComponent      = preload("res://modules/matter/components/FluidComponent.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")
const _InventoryComponent  = preload("res://modules/item/components/InventoryComponent.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _MaterialTypes       = preload("res://modules/matter/data/MaterialTypes.gd")
const _DietTypes           = preload("res://modules/matter/data/DietTypes.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")
const _ImpactEventComponent = preload("res://modules/matter/components/ImpactEventComponent.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureKinematics  = preload("res://modules/creature/data/CreatureKinematics.gd")

func initialize() -> void:
	print("[CreatureAbilitySystem] Initialized. Priority 240.")

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
		# Action / Ability Execution when in position or stationary
		# -------------------------------------------------------------------
		match plan.current_goal:
			_MindEmbeddings.Action.EAT:
				if pos_comp.position == plan.target_tile or plan.path_queue.is_empty():
					_execute_eat(eid, pos_comp.position, creature, mind, mem, plan, tick_number)

			_MindEmbeddings.Action.DRINK:
				if pos_comp.position == plan.target_tile or plan.path_queue.is_empty():
					_execute_drink(eid, pos_comp.position, pos_comp, creature, mind, mem, plan, tick_number)

			_MindEmbeddings.Action.REST:
				if pos_comp.position == plan.target_tile or plan.path_queue.is_empty():
					_execute_rest(eid, pos_comp.position, creature, mind, mem, plan, tick_number)

			_MindEmbeddings.Action.ATTACK:
				if pos_comp.position.distance_squared_to(plan.target_tile) <= 2 or plan.path_queue.is_empty():
					_execute_attack(eid, pos_comp, creature, mind, plan, traits, tick_number)

			_MindEmbeddings.Action.MATE:
				if pos_comp.position.distance_squared_to(plan.target_tile) <= 2 or plan.path_queue.is_empty():
					_execute_mate(eid, pos_comp.position, plan.target_tile, pos_comp, creature, mind, mem, plan, tick_number)

func _execute_eat(
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
	var eaten: bool = false
	var water_hydrated: bool = false
	var thirst_quenched: float = 0.0
	var food_name: String = "food"

	# 1. Prefer consuming loose food items from tile inventory matching creature diet
	var inv: _InventoryComponent = reg.get_component(tile_eid, &"InventoryComponent")
	if inv != null and not inv.items.is_empty():
		for item_eid: int in inv.items:
			var item: _ItemComponent = reg.get_component(item_eid, &"ItemComponent")
			if item == null:
				continue

			var mat_cat: int = _MaterialTypes.get_diet_category(item.material_type)
			if _DietTypes.can_creature_eat(creature.diet, mat_cat):
				food_name = item.display_name if item.display_name != "" else _MaterialTypes.get_display_name(item.material_type)
				var mat_data: Dictionary = _MaterialTypes.get_data(item.material_type)
				var cal: int = mat_data.get("nutritional_value", 10) as int

				# Hydration from item water part or moisture
				if item.get_part_material("water") == _MaterialTypes.Type.WATER:
					water_hydrated = true
					thirst_quenched = 0.20
				else:
					var item_matter = reg.get_component(item_eid, &"MatterComponent")
					if item_matter != null and item_matter.moisture >= 0.7:
						water_hydrated = true
						thirst_quenched = 0.20

				# Satiate based on calories/kg
				var fill: float = clampf(float(cal) * 0.15, 8.0, 30.0)
				creature.stomach_fill = minf(creature.stomach_capacity, creature.stomach_fill + fill)
				if mind != null:
					var hunger_reduction: float = clampf(float(cal) / 100.0 * 0.20, 0.20, 0.50)
					mind.hunger = maxf(0.0, mind.hunger - hunger_reduction)
					if water_hydrated and thirst_quenched > 0.0:
						mind.thirst = maxf(0.0, mind.thirst - thirst_quenched)

				if item.quantity > 1:
					item.quantity -= 1
					_ItemFactory.notify_item_destroyed(item.item_type, 1)
				else:
					inv.remove_item(item_eid)
					world.destroy_entity(item_eid)
				eaten = true
				break

	# 2. Fallback: Graze directly from living vegetation (herbivore/omnivore)
	if not eaten and _DietTypes.can_creature_eat(creature.diet, _DietTypes.Category.HERBIVORE):
		var veg: _VegetationComponent = reg.get_component(tile_eid, &"VegetationComponent")
		if veg != null and veg.growth_stage >= 1:
			veg.growth_stage = maxi(0, veg.growth_stage - 1)
			eaten = true
			food_name = "fresh grass"

			var tile_matter = reg.get_component(tile_eid, &"MatterComponent")
			if tile_matter != null and tile_matter.moisture >= 0.2:
				water_hydrated = true
				thirst_quenched = 0.10

			creature.stomach_fill = minf(creature.stomach_capacity, creature.stomach_fill + 15.0)
			if mind != null:
				mind.hunger = maxf(0.0, mind.hunger - 0.35)
				if water_hydrated and thirst_quenched > 0.0:
					mind.thirst = maxf(0.0, mind.thirst - thirst_quenched)

	if eaten:
		if world.signals != null:
			world.signals.emit_sound(pos, 0.25, 2)

		var landmark: StringName = &"carrion" if creature.diet == _DietTypes.Category.CARNIVORE else &"pasture"
		if mem != null:
			mem.record_event(pos, &"ate", tick_number, 1.0)
			mem.record_event(pos, &"grazed", tick_number, 1.0) # alias for backward compatibility
			mem.remember_landmark(pos, landmark, 1.0, tick_number)

		plan.clear_path()
		world.mark_render_dirty()
		if water_hydrated:
			print("[Creature] %s ate %s (with water) at %s. Hunger: %.2f, Thirst: %.2f." % [
				creature.creature_name, food_name, pos, mind.hunger if mind != null else 0.0, mind.thirst if mind != null else 0.0
			])
		else:
			print("[Creature] %s ate %s at %s. Hunger now %.2f." % [
				creature.creature_name, food_name, pos, mind.hunger if mind != null else 0.0
			])
	else:
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
		plan.clear_path()
		return

	if pos_comp != null and water_pos != pos:
		var face_dir := Vector2i(signi(water_pos.x - pos.x), signi(water_pos.y - pos.y))
		if face_dir != Vector2i.ZERO:
			pos_comp.facing = face_dir

	var tile_eid: int = world.get_entity_at(water_pos)
	var reg = world.get_registry()
	if reg != null and tile_eid != -1:
		var fluid: _FluidComponent = reg.get_component(tile_eid, &"FluidComponent")
		if fluid != null:
			fluid.volume = maxf(0.0, fluid.volume - 0.02)
			fluid.settled = false

	if mind != null:
		mind.thirst = maxf(0.0, mind.thirst - 0.40)

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

func _execute_mate(
	eid: int,
	pos: Vector2i,
	target_pos: Vector2i,
	pos_comp: _PositionComponent,
	creature: _CreatureComponent,
	mind: _MindComponent,
	mem: _MemoryComponent,
	plan: _ActionPlanComponent,
	tick_number: int
) -> void:
	if world == null or world.mating_system == null:
		plan.clear_path()
		return

	if target_pos != pos and pos_comp != null:
		var face_dir := Vector2i(signi(target_pos.x - pos.x), signi(target_pos.y - pos.y))
		if face_dir != Vector2i.ZERO:
			pos_comp.facing = face_dir

	var partner_eid: int = world.get_creature_at(target_pos)
	if partner_eid == -1:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var check_pos := Vector2i(pos.x + dx, pos.y + dy)
				var c_eid: int = world.get_creature_at(check_pos)
				if c_eid != -1 and c_eid != eid and world.mating_system.can_mate(eid, c_eid):
					partner_eid = c_eid
					break
			if partner_eid != -1:
				break

	if partner_eid == -1:
		plan.clear_path()
		return

	var success: bool = world.mating_system.attempt_mating(eid, partner_eid)
	plan.clear_path()
	if success:
		world.mark_render_dirty()

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

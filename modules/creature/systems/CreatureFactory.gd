## CreatureFactory.gd
## Stateless factory utility for instantiating complete data-driven creatures.
## Assembles the physical anatomy (composite limbs, organs, blood) as discrete
## item/matter entities and initializes the creature's cognitive mind and utility AI.
class_name CreatureFactory
extends RefCounted

const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MindComponent       = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MemoryComponent     = preload("res://modules/creature/components/mind/MemoryComponent.gd")
const _ActionPlanComponent = preload("res://modules/creature/components/mind/ActionPlanComponent.gd")
const _RenderComponent     = preload("res://modules/rendering/components/RenderComponent.gd")
const _ItemFactory         = preload("res://modules/item/systems/ItemFactory.gd")
const _ItemTypes           = preload("res://modules/item/data/ItemTypes.gd")

## Instantiates a creature entity and its physical anatomical sub-entities.
static func create(
	world: Node,
	species_type: int,
	spawn_pos: Vector2i,
	name_override: String = ""
) -> int:
	if world == null:
		return -1

	var spec_data: Dictionary = _CreatureTypes.get_data(species_type)
	var creature_eid: int = world.create_entity()

	# 1. Creature Core Component
	var creature_comp := _CreatureComponent.new()
	creature_comp.species_type = species_type
	creature_comp.creature_name = name_override if name_override != "" else spec_data.get("display_name", "Creature")
	creature_comp.stomach_capacity = spec_data.get("stomach_capacity", 50.0)
	creature_comp.stomach_fill = creature_comp.stomach_capacity * 0.4
	world.add_component(creature_eid, creature_comp)

	# 2. Position Component
	var pos_comp := _PositionComponent.new()
	pos_comp.position = spawn_pos
	pos_comp.base_move_interval = spec_data.get("move_cooldown", 2)
	pos_comp.move_cooldown_ticks = 0
	world.add_component(creature_eid, pos_comp)

	# 3. Physical Body & Anatomy Component (Limbs, Organs, Blood)
	var body_comp := _BodyComponent.new()
	body_comp.blood_volume = spec_data.get("blood_volume", 2.5)
	body_comp.max_blood_volume = body_comp.blood_volume

	var anatomy: Dictionary = spec_data.get("anatomy", {})
	var limbs_cfg: Dictionary = anatomy.get("limbs", {})
	for limb_name: String in limbs_cfg:
		var cfg: Dictionary = limbs_cfg[limb_name]
		var limb_eid: int = _ItemFactory.create_composite(world, _ItemTypes.Type.LIMB, {
			"flesh": cfg.get("flesh", 12),
			"bone":  cfg.get("bone",  21),
		})
		var limb_item = world.get_component(limb_eid, &"ItemComponent")
		if limb_item != null:
			limb_item.container_id = creature_eid
			limb_item.display_name = "%s's %s" % [creature_comp.creature_name, limb_name.capitalize()]
		body_comp.limbs[limb_name] = limb_eid

	var organs_cfg: Dictionary = anatomy.get("organs", {})
	for organ_name: String in organs_cfg:
		var cfg: Dictionary = organs_cfg[organ_name]
		var organ_eid: int = _ItemFactory.create(world, _ItemTypes.Type.ORGAN, cfg.get("matter", 12))
		var organ_item = world.get_component(organ_eid, &"ItemComponent")
		if organ_item != null:
			organ_item.container_id = creature_eid
			organ_item.display_name = "%s's %s" % [creature_comp.creature_name, organ_name.capitalize()]
		body_comp.organs[organ_name] = organ_eid

	world.add_component(creature_eid, body_comp)

	# 4. Cognitive Mind Component
	var mind_comp := _MindComponent.new()
	world.add_component(creature_eid, mind_comp)

	# 5. Spatial Memory Component
	var mem_comp := _MemoryComponent.new()
	world.add_component(creature_eid, mem_comp)

	# 6. Action Plan Component
	var plan_comp := _ActionPlanComponent.new()
	world.add_component(creature_eid, plan_comp)

	# 7. Render Component (ASCII glyph & color)
	var render_comp := _RenderComponent.new()
	render_comp.glyph = spec_data.get("glyph", "c")
	render_comp.fg_color = spec_data.get("fg_color", Color.WHITE)
	render_comp.bg_color = spec_data.get("bg_color", Color.BLACK)
	render_comp.z_layer = 10  # Drawn on top of terrain
	world.add_component(creature_eid, render_comp)

	return creature_eid

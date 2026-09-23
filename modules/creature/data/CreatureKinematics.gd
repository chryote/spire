## CreatureKinematics.gd
## Biomechanical force, momentum, and kinetic energy calculator for creatures.
## Translates creature anatomical mass, limb leverage, velocity, stamina,
## and genetic traits into standard ImpactParams for ImpactSolverSystem.
class_name CreatureKinematics
extends RefCounted

const _ImpactTypes   = preload("res://modules/matter/data/ImpactTypes.gd")
const _CreatureTypes = preload("res://modules/creature/data/CreatureTypes.gd")

## Computes ImpactParams for a creature physical action.
## Differentiates fast shallow blows (low backing mass, tiny energy pool, high slash sharpness)
## from fast deep blows (high backing mass, deep piercing momentum, large kinetic energy pool).
static func build_attack_impact_params(
	reg,
	_creature_eid: int,
	creature_comp,
	body_comp,
	traits_comp,
	attack_cfg: Dictionary,
	strike_dir: Vector2 = Vector2.RIGHT,
	target_velocity: Vector2 = Vector2.ZERO
) -> _ImpactTypes.ImpactParams:
	var total_mass: float = 20.0
	if body_comp != null:
		total_mass = body_comp.get_total_mass(reg)

	var limb_name: String = attack_cfg.get("limb", "head")
	var limb_eid: int = -1
	if body_comp != null:
		limb_eid = body_comp.limbs.get(limb_name, -1)

	var limb_mass: float = 0.5
	if reg != null and limb_eid != -1 and reg.has(limb_eid, &"ItemComponent"):
		var limb_item = reg.get_component(limb_eid, &"ItemComponent")
		if limb_item != null:
			limb_mass = limb_item.total_mass

	# 1. Effective Striking Mass (Limb Mass + committed Body Mass)
	# In a slash/scratch, only the distal paw/edge engages in cutting, whereas in blunt/pierce/crush
	# the entire limb mass and committed body weight drive forward through the target.
	var mass_ratio: float = attack_cfg.get("mass_ratio", 0.20) as float
	var limb_engagement: float = 0.25 if (attack_cfg.get("form", _ImpactTypes.Form.BLUNT) as int) == _ImpactTypes.Form.SLASH else 1.0
	var effective_mass: float = maxf(0.05, (limb_mass * limb_engagement) + (total_mass * mass_ratio))

	# 2. Strike Velocity & Relative Velocity
	var base_speed: float = 4.0  # m/s reference strike speed
	var speed_mult: float = attack_cfg.get("velocity_mult", 1.0) as float
	var mobility: float = creature_comp.mobility_factor if creature_comp != null else 1.0
	var trait_speed: float = traits_comp.get_stat_multiplier(&"attack_speed_mult", 1.0) if traits_comp != null else 1.0
	var final_speed: float = base_speed * speed_mult * maxf(0.2, mobility) * trait_speed

	var dir: Vector2 = strike_dir.normalized() if strike_dir != Vector2.ZERO else Vector2.RIGHT
	var strike_velocity: Vector2 = dir * final_speed
	var rel_velocity: Vector2 = strike_velocity - target_velocity
	var rel_speed: float = rel_velocity.length()

	# 3. Kinetic Energy modulated by stamina and strength traits
	var stamina_eff: float = clampf(creature_comp.stamina, 0.20, 1.0) if creature_comp != null else 1.0
	var trait_strength: float = traits_comp.get_stat_multiplier(&"strength_mult", 1.0) if traits_comp != null else 1.0
	var raw_energy: float = 0.5 * effective_mass * (rel_speed * rel_speed) * stamina_eff * trait_strength
	var energy: float = maxf(0.1, raw_energy)

	# 4. Construct ImpactParams
	var params = _ImpactTypes.ImpactParams.new()
	params.mass = effective_mass
	params.velocity = rel_velocity
	params.kinetic_energy = energy
	params.contact_area = maxf(0.00001, attack_cfg.get("contact_area", 0.005) as float)
	params.form = attack_cfg.get("form", _ImpactTypes.Form.BLUNT) as int
	params.sharpness = maxf(0.1, attack_cfg.get("sharpness", 1.0) as float)
	params.temperature_c = body_comp.body_temperature_c if body_comp != null else 38.0
	params.striker_material_id = attack_cfg.get("striking_material", -1) as int

	return params

## Estimates the nominal contact force in Newtons (F = W / d_ref * form_mult * sharpness).
static func estimate_contact_force(energy: float, form: int = 0, sharpness: float = 1.0) -> float:
	var depth_ref: float = 0.02  # 2cm reference deceleration distance
	var form_mult: float = 1.0
	match form:
		_ImpactTypes.Form.PIERCE:     form_mult = 2.4
		_ImpactTypes.Form.SLASH:      form_mult = 1.6
		_ImpactTypes.Form.BLUNT:      form_mult = 1.0
		_ImpactTypes.Form.CRUSH:      form_mult = 1.3
		_ImpactTypes.Form.PROJECTILE: form_mult = 2.0
	return (energy / depth_ref) * form_mult * sharpness

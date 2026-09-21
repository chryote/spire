## ImpactSolverSystem.gd
## Priority 165 -- runs between Combustion (160) and Fluid (170).
##
## Universal Collision & Impact Solver System for the Matter module.
## Provides:
##   1. Direct Pure Solver: ImpactSolverSystem.solve_impact(striker_matter, target_matter, params)
##      Usable anywhere (creature combat, claw vs door, tool vs rock, physics simulations).
##   2. ECS Entity Resolver: resolve_entity_impact(striker_eid, target_eid, params)
##      Mutates ECS state, applies structural damage, emits sound signals, spawns fire/contaminants.
##   3. Queued Tick Processing: processes entities holding ImpactEventComponent each tick.
class_name ImpactSolverSystem
extends "res://core/SystemBase.gd"

const _ImpactTypes          = preload("res://modules/matter/data/ImpactTypes.gd")
const _MaterialTypes        = preload("res://modules/matter/data/MaterialTypes.gd")
const _MatterComponent      = preload("res://modules/matter/components/MatterComponent.gd")
const _BurningComponent     = preload("res://modules/matter/components/BurningComponent.gd")
const _ContaminantComponent = preload("res://modules/matter/components/ContaminantComponent.gd")
const _FluidComponent       = preload("res://modules/matter/components/FluidComponent.gd")
const _TileTypes            = preload("res://modules/terrain/data/TileTypes.gd")
const _ItemTypes            = preload("res://modules/item/data/ItemTypes.gd")

func initialize() -> void:
	print("[ImpactSolverSystem] Initialized. Priority 165.")

# ===========================================================================
# 1. Direct Pure Solver API
# ===========================================================================

## Solves physical collision mechanics between any two MatterComponent instances.
## Pure function: does NOT mutate ECS world directly; returns a comprehensive ImpactResult.
static func solve_impact(
	striker,
	target,
	params: _ImpactTypes.ImpactParams
) -> _ImpactTypes.ImpactResult:
	var result = _ImpactTypes.ImpactResult.new()

	if striker == null or target == null or params == null:
		result.summary = "Invalid collision: missing striker, target, or parameters."
		return result

	# Ensure kinetic energy is consistent with motion
	var energy: float = params.kinetic_energy
	if energy <= 0.0 and params.velocity.length_squared() > 0.0:
		energy = 0.5 * params.mass * params.velocity.length_squared()
	energy = maxf(0.1, energy)

	var s_state: int = striker.state
	var t_state: int = target.state

	# Route to state-pair solvers
	if s_state == 0 and t_state == 0:
		_solve_solid_vs_solid(striker, target, params, energy, result)
	elif s_state == 0 and t_state == 1:
		_solve_solid_vs_liquid(striker, target, params, energy, result)
	elif s_state == 1 and t_state == 0:
		_solve_liquid_vs_solid(striker, target, params, energy, result)
	elif s_state == 0 and t_state == 2:
		_solve_solid_vs_gas(striker, target, params, energy, result)
	elif s_state == 2 and t_state == 0:
		_solve_gas_vs_solid(striker, target, params, energy, result)
	elif s_state == 1 and t_state == 1:
		_solve_liquid_vs_liquid(striker, target, params, energy, result)
	elif t_state == 3 or s_state == 3:
		_solve_colloid_interaction(striker, target, params, energy, result)
	else:
		_solve_generic_fluid(striker, target, params, energy, result)

	return result

## Convenience helper resolving collision using MaterialTypes archetype IDs.
static func solve_material_impact(
	striker_mat_id: int,
	target_mat_id: int,
	params: _ImpactTypes.ImpactParams
) -> _ImpactTypes.ImpactResult:
	var s_mat = _MatterComponent.new()
	_MaterialTypes.apply_to(s_mat, striker_mat_id)
	var t_mat = _MatterComponent.new()
	_MaterialTypes.apply_to(t_mat, target_mat_id)
	return solve_impact(s_mat, t_mat, params)

# ===========================================================================
# 2. Physics Solvers per State Pair
# ===========================================================================

## SOLID vs. SOLID (e.g. Iron Claw vs Wooden Door, Steel vs Steel, Obsidian vs Armor)
static func _solve_solid_vs_solid(
	s,
	t,
	params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	var area: float = maxf(0.00001, params.contact_area)
	var depth_ref: float = 0.02  # 2cm reference deceleration distance
	var form_mult: float = 1.0

	match params.form:
		_ImpactTypes.Form.PIERCE:
			form_mult = 2.4
			area *= 0.5
		_ImpactTypes.Form.SLASH:
			form_mult = 1.6
			area *= 0.8
		_ImpactTypes.Form.BLUNT:
			form_mult = 1.0
			area = maxf(area, 0.005)
		_ImpactTypes.Form.CRUSH:
			form_mult = 1.3
			area = maxf(area, 0.02)
		_ImpactTypes.Form.PROJECTILE:
			form_mult = 2.0
			area *= 0.6

	# Effective nominal pressure in MPa (N / mm^2)
	# Pressure = (Energy / depth) / Area / 1,000,000
	var base_pressure: float = (energy / (depth_ref * area * 1_000_000.0)) * form_mult * params.sharpness

	# Hardness advantage scaling (Mohs scale scratch & penetration factor)
	var s_hard: float = maxf(0.1, s.hardness)
	var t_hard: float = maxf(0.1, t.hardness)
	var hard_ratio: float = s_hard / t_hard

	var target_stress: float
	var striker_stress: float

	if hard_ratio >= 1.0:
		# Striker is harder than target: penetrates deeper, target suffers focused stress
		var bite_factor: float = pow(clampf(hard_ratio, 1.0, 5.0), 1.35)
		target_stress = base_pressure * bite_factor
		striker_stress = base_pressure / bite_factor
	else:
		# Target is harder than striker: striker blunts or glances off, stress reflects back
		var blunt_factor: float = pow(clampf(1.0 / hard_ratio, 1.0, 5.0), 1.2)
		target_stress = base_pressure / blunt_factor
		striker_stress = base_pressure * blunt_factor

	# Yield & Structural Failure Evaluation
	var t_yield: float = maxf(0.1, t.yield_strength)
	var s_yield: float = maxf(0.1, s.yield_strength)

	# Damage calculation
	if target_stress > t_yield:
		var excess_ratio = (target_stress - t_yield) / t_yield
		res.damage_to_target = excess_ratio * minf(energy * 0.4, t_yield * 2.0)
		if target_stress > t_yield * 1.5 or res.damage_to_target >= t_yield:
			res.target_fractured = true

	if striker_stress > s_yield:
		var excess_ratio_s = (striker_stress - s_yield) / s_yield
		res.damage_to_striker = excess_ratio_s * minf(energy * 0.3, s_yield * 2.0)
		if striker_stress > s_yield * 1.5 or res.damage_to_striker >= s_yield:
			res.striker_fractured = true

	# Restitution & Rebound
	var eff_elasticity: float = clampf(s.elasticity * t.elasticity, 0.0, 0.95)
	if res.target_fractured or res.striker_fractured:
		eff_elasticity *= 0.15  # energy dissipated into fracturing

	res.rebound_energy = energy * (eff_elasticity * eff_elasticity)
	res.energy_absorbed = maxf(0.0, energy - res.rebound_energy)

	if params.velocity.length_squared() > 0.0:
		res.rebound_velocity = -params.velocity * eff_elasticity
	else:
		res.rebound_velocity = Vector2.UP * sqrt(2.0 * res.rebound_energy / maxf(0.01, params.mass))

	# Determine outcome enum
	if res.target_fractured:
		if params.form in [_ImpactTypes.Form.PIERCE, _ImpactTypes.Form.SLASH]:
			res.outcome = _ImpactTypes.Outcome.PENETRATED
		else:
			res.outcome = _ImpactTypes.Outcome.SHATTERED
		res.penetration_depth = 1.0
	elif res.striker_fractured:
		res.outcome = _ImpactTypes.Outcome.SHATTERED
	elif res.damage_to_target > 0.0:
		res.outcome = _ImpactTypes.Outcome.DEFORMED
		res.penetration_depth = clampf(target_stress / (t_yield * 3.0), 0.05, 0.8)
	else:
		res.outcome = _ImpactTypes.Outcome.DEFLECTED
		res.penetration_depth = 0.0

	# Friction, Heat & Incandescent Sparks
	var dissipated_heat: float = res.energy_absorbed * 0.7
	var thermal_mass: float = maxf(0.1, params.mass) * maxf(100.0, t.specific_heat)
	res.heat_generated_c = clampf((dissipated_heat / thermal_mass) * 1000.0, 0.0, 600.0)

	# Sparks occur when hard solids (H >= 5.0, e.g. steel vs steel/stone) collide with enough energy
	if s_hard >= 5.0 and t_hard >= 5.0 and energy >= 35.0:
		res.sparks_produced = true

	# Thermal auto-ignition check
	var effective_temp: float = maxf(s.temperature_c, t.temperature_c) + res.heat_generated_c
	if res.sparks_produced:
		effective_temp = maxf(effective_temp, 350.0)

	if t.ignition_temp_c < INF and t.flammability > 0.05:
		if effective_temp >= t.ignition_temp_c:
			res.ignition_occurred = true

	# Exotic Destabilization (Icosidodecahedron)
	if t.material_id == _MaterialTypes.Type.ICOSIDODECAHEDRON and energy >= 30.0:
		res.sparks_produced = true
		res.ignition_occurred = true
		res.target_fractured = true
		res.sound_loudness = 1.0
		res.summary = "Icosidodecahedron destabilized violently under kinetic impact!"
		return

	# Acoustic sound loudness (0.0 to 1.0)
	var max_h: float = maxf(s_hard, t_hard)
	res.sound_loudness = clampf((log(1.0 + res.energy_absorbed) / 5.5) * (max_h / 8.0 + 0.35), 0.1, 1.0)

	# Contaminant transfer on cutting / piercing / damaging impact
	if res.damage_to_target > 0.0 or res.penetration_depth > 0.0:
		if s.toxicity > 0.0:
			res.contaminants_transferred["toxicity"] = s.toxicity
			res.contaminants_transferred["source_mat_id"] = s.material_id
		if s.corrosiveness > 0.0:
			res.contaminants_transferred["corrosion"] = s.corrosiveness
			res.contaminants_transferred["source_mat_id"] = s.material_id

	# Debris material assignment
	if res.target_fractured:
		res.debris_material_id = _get_fracture_debris(t.material_id)
	elif res.striker_fractured:
		res.debris_material_id = _get_fracture_debris(s.material_id)

	res.summary = "Solid vs Solid: %s vs %s. Energy: %.1f J. Outcome: %s. Dmg Target: %.1f, Dmg Striker: %.1f." % [
		_MaterialTypes.get_display_name(s.material_id),
		_MaterialTypes.get_display_name(t.material_id),
		energy,
		_ImpactTypes.Outcome.keys()[res.outcome],
		res.damage_to_target,
		res.damage_to_striker
	]

## SOLID vs. LIQUID (e.g. Projectile into Water, Acid, Greek Fire, or Non-Newtonian Oobleck)
static func _solve_solid_vs_liquid(
	s,
	t,
	params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	var speed: float = params.velocity.length()
	if speed <= 0.0:
		speed = sqrt(2.0 * energy / maxf(0.01, params.mass))

	# Special Non-Newtonian shear thickening (Oobleck)
	if t.material_id == _MaterialTypes.Type.OOBLECK:
		# At high velocity, Oobleck acts like concrete/stone
		if speed >= 6.0 or energy >= 80.0:
			var pseudo_solid = _MatterComponent.new()
			pseudo_solid.state = 0  # Treat as SOLID temporarily
			pseudo_solid.hardness = clampf(speed * 0.7, 3.0, 7.5)
			pseudo_solid.yield_strength = clampf(speed * speed * 4.0, 40.0, 400.0)
			pseudo_solid.elasticity = 0.05
			pseudo_solid.density = t.density
			pseudo_solid.material_id = t.material_id
			_solve_solid_vs_solid(s, pseudo_solid, params, energy, res)
			res.summary = "Oobleck shear-thickened into solid barrier under high impact velocity (%.1f m/s)!" % speed
			return

	# Newtonian Fluid Hydrodynamic Drag & Deceleration
	var area: float = maxf(0.0001, params.contact_area)
	var fluid_density: float = maxf(100.0, t.density)
	var drag_coeff: float = 0.85
	# Drag deceleration energy dissipation
	var drag_factor: float = clampf(0.5 * fluid_density * drag_coeff * area * 25.0 / maxf(0.01, params.mass), 0.1, 0.95)

	res.energy_absorbed = energy * drag_factor
	res.rebound_energy = energy - res.energy_absorbed
	res.rebound_velocity = params.velocity * (1.0 - drag_factor)

	# Splashing threshold (energy > 20 J or speed > 4 m/s)
	if energy >= 20.0 or speed >= 4.0:
		res.outcome = _ImpactTypes.Outcome.SPLASHED
	else:
		res.outcome = _ImpactTypes.Outcome.ABSORBED

	res.penetration_depth = clampf(1.0 - drag_factor, 0.1, 1.0)
	res.sound_loudness = clampf(0.25 + (res.energy_absorbed / 250.0), 0.2, 0.75)

	# Wetting & Chemical/Toxic transfer
	res.contaminants_transferred["moisture"] = minf(1.0, s.moisture + 0.45)
	if t.corrosiveness > 0.0:
		res.contaminants_transferred["corrosion"] = t.corrosiveness
		res.contaminants_transferred["source_mat_id"] = t.material_id
	if t.toxicity > 0.0:
		res.contaminants_transferred["toxicity"] = t.toxicity
		res.contaminants_transferred["source_mat_id"] = t.material_id

	# Flammable fluid ignition from hot striker
	if t.flammability > 0.1 and t.ignition_temp_c < INF:
		if s.temperature_c >= t.ignition_temp_c or params.temperature_c >= t.ignition_temp_c:
			res.ignition_occurred = true

	res.summary = "Solid vs Liquid (%s into %s). Splashed with %.1f J absorbed. Wetted." % [
		_MaterialTypes.get_display_name(s.material_id),
		_MaterialTypes.get_display_name(t.material_id),
		res.energy_absorbed
	]

## LIQUID vs. SOLID (e.g. Acid / Greek Fire splash thrown onto Steel Armor or Wooden Wall)
static func _solve_liquid_vs_solid(
	s,
	t,
	_params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	res.outcome = _ImpactTypes.Outcome.SPLASHED
	res.energy_absorbed = energy * 0.9
	res.rebound_energy = energy * 0.1
	res.sound_loudness = clampf(0.15 + (energy / 300.0), 0.15, 0.6)

	# Fluid coats the solid target
	res.contaminants_transferred["moisture"] = minf(1.0, t.moisture + 0.5)
	if s.corrosiveness > 0.0:
		res.contaminants_transferred["corrosion"] = s.corrosiveness
		res.contaminants_transferred["source_mat_id"] = s.material_id
	if s.toxicity > 0.0:
		res.contaminants_transferred["toxicity"] = s.toxicity
		res.contaminants_transferred["source_mat_id"] = s.material_id

	# Flammable fluid coating a hot/burning surface
	if s.flammability > 0.1 and s.ignition_temp_c < INF:
		if t.temperature_c >= s.ignition_temp_c:
			res.ignition_occurred = true

	res.summary = "Liquid splash (%s onto %s). Surface coated with contaminants/fluid." % [
		_MaterialTypes.get_display_name(s.material_id),
		_MaterialTypes.get_display_name(t.material_id)
	]

## SOLID vs. GAS (e.g. Arrow, thrown rock, or claw moving through Chlorine or Cave Methane)
static func _solve_solid_vs_gas(
	s,
	t,
	params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	res.outcome = _ImpactTypes.Outcome.PASSED_THROUGH
	# Negligible aerodynamic drag
	res.energy_absorbed = energy * 0.03
	res.rebound_energy = energy * 0.97
	res.rebound_velocity = params.velocity * 0.985
	res.penetration_depth = 1.0
	res.sound_loudness = 0.05

	# Gas displaced by projectile wake
	res.contaminants_transferred["gas_displacement"] = 0.2

	# Passing through toxic/corrosive gas coats trace residue
	if t.corrosiveness > 0.0:
		res.contaminants_transferred["corrosion"] = t.corrosiveness * 0.15
		res.contaminants_transferred["source_mat_id"] = t.material_id
	if t.toxicity > 0.0:
		res.contaminants_transferred["toxicity"] = t.toxicity * 0.2
		res.contaminants_transferred["source_mat_id"] = t.material_id

	# Flammable gas auto-ignition (e.g. burning projectile through Cave Methane)
	if t.flammability > 0.2 and t.ignition_temp_c < INF:
		if s.temperature_c >= t.ignition_temp_c or params.temperature_c >= t.ignition_temp_c:
			res.ignition_occurred = true

	res.summary = "Solid passed through gas (%s). Trajectory unimpeded." % _MaterialTypes.get_display_name(t.material_id)

## GAS vs. SOLID
static func _solve_gas_vs_solid(
	s,
	_t,
	_params: _ImpactTypes.ImpactParams,
	_energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	res.outcome = _ImpactTypes.Outcome.ABSORBED
	res.sound_loudness = 0.02
	if s.corrosiveness > 0.0:
		res.contaminants_transferred["corrosion"] = s.corrosiveness * 0.1
	if s.toxicity > 0.0:
		res.contaminants_transferred["toxicity"] = s.toxicity * 0.1
	res.summary = "Gas cloud drifted against solid barrier."

## LIQUID vs. LIQUID
static func _solve_liquid_vs_liquid(
	_s,
	_t,
	_params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	res.outcome = _ImpactTypes.Outcome.SPLASHED
	res.energy_absorbed = energy * 0.95
	res.sound_loudness = 0.3
	res.summary = "Liquid vs Liquid: fluids intermixed and splashed."

## COLLOIDS (e.g. Ectoplasm)
static func _solve_colloid_interaction(
	s,
	t,
	_params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	res.outcome = _ImpactTypes.Outcome.ABSORBED
	res.energy_absorbed = energy * 0.90
	res.rebound_energy = energy * 0.10
	res.sound_loudness = 0.15

	# Ectoplasm has negative specific heat (endothermic) -> rapidly drains heat
	if t.material_id == _MaterialTypes.Type.ECTOPLASM or s.material_id == _MaterialTypes.Type.ECTOPLASM:
		res.heat_generated_c = -40.0  # Cold flash / freezing shock
		res.summary = "Colloid collision: Ectoplasm endothermic drain chilled striker by 40C!"
	else:
		res.summary = "Colloid collision: viscous absorption dissipated momentum."

## Generic Fluid fallback
static func _solve_generic_fluid(
	_s,
	_t,
	_params: _ImpactTypes.ImpactParams,
	energy: float,
	res: _ImpactTypes.ImpactResult
) -> void:
	res.outcome = _ImpactTypes.Outcome.ABSORBED
	res.energy_absorbed = energy * 0.8
	res.rebound_energy = energy * 0.2
	res.summary = "Generic fluid collision absorbed kinetic energy."

# ===========================================================================
# 3. ECS Entity-Level Resolver
# ===========================================================================

## Resolves an impact between two live ECS entities in the World.
## Applies damage to components, spawns debris, plays sounds, and ignites fire.
func resolve_entity_impact(
	striker_eid: int,
	target_eid: int,
	params: _ImpactTypes.ImpactParams
) -> _ImpactTypes.ImpactResult:
	if world == null:
		push_error("[ImpactSolverSystem] Cannot resolve entity impact: World is null.")
		return null

	var reg = world.get_registry()
	var s_matter = reg.get_component(striker_eid, &"MatterComponent")
	var t_matter = reg.get_component(target_eid, &"MatterComponent")
	var s_item   = reg.get_component(striker_eid, &"ItemComponent")

	# Fallbacks if MatterComponent is not yet attached
	if s_matter == null:
		s_matter = _MatterComponent.new()
		_MaterialTypes.apply_to(s_matter, _MaterialTypes.Type.STEEL)
	if t_matter == null:
		t_matter = _MatterComponent.new()
		_MaterialTypes.apply_to(t_matter, _MaterialTypes.Type.GROUND)

	# If striker is an item entity, enrich params with its mold geometry if unspecified
	var effective_params: _ImpactTypes.ImpactParams = params
	if s_item != null:
		if effective_params == null:
			effective_params = _ItemTypes.build_impact_params(s_item, s_matter, Vector2(10.0, 0.0))
		elif effective_params.contact_area <= 0.0001 and effective_params.form == _ImpactTypes.Form.BLUNT:
			var mold_params = _ItemTypes.build_impact_params(s_item, s_matter, effective_params.velocity)
			effective_params.form = mold_params.form
			effective_params.contact_area = mold_params.contact_area
			effective_params.sharpness = mold_params.sharpness
			if effective_params.mass <= 1.0 and s_item.total_mass > 0.0:
				effective_params.mass = mold_params.mass
				if effective_params.kinetic_energy <= 0.1:
					effective_params.kinetic_energy = mold_params.kinetic_energy

	var result: _ImpactTypes.ImpactResult = solve_impact(s_matter, t_matter, effective_params)

	# Check for explosive payload in striker item (e.g. Blasting Warhammer)
	var explosive_part_name: String = ""
	if s_item != null:
		for part_name: String in s_item.parts:
			var p: Dictionary = s_item.parts[part_name]
			var p_mat = _MaterialTypes.get_data(p["material_id"])
			if p.get("wear", 0.0) < 1.0 and p_mat.get("flammability", 0.0) >= 0.90:
				explosive_part_name = part_name
				break

	if explosive_part_name != "" and effective_params.kinetic_energy >= 35.0:
		var blast_damage: float = 300.0
		result.damage_to_target += blast_damage
		result.heat_generated_c += 350.0
		result.sparks_produced = true
		result.ignition_occurred = true
		result.sound_loudness = 1.0
		result.outcome = _ImpactTypes.Outcome.SHATTERED
		s_item.parts[explosive_part_name]["wear"] = 1.0
		result.summary += " [EXPLOSIVE DETONATION: +%.0f blast damage!]" % blast_damage

	# Consume weapon surface coating on hit
	if s_item != null and s_item.parts.has("coating"):
		var c_wear: float = s_item.parts["coating"].get("wear", 0.0)
		if c_wear < 1.0:
			s_item.parts["coating"]["wear"] = minf(1.0, c_wear + 0.25)
			if s_item.parts["coating"]["wear"] >= 1.0:
				s_matter.toxicity = 0.0
				s_matter.corrosiveness = 0.0

	# 1. Apply structural damage to target
	if result.damage_to_target > 0.0:
		t_matter.yield_strength = maxf(0.0, t_matter.yield_strength - result.damage_to_target)
		if result.target_fractured or t_matter.yield_strength <= 0.0:
			_handle_target_fracture(target_eid, t_matter, result, reg)

	# 2. Apply wear/damage to striker (including ItemComponent parts wear)
	if result.damage_to_striker > 0.0:
		s_matter.yield_strength = maxf(0.0, s_matter.yield_strength - result.damage_to_striker)
		if s_item != null and s_item.parts.has(s_item.primary_part):
			var wear_delta = result.damage_to_striker / maxf(1.0, s_matter.yield_strength + result.damage_to_striker)
			s_item.parts[s_item.primary_part]["wear"] = clampf(s_item.parts[s_item.primary_part]["wear"] + wear_delta, 0.0, 1.0)
		if result.striker_fractured or s_matter.yield_strength <= 0.0:
			_handle_striker_fracture(striker_eid, s_matter, result, reg)

	# 3. Apply transferred contaminants (toxic, corrosive, moisture)
	if result.contaminants_transferred.size() > 0:
		_apply_contaminants_to_entity(target_eid, result.contaminants_transferred, reg)

	# 4. Handle thermal ignition
	if result.ignition_occurred and not reg.has(target_eid, &"BurningComponent"):
		var b = _BurningComponent.new()
		b.intensity = clampf(t_matter.flammability, 0.5, 1.0)
		b.fuel = 1.0
		b.heat_output = 25.0
		reg.add(target_eid, b)

	# 5. Acoustic sound emission to SignalSystem
	if result.sound_loudness > 0.05 and world != null:
		_emit_collision_sound(target_eid, result.sound_loudness, reg)

	return result

# ===========================================================================
# 4. Tick Queue Processing
# ===========================================================================

func tick(_tick_number: int) -> void:
	if world == null:
		return

	var reg = world.get_registry()
	var event_store: Dictionary = reg.get_store(&"ImpactEventComponent")
	if event_store.is_empty():
		return

	var event_eids: Array = event_store.keys()
	for eid: int in event_eids:
		var event = reg.get_component(eid, &"ImpactEventComponent")
		if event == null or event.processed:
			continue

		if event.target_eid != -1 and event.params != null:
			event.result = resolve_entity_impact(eid, event.target_eid, event.params)
			event.processed = true

		if event.remove_on_resolve:
			reg.remove(eid, &"ImpactEventComponent")

# ===========================================================================
# Helpers & Destructive Handlers
# ===========================================================================

func _handle_target_fracture(target_eid: int, t_matter, result: _ImpactTypes.ImpactResult, reg) -> void:
	# If target has vegetation, splinter and remove it
	if reg.has(target_eid, &"VegetationComponent"):
		reg.remove(target_eid, &"VegetationComponent")

	# If target is terrain tile, crumble into debris
	var tile_comp = reg.get_component(target_eid, &"TileComponent")
	if tile_comp != null:
		var fallback_mat: int = result.debris_material_id
		if fallback_mat != -1:
			t_matter.material_id = fallback_mat
			_apply_material_archetype(t_matter, _MaterialTypes.get_data(fallback_mat))
			# Update tile type to match
			var new_tile_type: int = _TileTypes.Type.DIRT
			if fallback_mat == _MaterialTypes.Type.GROUND:
				new_tile_type = _TileTypes.Type.GROUND
			elif fallback_mat == _MaterialTypes.Type.KINDLING:
				new_tile_type = _TileTypes.Type.GRASS
			tile_comp.tile_type = new_tile_type
			if world != null and world.signals != null:
				world.signals.notify_tile_type_changed(tile_comp.position, new_tile_type)
			_update_render(target_eid, new_tile_type, reg)

func _handle_striker_fracture(striker_eid: int, s_matter, result: _ImpactTypes.ImpactResult, reg) -> void:
	var s_item = reg.get_component(striker_eid, &"ItemComponent")
	if s_item != null and s_item.parts.has(s_item.primary_part):
		s_item.parts[s_item.primary_part]["wear"] = 1.0
	if result.debris_material_id != -1:
		s_matter.material_id = result.debris_material_id
		_apply_material_archetype(s_matter, _MaterialTypes.get_data(result.debris_material_id))

func _emit_collision_sound(target_eid: int, loudness: float, reg) -> void:
	var tile = reg.get_component(target_eid, &"TileComponent")
	var pos: Vector2i = tile.position if tile != null else Vector2i.ZERO

	# Check if World has signals exposed or in _sim_systems
	var sig_sys = null
	if "signals" in world and world.signals != null:
		sig_sys = world.signals
	else:
		for sys in world._sim_systems:
			if sys.get_script().resource_path.ends_with("SignalSystem.gd"):
				sig_sys = sys
				break

	if sig_sys != null and sig_sys.has_method("emit_sound"):
		var radius: int = int(clampf(loudness * 8.0, 1.0, 10.0))
		sig_sys.emit_sound(pos, loudness, radius)

func _apply_contaminants_to_entity(eid: int, transferred: Dictionary, reg) -> void:
	var contam = reg.get_component(eid, &"ContaminantComponent")
	if contam == null:
		contam = _ContaminantComponent.new()
		reg.add(eid, contam)

	if transferred.has("toxicity"):
		contam.toxicity = clampf(contam.toxicity + transferred["toxicity"], 0.0, 1.0)
	if transferred.has("corrosion"):
		contam.corrosion = clampf(contam.corrosion + transferred["corrosion"], 0.0, 1.0)
	if transferred.has("source_mat_id"):
		contam.source_mat_id = transferred["source_mat_id"]

	if transferred.has("moisture"):
		var matter = reg.get_component(eid, &"MatterComponent")
		if matter != null:
			matter.moisture = clampf(transferred["moisture"], 0.0, 1.0)

static func _get_fracture_debris(mat_id: int) -> int:
	match mat_id:
		_MaterialTypes.Type.OBSIDIAN, _MaterialTypes.Type.STONE:
			return _MaterialTypes.Type.DIRT
		_MaterialTypes.Type.WOOD_HARD, _MaterialTypes.Type.WOOD_SOFT:
			return _MaterialTypes.Type.KINDLING
		_MaterialTypes.Type.STEEL:
			return _MaterialTypes.Type.GROUND
		_MaterialTypes.Type.SILICA_AEROGEL:
			return _MaterialTypes.Type.DIRT
		_:
			return _MaterialTypes.Type.GROUND

static func _apply_material_archetype(matter, d: Dictionary) -> void:
	matter.state           = d.get("state",           0) as int
	matter.density         = d.get("density",         1000.0) as float
	matter.melting_point_c = d.get("melting_point_c", INF) as float
	matter.boiling_point_c = d.get("boiling_point_c", INF) as float
	matter.ignition_temp_c = d.get("ignition_temp_c", INF) as float
	matter.conductivity    = d.get("conductivity",    1.0) as float
	matter.specific_heat   = d.get("specific_heat",   1000.0) as float
	matter.flammability    = d.get("flammability",    0.0) as float
	matter.acidity_ph      = d.get("acidity_ph",      7.0) as float
	matter.corrosiveness   = d.get("corrosiveness",   0.0) as float
	matter.moisture        = d.get("moisture",        0.0) as float
	matter.rot_rate        = d.get("rot_rate",        0.0) as float
	matter.toxicity        = d.get("toxicity",        0.0) as float
	matter.hardness        = d.get("hardness",        5.0) as float
	matter.yield_strength  = d.get("yield_strength",  100.0) as float
	matter.elasticity      = d.get("elasticity",      0.3) as float

func _update_render(eid: int, tile_type: int, reg) -> void:
	var render = reg.get_component(eid, &"RenderComponent")
	if render == null:
		return
	var td: Dictionary = _TileTypes.get_data(tile_type)
	render.glyph    = td["glyph"]
	render.fg_color = td["fg_color"]
	render.bg_color = td["bg_color"]

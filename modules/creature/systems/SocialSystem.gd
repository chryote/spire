## SocialSystem.gd
## Priority 227 -- runs between MatingSystem (226) and CreatureAISystem (230).
##
## Manages creature sociality lifecycle, flocking/herd metrics (centroid, peer counts),
## kinship and pair bond maintenance, and sociability drive dynamics.
class_name SocialSystem
extends "res://core/SystemBase.gd"

const _CreatureComponent = preload("res://modules/creature/components/CreatureComponent.gd")
const _SocialComponent   = preload("res://modules/creature/components/SocialComponent.gd")
const _PositionComponent = preload("res://modules/creature/components/PositionComponent.gd")
const _MindComponent     = preload("res://modules/creature/components/mind/MindComponent.gd")
const _MindEmbeddings    = preload("res://modules/creature/data/MindEmbeddings.gd")
const _CreatureTypes     = preload("res://modules/creature/data/CreatureTypes.gd")
const _SocialTypes       = preload("res://modules/creature/data/SocialTypes.gd")

func initialize() -> void:
	print("[SocialSystem] Initialized. Priority 227.")

func tick(_tick_number: int) -> void:
	if world == null:
		return

	var reg = world.get_registry()
	if reg == null:
		return

	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var social_store: Dictionary   = reg.get_store(&"SocialComponent")
	var pos_store: Dictionary      = reg.get_store(&"PositionComponent")
	var mind_store: Dictionary     = reg.get_store(&"MindComponent")

	for eid: int in creature_store:
		var creature: _CreatureComponent = creature_store[eid]
		if not creature.is_alive:
			continue

		var social_comp: _SocialComponent = social_store.get(eid, null)
		var pos_comp: _PositionComponent  = pos_store.get(eid, null)
		var mind: _MindComponent          = mind_store.get(eid, null)

		if social_comp == null or pos_comp == null:
			continue

		var cur_pos: Vector2i = pos_comp.position

		# -------------------------------------------------------------------
		# 1. Clean Up Broken/Dead Bonds
		# -------------------------------------------------------------------
		_validate_bonds(social_comp, creature_store)

		# -------------------------------------------------------------------
		# 2. Local Herd & Peer Perception
		# -------------------------------------------------------------------
		var peer_count: int = 0
		var centroid_sum := Vector2.ZERO
		var min_peer_dist: float = 999.0
		var closest_eid: int = -1
		var has_bonded_near: bool = false

		for other_eid: int in pos_store:
			if other_eid == eid:
				continue

			var other_creature: _CreatureComponent = creature_store.get(other_eid, null)
			if other_creature == null or not other_creature.is_alive:
				continue

			var is_same_species: bool = (other_creature.species_type == creature.species_type)
			var is_bonded: bool = social_comp.is_bonded_to(other_eid)

			# Social perception evaluates conspecifics (same species) and bonded allies
			if not is_same_species and not is_bonded:
				continue

			var other_pos: Vector2i = pos_store[other_eid].position
			var dist: float = Vector2(cur_pos).distance_to(Vector2(other_pos))

			if dist <= float(social_comp.social_radius):
				peer_count += 1
				centroid_sum += Vector2(other_pos)

				if dist < min_peer_dist:
					min_peer_dist = dist
					closest_eid = other_eid

				if is_bonded and dist <= float(social_comp.comfort_dist_max):
					has_bonded_near = true

		# Update dynamic runtime metrics
		social_comp.recent_peers_count = peer_count
		social_comp.closest_peer_dist = min_peer_dist
		social_comp.closest_peer_eid = closest_eid
		if peer_count > 0:
			social_comp.herd_centroid = centroid_sum / float(peer_count)
		else:
			social_comp.herd_centroid = Vector2.ZERO

		# -------------------------------------------------------------------
		# 3. Sociability Drive & Comfort Updates
		# -------------------------------------------------------------------
		if mind != null:
			_update_social_drives(social_comp, mind, peer_count, min_peer_dist, has_bonded_near)

			# Feed social perception flags into mind.perceived_signals
			mind.perceived_signals[&"peers_nearby"] = clampf(float(peer_count) / 4.0, 0.0, 1.0)
			mind.perceived_signals[&"has_bonded_near"] = has_bonded_near
			mind.perceived_signals[&"closest_peer_dist"] = min_peer_dist

func _validate_bonds(social_comp: _SocialComponent, creature_store: Dictionary) -> void:
	if social_comp.bonded_partner_eid != -1:
		var partner = creature_store.get(social_comp.bonded_partner_eid, null)
		if partner == null or not partner.is_alive:
			social_comp.clear_partner_bond()

	if social_comp.mother_eid != -1:
		var mother = creature_store.get(social_comp.mother_eid, null)
		if mother == null or not mother.is_alive:
			social_comp.clear_mother_bond()

	var valid_offspring: Array[int] = []
	for child_eid in social_comp.offspring_eids:
		var child = creature_store.get(child_eid, null)
		if child != null and child.is_alive:
			valid_offspring.append(child_eid)
	social_comp.offspring_eids = valid_offspring

func _update_social_drives(
	social_comp: _SocialComponent,
	mind: _MindComponent,
	peer_count: int,
	min_peer_dist: float,
	has_bonded_near: bool
) -> void:
	# A. Isolation dynamics (No peers within social radius)
	if peer_count == 0:
		if social_comp.sociality > 0.25:
			# Sociability drive accumulates (loneliness / separation anxiety)
			var iso_rate: float = 0.003 * social_comp.sociality
			mind.sociability = clampf(mind.sociability + iso_rate, 0.0, 1.0)
			# Comfort degrades when isolated
			var comfort_loss: float = 0.001 * social_comp.sociality
			mind.drives[_MindEmbeddings.Drive.COMFORT] = maxf(0.0, mind.drives[_MindEmbeddings.Drive.COMFORT] - comfort_loss)
		else:
			# Solitary creature is content being alone
			mind.sociability = maxf(0.0, mind.sociability - 0.002)

	# B. Herd companionship dynamics (Peers present)
	else:
		# Sociability drive is satisfied
		var sat_rate: float = 0.006 * (0.5 + social_comp.sociality)
		mind.sociability = maxf(0.0, mind.sociability - sat_rate)

		# Comfort bonus when within personal comfort bounds
		if min_peer_dist >= float(social_comp.comfort_dist_min) and min_peer_dist <= float(social_comp.comfort_dist_max):
			var comfort_gain: float = 0.002 * social_comp.sociality
			if has_bonded_near:
				comfort_gain += 0.002 # Bonus reassurance near mate/mother
			mind.drives[_MindEmbeddings.Drive.COMFORT] = clampf(mind.drives[_MindEmbeddings.Drive.COMFORT] + comfort_gain, 0.0, 1.0)

		# Overcrowding penalty if crowded too tightly and creature is solitary/independent
		elif min_peer_dist < float(social_comp.comfort_dist_min) and peer_count >= 3:
			if social_comp.sociality < 0.60:
				mind.drives[_MindEmbeddings.Drive.COMFORT] = maxf(0.0, mind.drives[_MindEmbeddings.Drive.COMFORT] - 0.002)

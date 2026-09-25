## SocialComponent.gd
## Component storing individual social traits, kinship bonds, pack affiliation,
## and cached local herd dynamics.
class_name SocialComponent
extends Resource

const _SocialTypes = preload("res://modules/creature/data/SocialTypes.gd")

# ---------------------------------------------------------------------------
# Individual Social Tendencies (0.0 to 1.0)
# ---------------------------------------------------------------------------
## General affinity for living in groups vs solitary living.
@export var sociality: float = 0.50

## Likelihood and strength of forming a persistent mated pair bond.
@export var pair_bond_tendency: float = 0.30

## Fidelity and exclusivity to bonded partner (0.0 = promiscuous, 1.0 = strictly faithful).
@export var monogamy_tendency: float = 0.50

## Likelihood and strength of remaining attached to parents and offspring.
@export var kinship_tendency: float = 0.60

# ---------------------------------------------------------------------------
# Spatial Flocking & Herd Range Configuration
# ---------------------------------------------------------------------------
## Radius in tiles within which herd peers are perceived and provide comfort.
@export var social_radius: int = 12

## Minimum personal space distance (tiles) to avoid overcrowding.
@export var comfort_dist_min: int = 2

## Maximum separation distance (tiles) before loneliness/anxiety triggers.
@export var comfort_dist_max: int = 6

# ---------------------------------------------------------------------------
# Inter-Entity Relational Bonds
# ---------------------------------------------------------------------------
## Entity ID of bonded mating partner (-1 if none).
@export var bonded_partner_eid: int = -1

## Entity ID of mother for offspring following (-1 if none).
@export var mother_eid: int = -1

## Entity IDs of known living offspring.
@export var offspring_eids: Array[int] = []

## Pack or herd group ID (-1 for loose/independent).
@export var pack_id: int = -1

# ---------------------------------------------------------------------------
# Dynamic Runtime Metrics (Computed by SocialSystem each tick)
# ---------------------------------------------------------------------------
## Number of same-species herd peers perceived within social_radius on recent tick.
var recent_peers_count: int = 0

## Local center of mass of nearby herd members (Vector2.ZERO if isolated).
var herd_centroid: Vector2 = Vector2.ZERO

## Distance to closest herd peer.
var closest_peer_dist: float = 999.0

## Entity ID of the closest peer.
var closest_peer_eid: int = -1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func has_bonded_partner() -> bool:
	return bonded_partner_eid != -1

func is_partner_alive(reg) -> bool:
	if bonded_partner_eid == -1 or reg == null:
		return false
	var creature_store: Dictionary = reg.get_store(&"CreatureComponent")
	var partner = creature_store.get(bonded_partner_eid, null)
	return partner != null and partner.is_alive

func has_mother() -> bool:
	return mother_eid != -1

func is_bonded_to(target_eid: int) -> bool:
	if target_eid == -1:
		return false
	return target_eid == bonded_partner_eid or target_eid == mother_eid or offspring_eids.has(target_eid)

func add_offspring(child_eid: int) -> void:
	if child_eid != -1 and not offspring_eids.has(child_eid):
		offspring_eids.append(child_eid)

func remove_offspring(child_eid: int) -> void:
	offspring_eids.erase(child_eid)

func clear_partner_bond() -> void:
	bonded_partner_eid = -1

func clear_mother_bond() -> void:
	mother_eid = -1

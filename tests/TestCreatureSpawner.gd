## TestCreatureSpawner.gd
## Comprehensive test suite for extensible creature spawning and starter population:
## 1. Verifies default starter population introduces both Male and Female Grazer.
## 2. Validates distinct tile placement, walkability, hazard safety, and partner proximity.
## 3. Verifies anatomical genital limbs, gender traits, and female reproduction spawn rate.
## 4. Tests extensible configuration dictionary spawning via CreatureSpawner and CreatureFactory.
## 5. Validates spatial query fallback behaviors and collision prevention.
extends Node2D

const _CreatureSpawner     = preload("res://modules/creature/systems/CreatureSpawner.gd")
const _CreatureFactory     = preload("res://modules/creature/systems/CreatureFactory.gd")
const _CreatureTypes       = preload("res://modules/creature/data/CreatureTypes.gd")
const _CreatureComponent   = preload("res://modules/creature/components/CreatureComponent.gd")
const _PositionComponent   = preload("res://modules/creature/components/PositionComponent.gd")
const _BodyComponent       = preload("res://modules/creature/components/body/BodyComponent.gd")
const _MatingComponent     = preload("res://modules/creature/components/MatingComponent.gd")
const _TraitComponent      = preload("res://modules/creature/components/TraitComponent.gd")
const _TraitTypes          = preload("res://modules/creature/data/TraitTypes.gd")
const _TileAffordance      = preload("res://modules/signal/data/TileAffordance.gd")
const _ItemComponent       = preload("res://modules/item/components/ItemComponent.gd")

func _ready() -> void:
	print("\n=== STARTING CREATURE SPAWNER & STARTER GRAZER TEST ===")
	await get_tree().process_frame
	await get_tree().process_frame

	World.paused = true

	_test_default_starter_male_and_female_grazer()
	_test_creature_factory_create_from_config()
	_test_extensible_custom_creature_batch()
	_test_spatial_position_finding_and_collision_avoidance()
	_test_fallback_resilience()

	print("\n>>> ALL CREATURE SPAWNER & STARTER GRAZER TESTS PASSED! <<<\n")
	_write_log_artifact()
	World.paused = false
	get_tree().quit(0)

func _test_default_starter_male_and_female_grazer() -> void:
	print("\n[Test 1] Testing default starter population (Male & Female Grazer)...")
	var reg = World.get_registry()
	assert(reg != null, "World registry must be valid")

	var starter_eids: Array[int] = _CreatureSpawner.spawn_starter_creatures(World)
	assert(starter_eids.size() == 2, "Default starter population must spawn exactly 2 creatures")

	var male_eid: int = starter_eids[0]
	var female_eid: int = starter_eids[1]

	var male_creature: _CreatureComponent = reg.get_component(male_eid, &"CreatureComponent")
	var female_creature: _CreatureComponent = reg.get_component(female_eid, &"CreatureComponent")
	assert(male_creature != null, "Male Grazer must have CreatureComponent")
	assert(female_creature != null, "Female Grazer must have CreatureComponent")

	assert(male_creature.species_type == _CreatureTypes.Type.GRAZER, "Male must be a Grazer")
	assert(female_creature.species_type == _CreatureTypes.Type.GRAZER, "Female must be a Grazer")
	assert(male_creature.gender == _CreatureTypes.Gender.MALE, "Male creature gender must be MALE")
	assert(female_creature.gender == _CreatureTypes.Gender.FEMALE, "Female creature gender must be FEMALE")

	# Genital limb verification
	var male_body: _BodyComponent = reg.get_component(male_eid, &"BodyComponent")
	var female_body: _BodyComponent = reg.get_component(female_eid, &"BodyComponent")
	assert(male_body.limbs.has("male_genital"), "Male Grazer must possess male_genital limb")
	assert(female_body.limbs.has("female_genital"), "Female Grazer must possess female_genital limb")

	# Mating reproduction stats
	var male_mating: _MatingComponent = reg.get_component(male_eid, &"MatingComponent")
	var female_mating: _MatingComponent = reg.get_component(female_eid, &"MatingComponent")
	assert(male_mating != null and male_mating.is_male(), "Male MatingComponent must be configured as male")
	assert(female_mating != null and female_mating.is_female(), "Female MatingComponent must be configured as female")
	assert(male_mating.spawn_rate == 0.0, "Male spawn_rate must be 0.0")
	assert(female_mating.spawn_rate > 0.0, "Female Grazer must possess positive reproduction spawn_rate")

	# Position & collision separation check
	var male_pos_comp: _PositionComponent = reg.get_component(male_eid, &"PositionComponent")
	var female_pos_comp: _PositionComponent = reg.get_component(female_eid, &"PositionComponent")
	assert(male_pos_comp != null and female_pos_comp != null, "Both grazers must have PositionComponent")

	var male_pos: Vector2i = male_pos_comp.position
	var female_pos: Vector2i = female_pos_comp.position
	assert(male_pos != female_pos, "Male and Female Grazers must NOT spawn on the same tile (%s vs %s)" % [male_pos, female_pos])

	# Affordances check
	if World.signals != null:
		assert(World.signals.has_affordance(male_pos, _TileAffordance.WALKABLE), "Male spawn tile must be walkable")
		assert(not World.signals.has_affordance(male_pos, _TileAffordance.HAZARD_LETHAL), "Male spawn tile must not be lethal")
		assert(World.signals.has_affordance(female_pos, _TileAffordance.WALKABLE), "Female spawn tile must be walkable")
		assert(not World.signals.has_affordance(female_pos, _TileAffordance.HAZARD_LETHAL), "Female spawn tile must not be lethal")

	# Proximity check: female was clustered near male within reasonable distance
	var dist: float = Vector2(male_pos).distance_to(Vector2(female_pos))
	assert(dist >= 1.0, "Grazers must be separated by at least 1 tile")
	assert(dist <= 20.0, "Grazers should spawn within social proximity of each other (actual: %.2f tiles)" % dist)

	print("  Successfully spawned Male Grazer at %s and Female Grazer at %s (distance: %.1f tiles)" % [
		male_pos, female_pos, dist
	])

func _test_creature_factory_create_from_config() -> void:
	print("\n[Test 2] Testing CreatureFactory.create_from_config helper...")
	var reg = World.get_registry()

	var custom_cfg: Dictionary = {
		"species": _CreatureTypes.Type.HARE,
		"gender": _CreatureTypes.Gender.FEMALE,
		"name": "ConfigLeveret",
		"traits": [_TraitTypes.Type.BOLD],
		"stage": _CreatureTypes.GrowthStage.JUVENILE,
		"pos": Vector2i(55, 55),
	}

	var eid: int = _CreatureFactory.create_from_config(World, custom_cfg)
	assert(eid != -1, "create_from_config must succeed")

	var c_comp: _CreatureComponent = reg.get_component(eid, &"CreatureComponent")
	var t_comp: _TraitComponent = reg.get_component(eid, &"TraitComponent")
	var p_comp: _PositionComponent = reg.get_component(eid, &"PositionComponent")

	assert(c_comp.creature_name == "ConfigLeveret", "Creature name must match config")
	assert(c_comp.species_type == _CreatureTypes.Type.HARE, "Species must be HARE")
	assert(c_comp.gender == _CreatureTypes.Gender.FEMALE, "Gender must be FEMALE")
	assert(t_comp.has_genetic_trait(_TraitTypes.Type.BOLD), "Trait must be present")
	assert(p_comp.position == Vector2i(55, 55), "Position must match config")

	print("  create_from_config successfully created %s (eid=%d)" % [c_comp.creature_name, eid])

func _test_extensible_custom_creature_batch() -> void:
	print("\n[Test 3] Testing CreatureSpawner extensible batch spawning with custom definitions...")
	var reg = World.get_registry()

	var custom_batch: Array[Dictionary] = [
		{
			"species": _CreatureTypes.Type.DEER,
			"gender": _CreatureTypes.Gender.MALE,
			"name": "StagAlpha",
			"traits": [_TraitTypes.Type.BOLD],
			"options": {
				"min_y": 70,
				"max_y": 90,
				"require_vegetation": true,
			}
		},
		{
			"species": _CreatureTypes.Type.DEER,
			"gender": _CreatureTypes.Gender.FEMALE,
			"name": "DoeAlpha",
			"options": {
				"min_y": 70,
				"max_y": 90,
				"require_vegetation": true,
				"near_previous": true,
				"min_distance": 2,
				"max_distance": 8,
			}
		}
	]

	var eids: Array[int] = _CreatureSpawner.spawn_creatures(World, custom_batch)
	assert(eids.size() == 2, "Batch must spawn 2 deer")

	var stag_eid: int = eids[0]
	var doe_eid: int = eids[1]

	var stag_c: _CreatureComponent = reg.get_component(stag_eid, &"CreatureComponent")
	var doe_c: _CreatureComponent = reg.get_component(doe_eid, &"CreatureComponent")
	var stag_pos: Vector2i = reg.get_component(stag_eid, &"PositionComponent").position
	var doe_pos: Vector2i = reg.get_component(doe_eid, &"PositionComponent").position

	assert(stag_c.species_type == _CreatureTypes.Type.DEER, "First creature must be DEER")
	assert(doe_c.species_type == _CreatureTypes.Type.DEER, "Second creature must be DEER")
	assert(stag_c.gender == _CreatureTypes.Gender.MALE, "Stag must be male")
	assert(doe_c.gender == _CreatureTypes.Gender.FEMALE, "Doe must be female")
	assert(stag_pos != doe_pos, "Stag and Doe must occupy distinct tiles")

	var dist: float = Vector2(stag_pos).distance_to(Vector2(doe_pos))
	assert(dist >= 1.0, "Deer must be at least 1 tile apart")
	assert(dist <= 15.0, "Doe should be clustered near Stag (distance: %.1f tiles)" % dist)

	print("  Custom batch successfully spawned %s at %s and %s at %s" % [
		stag_c.creature_name, stag_pos, doe_c.creature_name, doe_pos
	])

func _test_spatial_position_finding_and_collision_avoidance() -> void:
	print("\n[Test 4] Testing spatial position finder and collision exclusion...")

	var target_ref := Vector2i(70, 75)
	var pos_a: Vector2i = _CreatureSpawner.find_spawn_position(World, {
		"min_y": 65,
		"max_y": 95,
		"near_pos": target_ref,
	})
	assert(pos_a != Vector2i(-1, -1), "Must find valid position A")

	# Finding position B with pos_a excluded must yield a distinct tile
	var pos_b: Vector2i = _CreatureSpawner.find_spawn_position(World, {
		"min_y": 65,
		"max_y": 95,
		"near_pos": target_ref,
	}, [pos_a])
	assert(pos_b != Vector2i(-1, -1), "Must find valid position B")
	assert(pos_a != pos_b, "Position B must not collide with excluded Position A")

	print("  Collision avoidance verified: pos_a=%s, pos_b=%s" % [pos_a, pos_b])

func _test_fallback_resilience() -> void:
	print("\n[Test 5] Testing fallback resilience when criteria are overly constrained...")

	# Constrain to an impossible X/Y window
	var impossible_pos: Vector2i = _CreatureSpawner.find_spawn_position(World, {
		"min_x": 0,
		"max_x": 1,
		"min_y": 0,
		"max_y": 1,
		"require_vegetation": true,
		"near_pos": Vector2i(100, 100),
		"max_distance": 2.0,
	})

	assert(impossible_pos != Vector2i(-1, -1), "Fallback must guarantee a valid tile return")
	assert(World.is_valid_position(impossible_pos), "Fallback tile must be within world bounds")

	print("  Fallback successfully returned safe tile: %s" % impossible_pos)

func _write_log_artifact() -> void:
	var log_path := "res://logs/test_creature_spawner.log"
	var file = FileAccess.open(log_path, FileAccess.WRITE)
	if file != null:
		file.store_line("PASSED: CreatureSpawner & Starter Population Integration Verified.")
		file.store_line("- Default starter population introduces both Male and Female Grazer.")
		file.store_line("- Distinct non-overlapping tile placement with walkability and hazard safety enforced.")
		file.store_line("- Anatomical genital limbs (male_genital / female_genital) and reproduction spawn rates verified.")
		file.store_line("- Extensible configuration dictionary spawning via CreatureSpawner and CreatureFactory.")
		file.store_line("- Multi-tier spatial query fallbacks guarantee valid placement under any constraints.")
		file.close()

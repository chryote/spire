## Query.gd
## Fluent ECS query builder.  Instantiated by World.query().
##
## Example usage:
##   var ids: Array = World.query() \
##       .with_all([&"TileComponent", &"BiomeComponent"]) \
##       .without([&"VegetationComponent"]) \
##       .run()
extends RefCounted

var _world = null
var _registry = null
var _with_types: Array = []    # Array[StringName]
var _without_types: Array = [] # Array[StringName]

# NOTE: Do NOT declare class_name here — this script is preloaded by World.gd
# and a self-referential class_name causes parse errors in headless boot.
# Access via World.query() which returns a preloaded instance.

# ---------------------------------------------------------------------------
# Fluent builder
# ---------------------------------------------------------------------------

## Require entities to have ALL of these component types.
func with_all(types: Array):
	for t in types:
		_with_types.append(t as StringName)
	return self

## Exclude entities that have ANY of these component types.
func without(types: Array):
	for t in types:
		_without_types.append(t as StringName)
	return self

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------

## Run the query and return matching entity IDs.
## Uses the first required type as a fast initial filter.
func run() -> Array:
	if _with_types.is_empty():
		return _world.get_all_entities()

	# Candidate set from the smallest bucket (first required type)
	var candidates: Array = _registry.get_all_with_type(_with_types[0] as StringName)

	var result: Array = []
	for entity_id: int in candidates:
		var valid := true

		# All required types must be present
		for i: int in range(1, _with_types.size()):
			if not _registry.has(entity_id, _with_types[i] as StringName):
				valid = false
				break

		if not valid:
			continue

		# No excluded types may be present
		for excl in _without_types:
			if _registry.has(entity_id, excl as StringName):
				valid = false
				break

		if valid:
			result.append(entity_id)

	return result

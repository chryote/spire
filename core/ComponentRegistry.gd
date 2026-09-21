## ComponentRegistry.gd
## Dense component store for the ECS.
## Structure: { StringName(type) → { int(entity_id) → Resource } }
##
## Access pattern:
##   registry.add(entity_id, MyComponent.new())
##   registry.get_component(entity_id, &"MyComponent") -> MyComponent
class_name ComponentRegistry
extends RefCounted

var _store: Dictionary = {}

# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

## Add (or overwrite) a component on an entity.
## The component's script must declare class_name.
func add(entity_id: int, component: Resource) -> void:
	var type_name: StringName = _type_name_of(component)
	if not _store.has(type_name):
		_store[type_name] = {}
	_store[type_name][entity_id] = component

## Remove a specific component type from an entity.
func remove(entity_id: int, type_name: StringName) -> void:
	if _store.has(type_name):
		_store[type_name].erase(entity_id)

## Remove every component from an entity (used on entity destruction).
func remove_all(entity_id: int) -> void:
	for type_name: StringName in _store:
		_store[type_name].erase(entity_id)

# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

## Return a component or null if the entity doesn't have it.
func get_component(entity_id: int, type_name: StringName) -> Resource:
	var bucket: Dictionary = _store.get(type_name, {})
	return bucket.get(entity_id, null)

## Return true when an entity owns a component of the given type.
func has(entity_id: int, type_name: StringName) -> bool:
	var bucket: Dictionary = _store.get(type_name, {})
	return bucket.has(entity_id)

## Return the raw { entity_id → Resource } dict for a type.
## Fastest way to iterate all entities that own a component.
func get_store(type_name: StringName) -> Dictionary:
	if not _store.has(type_name):
		_store[type_name] = {}
	return _store[type_name]

## Return all entity IDs that own a component of the given type.
func get_all_with_type(type_name: StringName) -> Array:
	return _store.get(type_name, {}).keys()

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _type_name_of(component: Resource) -> StringName:
	var script: Script = component.get_script() as Script
	if script == null:
		return &""
	return script.get_global_name()

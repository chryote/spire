## ActionPlanComponent.gd
## Represents the physical intention and movement path currently being executed.
class_name ActionPlanComponent
extends Resource

const _MindEmbeddings = preload("res://modules/creature/data/MindEmbeddings.gd")

## The macro-action currently being performed (MindEmbeddings.Action).
var current_goal: int = _MindEmbeddings.Action.IDLE

## The target tile coordinate the creature is navigating towards or interacting with.
var target_tile: Vector2i = Vector2i(-1, -1)

## Queue of intermediate path waypoints: Array of Vector2i.
var path_queue: Array[Vector2i] = []

## How many consecutive ticks this creature has been performing this goal.
var ticks_in_action: int = 0

## Cooldown ticks before re-scanning local area if previous scan found no targets.
var food_search_cooldown: int = 0
var water_search_cooldown: int = 0
var cover_search_cooldown: int = 0

## Helper to clear the active path.
func clear_path() -> void:
	path_queue.clear()
	target_tile = Vector2i(-1, -1)

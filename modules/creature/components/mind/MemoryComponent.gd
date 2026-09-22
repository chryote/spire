## MemoryComponent.gd
## Short-term working memory ring buffer and long-term associative spatial memory.
## Enables creatures to avoid oscillation/backtracking and remember valuable resources.
class_name MemoryComponent
extends Resource

## Maximum number of short-term memory items kept in the ring buffer.
const SHORT_TERM_CAPACITY: int = 16

## Ring buffer of recent stimuli and movements.
## Structure: Array of { "pos": Vector2i, "event": StringName, "tick": int, "intensity": float }
var short_term_events: Array[Dictionary] = []

## Persistent long-term landmarks: { Vector2i -> Dictionary }
## Structure: { "type": StringName, "value": float, "tick": int }
var long_term_landmarks: Dictionary = {}

## Record a short-term event (e.g. &"grazed", &"hazard_seen", &"stepped").
func record_event(pos: Vector2i, event_type: StringName, tick: int, intensity: float = 1.0) -> void:
	short_term_events.append({
		"pos": pos,
		"event": event_type,
		"tick": tick,
		"intensity": intensity
	})
	if short_term_events.size() > SHORT_TERM_CAPACITY:
		short_term_events.pop_front()

## True if creature recently visited or acted at pos within max_ticks.
func was_recently_at(pos: Vector2i, max_ticks: int, current_tick: int) -> bool:
	for entry in short_term_events:
		if entry["pos"] == pos and (current_tick - entry["tick"]) <= max_ticks:
			return true
	return false

## Store or update a salient long-term landmark (e.g. &"food_patch", &"water_source").
func remember_landmark(pos: Vector2i, landmark_type: StringName, value: float, current_tick: int) -> void:
	long_term_landmarks[pos] = {
		"type": landmark_type,
		"value": value,
		"tick": current_tick
	}

## Find the closest known landmark of the requested type.
## Returns Vector2i(-1, -1) if no matching landmark is remembered.
func get_closest_landmark(landmark_type: StringName, from_pos: Vector2i) -> Vector2i:
	var best_pos := Vector2i(-1, -1)
	var min_dist: float = INF

	for pos: Vector2i in long_term_landmarks:
		var data = long_term_landmarks[pos]
		if data.get("type", &"") == landmark_type:
			var d: float = from_pos.distance_to(pos)
			if d < min_dist:
				min_dist = d
				best_pos = pos

	return best_pos

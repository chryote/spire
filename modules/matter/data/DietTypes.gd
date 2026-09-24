## DietTypes.gd
## Dietary classifications for food matter, organic items, and living creatures.
## Governs which entities can derive nutritional sustenance from which materials.
class_name DietTypes
extends RefCounted

enum Category {
	NONE      = 0,
	HERBIVORE = 1, ## Plant matter, vegetation, foliage, grass, seeds
	OMNIVORE  = 2, ## General foraged food, berries, roots, insects, rations
	CARNIVORE = 3, ## Meat, organs, carcasses, bones, blood
}

## Returns true if a creature with creature_diet can digest and eat food_category.
static func can_creature_eat(creature_diet: int, food_category: int) -> bool:
	if food_category == Category.NONE:
		return false
	match creature_diet:
		Category.HERBIVORE:
			return food_category == Category.HERBIVORE or food_category == Category.OMNIVORE
		Category.CARNIVORE:
			return food_category == Category.CARNIVORE or food_category == Category.OMNIVORE
		Category.OMNIVORE:
			return true
		_:
			return false

## Human-readable string representation of a diet category.
static func get_category_name(category: int) -> String:
	match category:
		Category.HERBIVORE: return "Herbivore"
		Category.OMNIVORE:  return "Omnivore"
		Category.CARNIVORE: return "Carnivore"
		_:                  return "None"

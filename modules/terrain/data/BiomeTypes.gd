## BiomeTypes.gd
## Enum for biome classifications.
## Biomes are assigned by TerrainGenSystem from noise + moisture + height.
class_name BiomeTypes
extends RefCounted

enum Type {
	PLAINS,       ## Open grassland — primary biome
	FOREST_EDGE,  ## Moisture-rich transition zone — dense vegetation
	WETLAND,      ## Low soggy terrain — mud and water plants
	BARREN,       ## High rocky terrain — sparse life
	TUNDRA,       ## Cold terrain — near-zero vegetation, frost-prone
}


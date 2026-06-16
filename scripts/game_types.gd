class_name GameTypes
extends RefCounted

enum Terrain {
	WATER,
	SAND,
	GRASS,
	STONE,
}

enum BuildingType {
	CRASHED_SPACESHIP,
	LOGGER_CAMP,
	QUARRY,
	BURNER_GENERATOR,
	SAWMILL,
	DOCK,
	MANUAL_GENERATOR,
}

enum BuildingCategory {
	RESOURCES,
	POWER,
	PROCESSING,
	LOGISTICS,
	UTILITY,
}

enum ResourceNodeType {
	TREE,
	STONE,
}

enum ResourceType {
	WOOD,
	STONE,
	PLANKS,
}

enum AdjacencyKind {
	TERRAIN,
	RESOURCE,
	BUILDING,
}


static func terrain_display_name(terrain_type: int) -> String:
	match terrain_type:
		Terrain.WATER:
			return "Water"
		Terrain.SAND:
			return "Sand"
		Terrain.GRASS:
			return "Grass"
		Terrain.STONE:
			return "Stone"
		_:
			return "Unknown"


static func building_category_display_name(category: int) -> String:
	match category:
		BuildingCategory.RESOURCES:
			return "Resources"
		BuildingCategory.POWER:
			return "Power"
		BuildingCategory.PROCESSING:
			return "Processing"
		BuildingCategory.LOGISTICS:
			return "Logistics"
		BuildingCategory.UTILITY:
			return "Utility"
		_:
			return "Unknown"

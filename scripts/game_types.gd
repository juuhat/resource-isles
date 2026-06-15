class_name GameTypes
extends RefCounted

enum Terrain {
	WATER,
	SAND,
	GRASS,
	STONE,
}

enum BuildingType {
	HUB,
	LOGGER_CAMP,
	QUARRY,
}

enum ResourceNodeType {
	TREE,
	STONE,
}

enum ResourceType {
	WOOD,
	STONE,
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

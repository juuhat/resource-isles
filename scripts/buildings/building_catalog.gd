class_name BuildingCatalog
extends RefCounted


static func get_display_name(building_type: int) -> String:
	match building_type:
		IslandData.BuildingType.HUB:
			return "Hub"
		IslandData.BuildingType.LOGGER_CAMP:
			return "Logger's Camp"
		_:
			return "Unknown"


static func get_cost(building_type: int) -> Dictionary:
	match building_type:
		IslandData.BuildingType.HUB:
			return {
				ResourceManager.ResourceType.WOOD: 8,
				ResourceManager.ResourceType.STONE: 4,
			}
		IslandData.BuildingType.LOGGER_CAMP:
			return {
				ResourceManager.ResourceType.WOOD: 6,
			}
		_:
			return {}


static func get_label(building_type: int) -> String:
	return "%s (%s)" % [
		get_display_name(building_type),
		format_cost(get_cost(building_type)),
	]


static func format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"

	var parts: Array[String] = []
	for resource_type in cost.keys():
		parts.append("%d %s" % [
			cost[resource_type],
			ResourceManager.get_display_name_for_type(resource_type),
		])

	return ", ".join(parts)

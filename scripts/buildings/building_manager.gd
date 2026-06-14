class_name BuildingManager
extends RefCounted

const BuildingDefinitionScript := preload("res://scripts/buildings/building_definition.gd")
const HUB_TEXTURE := preload("res://assets/buildings/hub.png")
const LOGGER_CAMP_TEXTURE := preload("res://assets/buildings/logger_camp.png")

var definitions: Dictionary = {}


func _init() -> void:
	_add_definition(BuildingDefinitionScript.new(
		IslandData.BuildingType.HUB,
		"Hub",
		HUB_TEXTURE,
		{
			ResourceManager.ResourceType.WOOD: 8,
			ResourceManager.ResourceType.STONE: 4,
		}
	))
	_add_definition(BuildingDefinitionScript.new(
		IslandData.BuildingType.LOGGER_CAMP,
		"Logger's Camp",
		LOGGER_CAMP_TEXTURE,
		{
			ResourceManager.ResourceType.WOOD: 6,
		}
	))


func get_definition(building_type: int) -> BuildingDefinition:
	return definitions.get(building_type)


func get_display_name(building_type: int) -> String:
	var definition := get_definition(building_type)
	return definition.display_name if definition != null else "Unknown"


func get_cost(building_type: int) -> Dictionary:
	var definition := get_definition(building_type)
	return definition.cost if definition != null else {}


func get_label(building_type: int) -> String:
	return "%s (%s)" % [
		get_display_name(building_type),
		format_cost(get_cost(building_type)),
	]


func format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"

	var parts: Array[String] = []
	for resource_type in cost.keys():
		parts.append("%d %s" % [
			cost[resource_type],
			ResourceManager.get_display_name_for_type(resource_type),
		])

	return ", ".join(parts)


func _add_definition(definition: BuildingDefinition) -> void:
	definitions[definition.id] = definition

class_name ResourceManager
extends RefCounted

signal resource_changed(resource_type: int, amount: int)

var amounts: Dictionary = {
	GameTypes.ResourceType.WOOD: 0,
	GameTypes.ResourceType.STONE: 0,
}


func get_amount(resource_type: int) -> int:
	return amounts.get(resource_type, 0)


func set_amount(resource_type: int, amount: int) -> void:
	amounts[resource_type] = max(amount, 0)
	resource_changed.emit(resource_type, get_amount(resource_type))


func add_amount(resource_type: int, amount: int) -> void:
	set_amount(resource_type, get_amount(resource_type) + amount)


func can_afford(cost: Dictionary) -> bool:
	for resource_type in cost.keys():
		if get_amount(resource_type) < cost[resource_type]:
			return false

	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false

	for resource_type in cost.keys():
		add_amount(resource_type, -cost[resource_type])

	return true


static func get_display_name_for_type(resource_type: int) -> String:
	match resource_type:
		GameTypes.ResourceType.WOOD:
			return "Wood"
		GameTypes.ResourceType.STONE:
			return "Stone"
		GameTypes.ResourceType.PLANKS:
			return "Planks"
		_:
			return "Unknown"

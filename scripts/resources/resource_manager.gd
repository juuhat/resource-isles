class_name ResourceManager
extends RefCounted

signal resource_changed(resource_type: int, amount: int)

enum ResourceType {
	WOOD,
	STONE,
}

var amounts: Dictionary = {
	ResourceType.WOOD: 0,
	ResourceType.STONE: 0,
}


func get_amount(resource_type: int) -> int:
	return amounts.get(resource_type, 0)


func set_amount(resource_type: int, amount: int) -> void:
	amounts[resource_type] = max(amount, 0)
	resource_changed.emit(resource_type, get_amount(resource_type))


func add_amount(resource_type: int, amount: int) -> void:
	set_amount(resource_type, get_amount(resource_type) + amount)


func get_display_name(resource_type: int) -> String:
	match resource_type:
		ResourceType.WOOD:
			return "Wood"
		ResourceType.STONE:
			return "Stone"
		_:
			return "Unknown"

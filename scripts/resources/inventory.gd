class_name Inventory
extends RefCounted

# A stock of resources owned by one thing. Each island has its own Inventory
# (per-island inventory; no global pool — see docs/island-unlocks.md). Boat cargo
# holds will reuse this same class once inter-island transfer lands.

signal changed(resource_type: int, amount: int)

var amounts: Dictionary = {}


func _init(initial_amounts: Dictionary = {}) -> void:
	for resource_type in initial_amounts.keys():
		amounts[resource_type] = maxi(int(initial_amounts[resource_type]), 0)


func get_amount(resource_type: int) -> int:
	return amounts.get(resource_type, 0)


func set_amount(resource_type: int, amount: int) -> void:
	amounts[resource_type] = maxi(amount, 0)
	changed.emit(resource_type, get_amount(resource_type))


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

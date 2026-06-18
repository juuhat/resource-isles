class_name ResourceManager
extends RefCounted

# Facade over the *current* island's Inventory. Inventory is per-island (no global
# pool — see docs/island-unlocks.md); this keeps a stable signal/API for the UI and
# placement logic while the active island swaps underneath. Point it at an island's
# inventory with set_inventory() whenever the player switches islands.

signal resource_changed(resource_type: int, amount: int)

var inventory: Inventory


func set_inventory(new_inventory: Inventory) -> void:
	if inventory == new_inventory:
		return

	if inventory != null and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)

	inventory = new_inventory

	if inventory != null:
		inventory.changed.connect(_on_inventory_changed)


func get_amount(resource_type: int) -> int:
	return inventory.get_amount(resource_type) if inventory != null else 0


func set_amount(resource_type: int, amount: int) -> void:
	if inventory != null:
		inventory.set_amount(resource_type, amount)


func add_amount(resource_type: int, amount: int) -> void:
	if inventory != null:
		inventory.add_amount(resource_type, amount)


func can_afford(cost: Dictionary) -> bool:
	return inventory != null and inventory.can_afford(cost)


func spend(cost: Dictionary) -> bool:
	return inventory != null and inventory.spend(cost)


func _on_inventory_changed(resource_type: int, amount: int) -> void:
	resource_changed.emit(resource_type, amount)


static func get_display_name_for_type(resource_type: int) -> String:
	var definition := ResourceDatabase.get_definition(resource_type)
	return definition.display_name if definition != null else "Unknown"

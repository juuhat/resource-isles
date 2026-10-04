class_name BoatCargo
extends RefCounted

# Plain amounts live in the boat dictionary, so existing world save/load carries them.
const SLOT_COUNT := 2
const SLOT_CAPACITY := 20

static func inventory(state: Dictionary) -> Inventory:
	if not state.has("cargo"):
		state.cargo = {}
	var hold := Inventory.new()
	hold.amounts = state.cargo
	return hold

static func occupied_slots(hold: Inventory) -> int:
	var count := 0
	for resource in hold.amounts:
		if hold.get_amount(resource) > 0:
			count += 1
	return count

static func space_for(hold: Inventory, resource: int) -> int:
	if not GameTypes.ResourceType.values().has(resource):
		return 0
	if hold.get_amount(resource) == 0 and occupied_slots(hold) >= SLOT_COUNT:
		return 0
	return maxi(0, SLOT_CAPACITY - hold.get_amount(resource))

# Exact transfers: stale controls or invalid requests never partially spend stock.
static func transfer(hold: Inventory, stock: Inventory, resource: int, amount: int, loading: bool) -> bool:
	if stock == null or amount <= 0 or not GameTypes.ResourceType.values().has(resource):
		return false
	var source := stock if loading else hold
	var destination := hold if loading else stock
	if source.get_amount(resource) < amount or (loading and space_for(hold, resource) < amount):
		return false
	# Write both sides before notifying observers.
	source.amounts[resource] = source.get_amount(resource) - amount
	destination.amounts[resource] = destination.get_amount(resource) + amount
	source.changed.emit(resource, source.get_amount(resource))
	destination.changed.emit(resource, destination.get_amount(resource))
	return true

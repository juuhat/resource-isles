class_name PowerManager
extends RefCounted

# Power is a constant MW rate balance, not a stockpile: running generators add
# capacity, producers draw it. This manager burns generator fuel on its interval,
# tracks which generators are running, and reports the island's generation/demand.
# Phase 1 only reports the balance; throttling consumers comes in Phase 2.

signal power_changed(generated: int, consumed: int)
signal fuel_consumed(anchor_cell: Vector2i, resource_type: int, amount: int)

var building_manager: BuildingManager
var resource_manager: ResourceManager
var total_generated: int = 0
var total_consumed: int = 0


func setup(new_building_manager: BuildingManager, new_resource_manager: ResourceManager) -> void:
	building_manager = new_building_manager
	resource_manager = new_resource_manager


func update(
	island: IslandData,
	current_time_seconds: float,
	operated_cell: Vector2i = Vector2i(-1, -1)
) -> void:
	if island == null:
		return

	var generated := 0
	for anchor_cell in island.buildings.keys():
		var definition := building_manager.get_definition(island.buildings[anchor_cell].type)
		if definition == null or definition.power_generated <= 0:
			continue
		if _update_generator(anchor_cell, definition, island, current_time_seconds):
			generated += definition.power_generated

	var consumed := _allocate_power(island, generated, operated_cell)

	if generated != total_generated or consumed != total_consumed:
		total_generated = generated
		total_consumed = consumed
		power_changed.emit(generated, consumed)


# Hands generated capacity to consumers in placement order (first built keeps power
# when supply is short), filling leftover MW with any smaller consumer that still
# fits. Marks each consumer powered/unpowered and returns total demand so the
# readout can show a deficit.
#
# The building the robot is operating (operated_cell) is hand-powered for free: it is
# always marked powered and its draw is left out of both the pool and the reported
# demand, since the robot supplies it directly (the tier-0 "pedal it yourself" power).
func _allocate_power(island: IslandData, generated: int, operated_cell: Vector2i) -> int:
	var remaining := generated
	var demand := 0

	for anchor_cell in island.buildings.keys():
		var definition := building_manager.get_definition(island.buildings[anchor_cell].type)
		if definition == null or definition.power_consumed <= 0:
			continue

		if anchor_cell == operated_cell:
			island.set_consumer_powered(anchor_cell, true)
			continue

		demand += definition.power_consumed
		var powered := remaining >= definition.power_consumed
		if powered:
			remaining -= definition.power_consumed
		island.set_consumer_powered(anchor_cell, powered)

	return demand


# True while the generator is producing power. Fuel-less generators always run;
# fuelled ones run for as long as their last burn succeeded.
func _update_generator(
	anchor_cell: Vector2i,
	definition: BuildingDefinition,
	island: IslandData,
	current_time_seconds: float
) -> bool:
	if definition.fuel_resource_type == -1 or definition.fuel_interval_seconds <= 0.0:
		return true

	# Burn immediately on placement, then once per interval.
	if not island.has_fuel_time(anchor_cell):
		return _burn_and_schedule(anchor_cell, definition, island, current_time_seconds)

	if current_time_seconds < island.get_next_fuel_time(anchor_cell):
		return island.is_generator_running(anchor_cell)

	return _burn_and_schedule(anchor_cell, definition, island, current_time_seconds)


func _burn_and_schedule(
	anchor_cell: Vector2i,
	definition: BuildingDefinition,
	island: IslandData,
	current_time_seconds: float
) -> bool:
	var running := resource_manager.spend({definition.fuel_resource_type: definition.fuel_amount})
	island.set_generator_running(anchor_cell, running)
	island.set_next_fuel_time(anchor_cell, current_time_seconds + definition.fuel_interval_seconds)
	if running:
		fuel_consumed.emit(anchor_cell, definition.fuel_resource_type, definition.fuel_amount)
	return running

class_name ProductionManager
extends RefCounted

signal produced(anchor_cell: Vector2i, resource_type: int, amount: int)
signal input_consumed(anchor_cell: Vector2i, resource_type: int, amount: int)

var building_manager: BuildingManager
var resource_manager: ResourceManager


func setup(new_building_manager: BuildingManager, new_resource_manager: ResourceManager) -> void:
	building_manager = new_building_manager
	resource_manager = new_resource_manager


func update(island: IslandData, current_time_seconds: float) -> void:
	if island == null:
		return

	for anchor_cell in island.buildings.keys():
		var building_type: int = island.buildings[anchor_cell].type
		var definition := building_manager.get_definition(building_type)
		if definition == null or definition.production_resource_type == -1:
			continue

		if definition.production_interval_seconds <= 0.0:
			continue

		# An unpowered consumer is paused: skip without advancing its timer so it
		# resumes where it left off once power returns.
		if definition.power_consumed > 0 and not island.is_consumer_powered(anchor_cell):
			continue

		# Newly placed buildings wait one full interval before their first payout.
		if not island.has_production_time(anchor_cell):
			island.set_next_production_time(
				anchor_cell,
				current_time_seconds + definition.production_interval_seconds
			)
			continue

		if current_time_seconds < island.get_next_production_time(anchor_cell):
			continue

		var amount := building_manager.get_production_amount(anchor_cell, building_type, island)

		# A processor pays for one batch of input up front. If stock is short it
		# stalls without advancing its timer, paying out the instant input arrives.
		if amount > 0 and definition.input_resource_type != -1:
			if not resource_manager.spend({definition.input_resource_type: definition.input_amount}):
				continue
			input_consumed.emit(anchor_cell, definition.input_resource_type, definition.input_amount)

		if amount > 0:
			resource_manager.add_amount(definition.production_resource_type, amount)
			produced.emit(anchor_cell, definition.production_resource_type, amount)

		island.set_next_production_time(
			anchor_cell,
			current_time_seconds + definition.production_interval_seconds
		)

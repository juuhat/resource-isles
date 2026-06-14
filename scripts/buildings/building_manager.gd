class_name BuildingManager
extends RefCounted

const BuildingDefinitionScript := preload("res://scripts/buildings/building_definition.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HUB_TEXTURE := preload("res://assets/buildings/hub.png")
const LOGGER_CAMP_TEXTURE := preload("res://assets/buildings/logger_camp.png")

var definitions: Dictionary = {}
var resource_node_database: ResourceNodeDatabase


func _init() -> void:
	_add_definition(BuildingDefinitionScript.new(
		GameTypes.BuildingType.HUB,
		"Hub",
		HUB_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 8,
			GameTypes.ResourceType.STONE: 4,
		}
	))

	var logger_camp := BuildingDefinitionScript.new(
		GameTypes.BuildingType.LOGGER_CAMP,
		"Logger's Camp",
		LOGGER_CAMP_TEXTURE,
		{
			GameTypes.ResourceType.WOOD: 6,
		}
	)
	# Must touch a forest, earns +1 per adjacent forest, but crowding other
	# camps strips the surrounding woodland faster than it regrows: -1 each.
	logger_camp.required_adjacent = [_resource_ref(GameTypes.ResourceNodeType.TREE)]
	logger_camp.adjacency_yields = [
		_yield_rule(GameTypes.AdjacencyKind.RESOURCE, GameTypes.ResourceNodeType.TREE, 1),
		_yield_rule(GameTypes.AdjacencyKind.BUILDING, GameTypes.BuildingType.LOGGER_CAMP, -1),
	]
	_add_definition(logger_camp)


func setup(new_resource_node_database: ResourceNodeDatabase) -> void:
	resource_node_database = new_resource_node_database


func get_footprint_cells(anchor_cell: Vector2i, building_type: int) -> Array[Vector2i]:
	return [anchor_cell]


func can_place(anchor_cell: Vector2i, building_type: int, island: IslandData) -> bool:
	var definition := get_definition(building_type)
	if definition == null:
		return false

	var footprint := get_footprint_cells(anchor_cell, building_type)
	if not island.can_place_building(anchor_cell, footprint, definition.required_terrain):
		return false

	var neighbors := _footprint_neighbors(footprint)

	for required in definition.required_adjacent:
		if not _any_neighbor_matches(neighbors, required, island):
			return false

	for forbidden in definition.forbidden_adjacent:
		if _any_neighbor_matches(neighbors, forbidden, island):
			return false

	return true


func try_place(anchor_cell: Vector2i, building_type: int, island: IslandData) -> bool:
	if not can_place(anchor_cell, building_type, island):
		return false

	var definition := get_definition(building_type)
	var footprint := get_footprint_cells(anchor_cell, building_type)
	return island.place_building(anchor_cell, building_type, footprint, definition.required_terrain)


# Returns { total: int, breakdown: Array[{ label, count, amount }] }.
func get_adjacency_yield(anchor_cell: Vector2i, building_type: int, island: IslandData) -> Dictionary:
	var result := {total = 0, breakdown = []}
	var definition := get_definition(building_type)
	if definition == null or definition.adjacency_yields.is_empty():
		return result

	var neighbors := _footprint_neighbors(get_footprint_cells(anchor_cell, building_type))

	for rule in definition.adjacency_yields:
		var count := 0
		for neighbor in neighbors:
			if _cell_matches(neighbor, rule, island):
				count += 1

		if count == 0:
			continue

		var amount := count * int(rule.amount)
		result.total += amount
		result.breakdown.append({
			label = _ref_label(rule),
			count = count,
			amount = amount,
		})

	return result


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


func _footprint_neighbors(footprint_cells: Array[Vector2i]) -> Array[Vector2i]:
	var footprint_lookup := {}
	for cell in footprint_cells:
		footprint_lookup[cell] = true

	var neighbors: Array[Vector2i] = []
	var seen := {}

	for cell in footprint_cells:
		for neighbor in HexGridScript.neighbors(cell):
			if footprint_lookup.has(neighbor) or seen.has(neighbor):
				continue

			seen[neighbor] = true
			neighbors.append(neighbor)

	return neighbors


func _any_neighbor_matches(neighbors: Array[Vector2i], reference: Dictionary, island: IslandData) -> bool:
	for neighbor in neighbors:
		if _cell_matches(neighbor, reference, island):
			return true

	return false


func _cell_matches(cell: Vector2i, reference: Dictionary, island: IslandData) -> bool:
	match int(reference.kind):
		GameTypes.AdjacencyKind.TERRAIN:
			return island.is_in_bounds(cell) and island.get_terrain(cell) == int(reference.type)
		GameTypes.AdjacencyKind.RESOURCE:
			return island.get_resource_node_type(cell) == int(reference.type)
		GameTypes.AdjacencyKind.BUILDING:
			return island.get_building_type(cell) == int(reference.type)
		_:
			return false


func _ref_label(reference: Dictionary) -> String:
	match int(reference.kind):
		GameTypes.AdjacencyKind.TERRAIN:
			return GameTypes.terrain_display_name(int(reference.type))
		GameTypes.AdjacencyKind.RESOURCE:
			if resource_node_database != null:
				var node_definition := resource_node_database.get_definition(int(reference.type))
				if node_definition != null:
					return node_definition.display_name
			return "Resource"
		GameTypes.AdjacencyKind.BUILDING:
			return get_display_name(int(reference.type))
		_:
			return "Unknown"


func _resource_ref(resource_node_type: int) -> Dictionary:
	return {kind = GameTypes.AdjacencyKind.RESOURCE, type = resource_node_type}


func _yield_rule(kind: int, type: int, amount: int) -> Dictionary:
	return {kind = kind, type = type, amount = amount}


func _add_definition(definition: BuildingDefinition) -> void:
	definitions[definition.id] = definition

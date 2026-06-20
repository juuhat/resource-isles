class_name BuildingManager
extends RefCounted

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const BuildingDefinitionsScript := preload("res://scripts/buildings/building_definitions.gd")

var definitions: Dictionary = {}
var resource_node_database: ResourceNodeDatabase


func _init() -> void:
	for definition in BuildingDefinitionsScript.build_all():
		_add_definition(definition)


func setup(new_resource_node_database: ResourceNodeDatabase) -> void:
	resource_node_database = new_resource_node_database


func get_footprint_cells(anchor_cell: Vector2i, building_type: int) -> Array[Vector2i]:
	return [anchor_cell]


func can_place(anchor_cell: Vector2i, building_type: int, island: IslandData) -> bool:
	var definition := get_definition(building_type)
	if definition == null:
		return false

	var footprint := get_footprint_cells(anchor_cell, building_type)
	if not island.can_place_building(anchor_cell, footprint, definition.required_terrains):
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
	return island.place_building(anchor_cell, building_type, footprint, definition.required_terrains)


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


# Neighbor cells that change this building's output at anchor_cell, split by sign.
# Drives the placement-preview yield highlight: positive = deposits it would tap,
# negative = crowding penalties (e.g. an adjacent same-type extractor).
func get_yield_cells(anchor_cell: Vector2i, building_type: int, island: IslandData) -> Dictionary:
	var result := {positive = [] as Array[Vector2i], negative = [] as Array[Vector2i]}
	var definition := get_definition(building_type)
	if definition == null or definition.adjacency_yields.is_empty():
		return result

	var neighbors := _footprint_neighbors(get_footprint_cells(anchor_cell, building_type))

	for rule in definition.adjacency_yields:
		var amount := int(rule.amount)
		if amount == 0:
			continue
		for neighbor in neighbors:
			if _cell_matches(neighbor, rule, island):
				if amount > 0:
					result.positive.append(neighbor)
				else:
					result.negative.append(neighbor)

	return result


# Per-tick output for a placed building: base plus adjacency total, never below zero.
func get_production_amount(anchor_cell: Vector2i, building_type: int, island: IslandData) -> int:
	var definition := get_definition(building_type)
	if definition == null or definition.production_resource_type == -1:
		return 0

	var bonus: int = get_adjacency_yield(anchor_cell, building_type, island).total
	return maxi(0, definition.production_base_amount + bonus)


func get_definition(building_type: int) -> BuildingDefinition:
	return definitions.get(building_type)


func get_definitions_for_category(category: int) -> Array[BuildingDefinition]:
	var matching: Array[BuildingDefinition] = []
	for definition in definitions.values():
		if definition.category == category:
			matching.append(definition)

	matching.sort_custom(func(a: BuildingDefinition, b: BuildingDefinition) -> bool:
		return a.id < b.id
	)
	return matching


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


func _add_definition(definition: BuildingDefinition) -> void:
	definitions[definition.id] = definition

extends SceneTree

# The three kinds of tree stand, pine, leaf and palm: their models, the ground each grows on, a
# logger camp felling any of them, their design letters, the starter island having all three, and
# saves keeping them.

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const LOGGER := GameTypes.BuildingType.LOGGER_CAMP
# Each kind of tree and the ground it grows on.
const TREES := {
	GameTypes.ResourceNodeType.TREE: GameTypes.Terrain.GRASS,
	GameTypes.ResourceNodeType.LEAF_TREE: GameTypes.Terrain.GRASS,
	GameTypes.ResourceNodeType.PALM_TREE: GameTypes.Terrain.SAND,
}
var failures := 0


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	CheckWatchdog.install(self)
	var database := ResourceNodeDatabase.new()
	_check_definitions(database)
	_check_logger_camp(database)
	_check_starter()
	print("Tree deposits: PASS" if failures == 0 else "Tree deposits: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _check_definitions(database: ResourceNodeDatabase) -> void:
	var names := {}
	for node_type in TREES:
		var definition := database.get_definition(node_type)
		expect(definition != null and definition.extracted_resource_type == GameTypes.ResourceType.WOOD,
			"Tree type %d yields wood" % node_type)
		expect(GameTypes.is_tree(node_type), "%s counts as a tree" % definition.display_name)
		expect(definition.model != null and definition.true_tile_model, "%s has a tile-scale model" % definition.display_name)
		var instance := definition.model.instantiate()
		expect(instance.get_node_or_null("Footprint") != null, "%s exports its footprint" % definition.display_name)
		instance.free()
		names[definition.display_name] = true
		var island := IslandData.new(3, 3)
		for terrain in GameTypes.LAND_TERRAINS:
			island.set_terrain(Vector2i(1, 1), terrain)
			expect(island.can_place_resource(Vector2i(1, 1), node_type) == (terrain == TREES[node_type]),
				"%s grows on %s only" % [definition.display_name, GameTypes.terrain_display_name(TREES[node_type])])
	expect(names.size() == TREES.size(), "Each kind of tree has its own name")
	for node_type in [GameTypes.ResourceNodeType.STONE, GameTypes.ResourceNodeType.COPPER_ORE, -1]:
		expect(not GameTypes.is_tree(node_type), "Type %d is no tree" % node_type)
	expect(IslandDesign.LEGEND["L"].resource == GameTypes.ResourceNodeType.LEAF_TREE
		and IslandDesign.LEGEND["L"].terrain == GameTypes.Terrain.GRASS, "L draws leaf trees on grass")
	expect(IslandDesign.LEGEND["P"].resource == GameTypes.ResourceNodeType.PALM_TREE
		and IslandDesign.LEGEND["P"].terrain == GameTypes.Terrain.SAND, "P draws palms on sand")


# A logger camp needs trees beside it, of any kind, and earns one more wood per stand, whatever
# mix of kinds surrounds it.
func _check_logger_camp(database: ResourceNodeDatabase) -> void:
	var manager := BuildingManager.new()
	manager.setup(database)
	var camp := Vector2i(2, 2)
	for node_type in TREES:
		var island := _grass_island()
		expect(not manager.can_place(camp, LOGGER, island), "No logger camp without trees")
		var neighbor: Vector2i = HexGridScript.neighbors(camp)[0]
		island.set_terrain(neighbor, TREES[node_type])
		expect(island.place_resource(neighbor, node_type), "Tree type %d grows beside the camp" % node_type)
		expect(manager.can_place(camp, LOGGER, island), "A logger camp goes beside tree type %d" % node_type)
		expect(manager.get_production_amount(camp, LOGGER, island) == 2, "One stand of tree type %d adds a wood" % node_type)
	var mixed := _grass_island()
	var neighbors := HexGridScript.neighbors(camp)
	var index := 0
	for node_type in TREES:
		mixed.set_terrain(neighbors[index], TREES[node_type])
		mixed.place_resource(neighbors[index], node_type)
		index += 1
	expect(manager.get_production_amount(camp, LOGGER, mixed) == 1 + TREES.size(), "Mixed stands each add a wood")
	var adjacency := manager.get_adjacency_yield(camp, LOGGER, mixed)
	expect(adjacency.breakdown.size() == 1 and adjacency.breakdown[0].label == "Forest"
		and adjacency.breakdown[0].count == TREES.size(), "The camp's info counts every stand as forest")
	mixed.set_terrain(neighbors[index], GameTypes.Terrain.STONE)
	mixed.place_resource(neighbors[index], GameTypes.ResourceNodeType.STONE)
	expect(manager.get_production_amount(camp, LOGGER, mixed) == 1 + TREES.size(), "Stone beside the camp adds no wood")


func _grass_island() -> IslandData:
	var island := IslandData.new(5, 5)
	for cell in island.terrain.keys():
		island.set_terrain(cell, GameTypes.Terrain.GRASS)
	return island


# The crash site grows all three, each on its own ground, and they survive a save.
func _check_starter() -> void:
	for placement in WorldMap.load_file().placements:
		if not placement.start:
			continue
		var island := IslandDesign.load_named(placement.design).build(placement.center, placement.rotation,
			placement.mirror, BuildingManager.new())
		for node_type in TREES:
			expect(island.resources.values().has(node_type), "The starter island has tree type %d" % node_type)
		for cell in island.resources:
			var node_type: int = island.resources[cell]
			if GameTypes.is_tree(node_type):
				expect(island.get_terrain(cell) == TREES[node_type], "Tree type %d at %s is on its own ground" % [node_type, cell])
		var saved: Dictionary = bytes_to_var(var_to_bytes(island.to_dict(0)))
		expect(IslandData.from_dict(saved, 0).resources == island.resources, "Every tree survives a binary save and load")
		return
	expect(false, "The world map has a starter island")

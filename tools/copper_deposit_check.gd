extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const NODE := GameTypes.ResourceNodeType.COPPER_ORE
const ORE := GameTypes.ResourceType.COPPER_ORE
var failures := 0

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	CheckWatchdog.install(self)
	var definition := ResourceNodeDatabase.new().get_definition(NODE)
	expect(definition != null and definition.extracted_resource_type == ORE, "Copper deposit yields copper ore")
	expect(definition.model != null and definition.true_tile_model, "Copper has a tile-scale model")
	expect(ResourceDatabase.get_definition(ORE).icon != null, "Copper inventory icon loads")
	var instance := definition.model.instantiate()
	expect(instance.get_node_or_null("Footprint") != null, "Copper exports its solid footprint")
	instance.free()
	# On the world map, K9-DA's rescue island is the one copper destination within reach of the
	# first ring, and the start island has none.
	var copper_island: IslandData
	var copper_count := 0
	for placement in WorldMap.load_file().placements:
		var island := IslandDesign.load_named(placement.design).build(placement.center, placement.rotation,
			placement.mirror, BuildingManager.new())
		if placement.start:
			expect(not island.resources.values().has(NODE), "Starter has no copper")
		if not island.resources.values().has(NODE):
			continue
		expect(placement.k9da, "Copper is on the rescue island, not %s" % placement.id)
		if WorldData.rings_out(placement.center) < 1.5:
			copper_count += 1
		copper_island = island
		expect(copper_island.resources.values().count(NODE) >= 3, "Copper island has its required deposits")
		expect(copper_island.resources.values().count(GameTypes.ResourceNodeType.STONE) >= 3, "Copper island supplies local stone")
		expect(not copper_island.resources.values().has(GameTypes.ResourceNodeType.IRON_ORE), "Copper island has no iron")
		expect(not copper_island.resources.values().has(GameTypes.ResourceNodeType.COAL), "Copper island has no coal")
		for cell in copper_island.resources:
			if copper_island.get_resource_node_type(cell) == NODE:
				expect(copper_island.get_terrain(cell) == GameTypes.Terrain.STONE, "Copper is placed on rock")
				expect(copper_island.can_scavenge(cell), "Copper can be scavenged")
	expect(copper_count == 1 and copper_island != null, "Exactly one ring-1 copper destination")
	var tracker := StatTracker.new()
	copper_island.inventory.add_amount(ORE, definition.scavenge_amount)
	tracker.record_resource_gained(ORE, definition.scavenge_amount)
	expect(tracker.lifetime_gathered(ORE) == 3, "Copper gains reveal the resource and track lifetime totals")
	var saved: Dictionary = bytes_to_var(var_to_bytes(copper_island.to_dict(0)))
	var restored := IslandData.from_dict(saved, 0)
	expect(restored.inventory.get_amount(ORE) == 3 and restored.resources.values().has(NODE), "Copper nodes and stock survive binary save/load")
	var hold := BoatCargo.inventory({})
	expect(BoatCargo.transfer(hold, restored.inventory, ORE, 3, true), "Copper loads into boat cargo")
	expect(BoatCargo.transfer(hold, restored.inventory, ORE, 3, false), "Copper unloads from boat cargo")
	print("Copper deposits: PASS" if failures == 0 else "Copper deposits: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

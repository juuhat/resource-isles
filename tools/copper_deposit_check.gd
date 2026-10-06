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
	var generator := IslandGenerator.new()
	var copper_island: IslandData
	for seed_value in range(-3, 21):
		var copper_count := 0
		for coord in WorldData.slots_within(1).slice(1):
			var biome := IslandProfiles.biome_for_coord(coord, seed_value)
			if coord == WorldData.dog_slot_for_seed(seed_value):
				expect(biome == IslandProfiles.Biome.COPPER, "Rescue island is the copper island")
			if biome != IslandProfiles.Biome.COPPER:
				continue
			copper_count += 1
			copper_island = generator.generate(IslandProfiles.get_profile(biome), seed_value)
			expect(copper_island.resources.values().count(NODE) >= 3, "Copper island has its required deposits")
			expect(copper_island.resources.values().count(GameTypes.ResourceNodeType.STONE) >= 3, "Copper island supplies local stone")
			expect(not copper_island.resources.values().has(GameTypes.ResourceNodeType.IRON_ORE), "Copper island has no iron")
			expect(not copper_island.resources.values().has(GameTypes.ResourceNodeType.COAL), "Copper island has no coal")
			for cell in copper_island.resources:
				if copper_island.get_resource_node_type(cell) == NODE:
					expect(copper_island.get_terrain(cell) == GameTypes.Terrain.STONE, "Copper is placed on rock")
					expect(copper_island.can_scavenge(cell), "Copper can be scavenged")
		var starter := generator.generate(IslandProfiles.get_profile(IslandProfiles.Biome.STARTER), seed_value, BuildingManager.new())
		expect(not starter.resources.values().has(NODE), "Starter has no copper")
		expect(copper_count == 1, "Exactly one ring-1 copper destination per seed")
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

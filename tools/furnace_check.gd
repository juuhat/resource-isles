extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const FURNACE := GameTypes.BuildingType.FURNACE
const ORE := GameTypes.ResourceType.IRON_ORE
const COAL := GameTypes.ResourceType.COAL
const INGOT := GameTypes.ResourceType.IRON_INGOT
const COPPER_ORE := GameTypes.ResourceType.COPPER_ORE
const COPPER_INGOT := GameTypes.ResourceType.COPPER_INGOT
const WOOD := GameTypes.ResourceType.WOOD
const GameScene := preload("res://game.tscn")
var failures := 0

func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func _run() -> void:
	_check_production()
	_check_recipes()
	_check_quests()
	_check_model()
	await _check_scene()
	print("Furnace: PASS" if failures == 0 else "Furnace: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _check_production() -> void:
	var manager := BuildingManager.new()
	var production := ProductionManager.new()
	production.setup(manager)
	var power := PowerManager.new()
	power.setup(manager)
	var island := IslandData.new(3, 3)
	for y in 3:
		for x in 3:
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.GRASS)
	var cell := Vector2i(1, 1)
	expect(manager.try_place(cell, FURNACE, island, 0, true), "Furnace blueprint fits land without a deposit")
	expect(island.get_recipe(cell) == COPPER_INGOT, "A new Furnace starts on its copper recipe")
	island.set_recipe(cell, INGOT)
	island.inventory.add_amount(ORE, 6)
	island.inventory.add_amount(COAL, 3)
	production.update(island, 0)
	production.update(island, 10)
	expect(not island.has_production_time(cell) and island.inventory.get_amount(INGOT) == 0, "Blueprint does not smelt")
	island.complete_construction(cell)
	power.update(island, 0)
	expect(power.total_generated == 0 and power.total_consumed == 2, "Bellows require power")
	production.update(island, 0)
	production.update(island, 10)
	expect(island.inventory.get_amount(INGOT) == 0 and island.inventory.get_amount(ORE) == 6, "Idle Furnace preserves inputs")
	power.update(island, 0, cell)
	expect(island.is_consumer_powered(cell) and power.total_consumed == 0, "Robot drives bellows without electricity")
	production.update(island, 0)
	production.update(island, 5)
	expect(island.inventory.get_amount(INGOT) == 0, "Waits a full batch interval")
	production.update(island, 6)
	expect(island.inventory.get_amount(INGOT) == 1 and island.inventory.get_amount(ORE) == 4 and island.inventory.get_amount(COAL) == 2, "Consumes ore and coal for one ingot")
	island.inventory.set_amount(COAL, 0)
	production.update(island, 12)
	expect(island.inventory.get_amount(ORE) == 4 and island.inventory.get_amount(INGOT) == 1, "Missing coal does not waste ore")
	island.inventory.add_amount(COAL, 1)
	production.update(island, 12.1)
	expect(island.inventory.get_amount(INGOT) == 2, "Resumes when coal arrives")
	island.inventory.set_amount(ORE, 0)
	island.inventory.add_amount(COAL, 1)
	production.update(island, 19)
	expect(island.inventory.get_amount(COAL) == 1 and island.inventory.get_amount(INGOT) == 2, "Missing ore does not waste coal")
	island.inventory.add_amount(ORE, 2)
	production.update(island, 19.1)
	var restored := IslandData.from_dict(island.to_dict(19.1), 100)
	expect(restored.inventory.get_amount(INGOT) == 3 and restored.get_building_type(cell) == FURNACE, "Ingot inventory and Furnace survive save round trip")
	expect(restored.get_recipe(cell) == INGOT, "The Furnace's recipe survives a save round trip")
	production.update(restored, 105)
	expect(restored.inventory.get_amount(INGOT) == 3, "Save preserves remaining batch time")
	power.update(island, 20)
	production.update(island, 30)
	expect(island.inventory.get_amount(INGOT) == 3, "Stopping Operate pauses smelting")
	expect(manager.try_place(Vector2i(2, 2), GameTypes.BuildingType.BURNER_GENERATOR, island), "Place generator")
	island.inventory.add_amount(GameTypes.ResourceType.WOOD, 10)
	island.inventory.add_amount(ORE, 2)
	island.inventory.add_amount(COAL, 1)
	power.update(island, 30)
	production.update(island, 30)
	expect(island.is_consumer_powered(cell) and island.inventory.get_amount(INGOT) == 4, "Generator takes over bellows")
	# Existing single-input recipes still work, and still respect power.
	var saw := Vector2i.ZERO
	expect(manager.try_place(saw, GameTypes.BuildingType.SAWMILL, island), "Place existing sawmill")
	island.inventory.set_amount(GameTypes.ResourceType.WOOD, 2)
	production.update(island, 20)
	expect(not island.has_production_time(saw), "Unpowered sawmill remains paused")
	island.set_consumer_powered(saw, true)
	production.update(island, 20)
	production.update(island, 23)
	expect(island.inventory.get_amount(GameTypes.ResourceType.PLANKS) == 1 and island.inventory.get_amount(GameTypes.ResourceType.WOOD) == 0, "Single-input sawmill recipe still works")


# The Furnace smelts copper over wood, or iron with coal, as set on each one.
func _check_recipes() -> void:
	var manager := BuildingManager.new()
	var production := ProductionManager.new()
	production.setup(manager)
	var island := IslandData.new(2, 1)
	island.set_terrain(Vector2i(0, 0), GameTypes.Terrain.GRASS)
	island.set_terrain(Vector2i(1, 0), GameTypes.Terrain.GRASS)
	var cell := Vector2i(0, 0)
	expect(manager.try_place(cell, FURNACE, island), "Place a Furnace")
	island.set_consumer_powered(cell, true)
	island.inventory.add_amount(COPPER_ORE, 2)
	island.inventory.add_amount(WOOD, 1)
	island.inventory.add_amount(ORE, 2)
	island.inventory.add_amount(COAL, 1)
	production.update(island, 0)
	production.update(island, 6)
	expect(island.inventory.get_amount(COPPER_INGOT) == 1 and island.inventory.get_amount(COPPER_ORE) == 0 and island.inventory.get_amount(WOOD) == 0,
		"The copper recipe smelts 2 copper ore with 1 wood into a copper ingot")
	expect(island.inventory.get_amount(ORE) == 2 and island.inventory.get_amount(COAL) == 1, "The copper recipe leaves iron ore and coal alone")
	island.set_recipe(cell, INGOT)
	production.update(island, 12)
	expect(island.inventory.get_amount(INGOT) == 1 and island.inventory.get_amount(ORE) == 0, "Switching to the iron recipe smelts iron")
	# A Furnace saved before recipes existed only smelted iron.
	var legacy := island.to_dict(12)
	(legacy.buildings[cell] as Dictionary).erase("recipe")
	var loaded := IslandData.from_dict(legacy, 0)
	expect(loaded.get_recipe(cell) == -1, "An old save's Furnace has no recipe")
	manager.migrate_recipes(loaded)
	expect(loaded.get_recipe(cell) == INGOT, "Loading keeps an old Furnace on iron")
	var definition := manager.get_definition(FURNACE)
	expect(definition.recipes.size() == 2 and definition.recipes[0].output == COPPER_INGOT, "The Furnace lists copper, then iron")


func _check_quests() -> void:
	var stats := StatTracker.new()
	var quests := QuestManager.new()
	quests.setup(stats)
	expect(not quests.is_building_unlocked(FURNACE), "Furnace locked before rescue")
	expect(not quests.is_building_unlocked(GameTypes.BuildingType.WINDMILL), "Windmill cannot bypass rescue")
	for entry in [
		[GameTypes.Stat.TOOLS_COLLECTED, 3], [GameTypes.Stat.WOOD_GATHERED, 100],
		[GameTypes.Stat.STONE_GATHERED, 100], [GameTypes.Stat.LOGGER_CAMPS_BUILT, 1],
		[GameTypes.Stat.QUARRIES_BUILT, 1], [GameTypes.Stat.BUILDINGS_OPERATED, 1],
		[GameTypes.Stat.SAWMILLS_BUILT, 1], [GameTypes.Stat.PLANKS_GATHERED, 12],
		[GameTypes.Stat.DOCKS_BUILT, 1], [GameTypes.Stat.DOG_ISLAND_DISCOVERED, 1]]:
		stats.add(entry[0], entry[1])
	expect(quests.get_current_milestone().id == GameTypes.QuestId.COPPER_GLINT, "Copper follows finding K9-DA's island")
	expect(not quests.is_upgrade_active(GameTypes.RobotUpgrade.CARGO_HOLD), "The cargo hold waits for copper")
	stats.add(GameTypes.Stat.COPPER_ORE_GATHERED, 6)
	expect(quests.get_current_milestone().id == GameTypes.QuestId.COPPER_GLINT, "Copper Glint waits for the rescue")
	stats.add(GameTypes.Stat.DOG_RESCUED, 1)
	expect(quests.is_upgrade_active(GameTypes.RobotUpgrade.CARGO_HOLD), "Rescue and copper open the cargo hold")
	expect(quests.get_current_milestone().id == GameTypes.QuestId.HAUL_IT_HOME and not quests.is_building_unlocked(FURNACE), "Copper is hauled home before the Furnace")
	stats.add(GameTypes.Stat.COPPER_ORE_SHIPPED_HOME, 6)
	expect(quests.is_building_unlocked(FURNACE) and quests.get_current_milestone().id == GameTypes.QuestId.FIRST_MELT, "Copper shipped home unlocks the Furnace")
	stats.record_building_built(FURNACE)
	stats.record_resource_gained(COPPER_INGOT, 3)
	expect(quests.is_upgrade_active(GameTypes.RobotUpgrade.REPAIRING) and quests.get_current_milestone().id == GameTypes.QuestId.EYES_ON_THE_HORIZON, "Three copper ingots unlock repairing the ship")
	stats.add(GameTypes.Stat.SHIP_PARTS_REPAIRED, 1)
	expect(quests.is_completed(GameTypes.QuestId.EYES_ON_THE_HORIZON) and quests.get_current_milestone().id == GameTypes.QuestId.STRIKE_IRON, "The radar repair leads to iron")
	stats.add(GameTypes.Stat.IRON_ORE_GATHERED, 5)
	expect(quests.get_current_milestone().id == GameTypes.QuestId.LIGHT_THE_FORGE, "Smelting lesson precedes automatic trade")
	expect(not quests.is_building_unlocked(GameTypes.BuildingType.BURNER_GENERATOR), "Early milestones no longer grant electricity")
	stats.record_resource_gained(INGOT, 5)
	expect(not quests.is_building_unlocked(GameTypes.BuildingType.BURNER_GENERATOR), "Five ingots do not unlock generator")
	stats.record_resource_gained(INGOT, 1)
	expect(quests.is_completed(GameTypes.QuestId.LIGHT_THE_FORGE), "Furnace and ingots complete smelting lesson")
	expect(quests.is_building_unlocked(GameTypes.BuildingType.BURNER_GENERATOR), "First ingots unlock generator")
	expect(quests.get_current_milestone().id == GameTypes.QuestId.POWER_ON, "Power On follows six ingots")
	expect(not quests.is_building_unlocked(GameTypes.BuildingType.WINDMILL), "Windmill waits for generator lesson")
	stats.record_building_built(GameTypes.BuildingType.BURNER_GENERATOR)
	expect(quests.is_completed(GameTypes.QuestId.POWER_ON), "Building generator completes Power On")
	expect(quests.get_current_milestone().id == GameTypes.QuestId.THE_SUPPLY_LINE, "Trade lesson follows generator construction")
	expect(quests.is_building_unlocked(GameTypes.BuildingType.WINDMILL), "Power On unlocks Windmill")
	var burner := BuildingManager.new().get_definition(GameTypes.BuildingType.BURNER_GENERATOR)
	expect(burner.cost.get(INGOT) == 6, "Generator construction requires ingots")
	var legacy := QuestManager.new()
	legacy.restore_completed({GameTypes.QuestId.THE_SUPPLY_LINE: true})
	expect(not legacy.is_completed(GameTypes.QuestId.LIGHT_THE_FORGE) and not legacy.is_building_unlocked(GameTypes.BuildingType.BURNER_GENERATOR), "Old trade saves do not silently skip smelting")
	expect(not legacy.is_completed(GameTypes.QuestId.POWER_ON) and not legacy.is_building_unlocked(GameTypes.BuildingType.WINDMILL), "Old trade saves do not silently skip generator lesson")
	var restored := QuestManager.new()
	restored.restore_completed(quests.completed_to_dict())
	expect(restored.is_completed(GameTypes.QuestId.POWER_ON) and restored.is_building_unlocked(GameTypes.BuildingType.WINDMILL), "Completed Power On survives restoration")

func _check_model() -> void:
	var definition := BuildingManager.new().get_definition(FURNACE)
	var model := definition.model.instantiate() as Node3D
	root.add_child(model)
	expect(definition.true_tile_model and model.find_child("WorkSpot", true, false) != null, "Imported Furnace has construction work spot and fixed scale")
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = part if first else bounds.merge(part)
		first = false
	expect(bounds.size.x < 1.5 and bounds.size.z < 1.2 and bounds.position.y >= -0.001, "Model stays inside tile and rests on ground")
	var body := model.find_child("BellowsBody", true, false) as Node3D
	var top := model.find_child("BellowsTop", true, false) as Node3D
	expect(body != null and top != null and model.find_child("DockPoint", true, false) != null, "Articulated bellows and robot socket exist")
	if body != null and top != null:
		var island := IslandData.new(1, 1)
		island.set_terrain(Vector2i.ZERO, GameTypes.Terrain.GRASS)
		BuildingManager.new().try_place(Vector2i.ZERO, FURNACE, island)
		var spinner := PoweredSpinner.new()
		model.add_child(spinner)
		spinner.set_process(false)
		spinner.island = island
		spinner.anchor_cell = Vector2i.ZERO
		spinner.add_bellows(body, top, 0.20, 1.6)
		var rest_scale := body.scale
		var rest_top := top.position
		spinner._process(1)
		expect(body.scale.is_equal_approx(rest_scale), "Unpowered bellows stay still")
		island.set_consumer_powered(Vector2i.ZERO, true)
		spinner._process(0.6)
		expect(body.scale.y < rest_scale.y and top.position.y < rest_top.y, "Bellows contract with moving top")
		var low := body.scale.y
		spinner._process(1.0)
		expect(body.scale.y > low, "Bellows expand again")
		island.set_consumer_powered(Vector2i.ZERO, false)
		spinner._process(2)
		var stopped := body.scale
		spinner._process(1)
		expect(body.scale.is_equal_approx(stopped), "Bellows stop when power ends")
	root.remove_child(model)
	model.free()

func _panel_text(game: Node) -> String:
	var text := ""
	for label in game.building_info_panel.detail_box.find_children("*", "Label", true, false):
		text += label.text + " "
	return text


func _check_scene() -> void:
	var had_save := FileAccess.file_exists(SaveManager.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if had_save else PackedByteArray()
	SaveManager.delete_save()
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	# Haul It Home unlocks the Furnace (and, completing every milestone before it, Operate).
	game.quest_manager.restore_completed({GameTypes.QuestId.HAUL_IT_HOME: true})
	var cell := GameTypes.NO_CELL
	for candidate in game.current_island.terrain:
		if game.building_manager.can_place(candidate, FURNACE, game.current_island) and not game.robot.is_unit_cell(candidate):
			cell = candidate
			break
	expect(cell != GameTypes.NO_CELL, "Find Furnace placement in real scene")
	if cell != GameTypes.NO_CELL:
		game.current_island.inventory.set_amount(GameTypes.ResourceType.WOOD, 4)
		game.current_island.inventory.set_amount(GameTypes.ResourceType.STONE, 12)
		game.selected_building_type = FURNACE
		game.building_manager.get_definition(FURNACE).build_seconds = 0.1
		game.renderer.hovered_cell = cell
		expect(game._try_place_selected_building(), "Unlocked Furnace can enter robot construction")
		expect(game.current_island.is_under_construction(cell) and game.resource_manager.get_amount(GameTypes.ResourceType.STONE) == 0, "Blueprint reserves construction materials")
		for step in 300:
			if not game.player_unit.is_moving():
				break
			game.player_unit._process(0.25)
		expect(game.robot.is_constructing, "Robot reaches Furnace work spot and starts construction")
		game.robot._update_construction(0.2)
		expect(game.current_island.is_building_complete(cell) and game.stat_tracker.get_value(GameTypes.Stat.FURNACES_BUILT) == 1, "Robot completes Furnace and records quest credit")
		game.renderer.refresh()
		var furnace_spinner: PoweredSpinner = null
		for node in game.renderer.find_children("*", "", true, false):
			if node is PoweredSpinner and node.anchor_cell == cell:
				furnace_spinner = node
		expect(furnace_spinner != null, "Renderer attaches powered Furnace animation")
		if furnace_spinner != null:
			expect(furnace_spinner._bellows.size() == 1 and furnace_spinner._targets.size() == 3, "Bellows, cam, flywheel and drive socket are wired")
		game.current_island.inventory.set_amount(COPPER_ORE, 4)
		game.current_island.inventory.set_amount(WOOD, 2)
		game.current_island.set_next_production_time(cell, 0)
		game.power_manager.update(game.current_island, 1)
		game.production_manager.update(game.current_island, 1)
		expect(game.current_island.inventory.get_amount(COPPER_INGOT) == 0, "Real Furnace waits for power")
		game.robot._on_operate_pressed()
		expect(game.robot.is_operating and game.robot.operate_cell == cell, "Furnace offers robot Operate")
		game.power_manager.update(game.current_island, 1, game.robot.operate_cell)
		game.production_manager.update(game.current_island, 1)
		expect(game.stat_tracker.get_value(GameTypes.Stat.COPPER_INGOTS_GATHERED) == 1, "Real production records the copper ingot stat")
		game.building_info_panel.show_building(FURNACE, cell, game.current_island)
		expect(_panel_text(game).contains("Copper Ore") and _panel_text(game).contains("Wood"), "Building panel shows the copper recipe's ingredients")
		# Switch to iron with the panel's recipe button.
		var iron_button: Button = null
		for button: Button in game.building_info_panel.detail_box.find_children("*", "Button", true, false):
			if button.text == "Iron Ingot":
				iron_button = button
		expect(iron_button != null, "The Furnace panel offers the iron recipe")
		if iron_button != null:
			iron_button.pressed.emit()
		expect(game.current_island.get_recipe(cell) == INGOT, "The recipe button switches the Furnace to iron")
		expect(_panel_text(game).contains("Iron Ore") and _panel_text(game).contains("Coal"), "Building panel displays both iron batch ingredients")
		game.current_island.inventory.set_amount(ORE, 12)
		game.current_island.inventory.set_amount(COAL, 6)
		game.power_manager.update(game.current_island, 8, game.robot.operate_cell)
		game.production_manager.update(game.current_island, 8)
		expect(game.stat_tracker.get_value(GameTypes.Stat.IRON_INGOTS_GATHERED) == 1, "Real production records the iron ingot stat")
		if OS.get_cmdline_user_args().has("--screenshot"):
			root.size = Vector2i(1400, 900)
			game.building_menu.clear_selection()
			game.camera_rig.center_on(game.renderer.get_cell_center(cell), true)
			game.camera_rig._distance = 550
			game.camera_rig._target_distance = 550
			for frame in 30:
				await process_frame
			root.get_texture().get_image().save_png("res://.godot/furnace_preview.png")
	root.remove_child(game)
	game.free()
	await process_frame
	SaveManager.delete_save()
	if had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)

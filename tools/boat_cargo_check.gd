extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const Cargo := preload("res://scripts/player/boat_cargo.gd")
const GameScene := preload("res://game.tscn")
const Nav := preload("res://scripts/world/world_navigation.gd")
var failures := 0

func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func _run() -> void:
	root.size = Vector2i(1400, 900)
	_check_hold()
	# Preserve the user's save, as the other gameplay checks do.
	var had_save := FileAccess.file_exists(SaveManager.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if had_save else PackedByteArray()
	SaveManager.delete_save()
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var origin: IslandData = game.current_island
	origin.inventory.set_amount(GameTypes.ResourceType.WOOD, 100)
	var anchor := GameTypes.NO_CELL
	for cell in origin.terrain:
		var rotation: int = game.building_manager.fit_rotation(cell, GameTypes.BuildingType.DOCK, origin, 0)
		if game.building_manager.can_place(cell, GameTypes.BuildingType.DOCK, origin, rotation):
			anchor = cell
			game.renderer.place_building_at(cell, GameTypes.BuildingType.DOCK, rotation)
			break
	expect(anchor != GameTypes.NO_CELL, "Find a dock site")
	if anchor != GameTypes.NO_CELL:
		game.player_unit.place_at(origin.buildings[anchor].cells[1])
		game.player_unit.set_selected(true)
		game.refresh_action_bar()
		expect(game.action_bar.action_row.get_children().any(func(button: Button) -> bool: return button.text == "Cargo"), "Cargo control offered beside initial boat")
		game.boats.open_cargo()
		var id: int = game.boats.cargo_boat_id
		expect(game.player_unit.boat_id == -1 and game.boat_cargo_panel.is_open(), "Open cargo without boarding")
		var hold := Cargo.inventory(game.world.boats[id])
		var ui: BoatCargoPanel = game.boat_cargo_panel
		await process_frame
		await process_frame
		await _drag_slots(ui.island_slots[0], ui.boat_slots[0])
		expect(ui.amount_dialog.visible and ui.amount_picker.value == 20, "Real icon drag prompts with maximum fitting stack")
		expect(hold.get_amount(GameTypes.ResourceType.WOOD) == 0, "Dropping asks before transferring")
		game.boat_cargo_panel.amount_picker.value = 12
		await process_frame
		game.boat_cargo_panel.amount_dialog.confirmed.emit()
		expect(hold.get_amount(GameTypes.ResourceType.WOOD) == 12 and origin.inventory.get_amount(GameTypes.ResourceType.WOOD) == 88, "Load through panel controls")
		ui.boat_slots[0]._drop_data(Vector2.ZERO, ui.island_slots[0].drag_data())
		expect(ui.amount_picker.value == 8, "Merging stack defaults to remaining capacity")
		ui.amount_dialog.hide()
		ui.amount_dialog.canceled.emit()
		expect(hold.get_amount(GameTypes.ResourceType.WOOD) == 12, "Cancelling leaves both inventories unchanged")
		origin.inventory.set_amount(GameTypes.ResourceType.COAL, 4)
		ui.refresh()
		var coal_slot: Control = ui.island_slots[GameTypes.ResourceType.COAL]
		expect(not ui.boat_slots[0]._can_drop_data(Vector2.ZERO, coal_slot.drag_data()), "Different resource cannot overwrite occupied boat slot")
		ui.boat_slots[1]._drop_data(Vector2.ZERO, coal_slot.drag_data())
		expect(ui.amount_picker.value == 4, "Small island stock limits default stack")
		origin.inventory.set_amount(GameTypes.ResourceType.COAL, 2)
		ui.refresh()
		expect(ui.amount_picker.max_value == 2 and ui.amount_picker.value == 2, "Prompt shrinks when source stock changes")
		origin.inventory.set_amount(GameTypes.ResourceType.COAL, 0)
		ui.refresh()
		expect(not ui.amount_dialog.visible, "Prompt closes if source disappears")
		game.boats.board()
		expect(game.player_unit.boat_id == id, "Loading first does not create another boat")
		game._reveal_rings(1)
		var target: Vector2i = game.world.dog_coord
		ui.boat_slots[0]._drop_data(Vector2.ZERO, ui.island_slots[0].drag_data())
		expect(game.boats.sail_to_island(target), "Sail with cargo")
		game.boats.refresh_cargo()
		expect(not ui.amount_dialog.visible, "Moving away cancels pending transfer prompt")
		expect(ui.maximum_transfer(GameTypes.ResourceType.WOOD, true) == 0 and ui.boat_slots[0].drag_data() == null, "Transfers disabled while moving")
		game.boats.transfer(GameTypes.ResourceType.WOOD, 1, false)
		expect(hold.get_amount(GameTypes.ResourceType.WOOD) == 12, "Reject transfer while moving")
		for step in 2000:
			if not game.player_unit.is_moving():
				break
			game.player_unit._process(0.25)
		var away: IslandData = game.world.get_island(target)
		expect(away.buildings.values().all(func(building: Dictionary) -> bool: return int(building.type) != GameTypes.BuildingType.DOCK), "Destination has no dock")
		var before := away.inventory.get_amount(GameTypes.ResourceType.WOOD)
		game.boats.refresh_cargo()
		expect(game.boat_cargo_panel.island == away and game.world.current_coord == game.world.start_coord, "Aboard transfer targets destination, not home")
		ui.island_slots[0]._drop_data(Vector2.ZERO, ui.boat_slots[0].drag_data())
		expect(ui.amount_picker.value == 12, "Unloading defaults to whole boat stack")
		game.boat_cargo_panel.amount_picker.value = 7
		await process_frame
		game.boat_cargo_panel.amount_dialog.confirmed.emit()
		expect(away.inventory.get_amount(GameTypes.ResourceType.WOOD) == before + 7 and origin.inventory.get_amount(GameTypes.ResourceType.WOOD) == 88, "Unload at untouched shoreline through controls")
		game.boats.disembark()
		game.boats.refresh_cargo()
		expect(game.boat_cargo_panel.island == away, "Can transfer standing beside boat after landing")
		ui.island_slots[0]._drop_data(Vector2.ZERO, ui.boat_slots[0].drag_data())
		expect(ui.amount_picker.value == 5, "Default unload updates after split transfer")
		await process_frame
		game.boat_cargo_panel.amount_dialog.confirmed.emit()
		expect(hold.get_amount(GameTypes.ResourceType.WOOD) == 0 and away.inventory.get_amount(GameTypes.ResourceType.WOOD) == before + 12, "Unload remaining supplies after landing")
		game.boats.transfer(GameTypes.ResourceType.WOOD, 3, true)
		var at_shore: Vector2i = game.world.boats[id].cell
		game.boats.board()
		var sea := GameTypes.NO_CELL
		for cell in HexGrid.neighbors(at_shore):
			if game.world_navigation.can_sail(cell, id) and HexGrid.neighbors(cell).all(func(shore: Vector2i) -> bool: return not game.world_navigation.can_land(cell, shore)):
				sea = cell
				break
		if sea != GameTypes.NO_CELL:
			game.player_unit.mount_boat(id, sea, 0.0)
			game.boats.store_position()
			game.boats.refresh_cargo()
			expect(game.boat_cargo_panel.island == null and game.boat_cargo_panel.maximum_transfer(GameTypes.ResourceType.WOOD, false) == 0, "Stationary open-water boat cannot unload")
		game.save_game()
		root.remove_child(game)
		game.free()
		await process_frame
		game = GameScene.instantiate()
		root.add_child(game)
		await process_frame
		expect(Cargo.inventory(game.world.boats[id]).get_amount(GameTypes.ResourceType.WOOD) == 3, "Actual save/reload retains cargo")
		game.boat_cargo_panel.close()
		game.boats.open_cargo()
		if OS.get_cmdline_user_args().has("--screenshot"):
			root.size = Vector2i(1400, 900)
			game.player_unit.mount_boat(id, at_shore, 0.0)
			game.boats.store_position()
			game.boats.refresh_cargo()
			game.player_unit.set_selected(true)
			game.refresh_action_bar()
			game.camera_rig.center_on(game.player_unit.position, true)
			for frame in 20:
				await process_frame
			root.get_texture().get_image().save_png("res://.godot/boat_cargo_preview.png")
			game.boat_cargo_panel.boat_slots[1]._drop_data(Vector2.ZERO, game.boat_cargo_panel.island_slots[0].drag_data())
			# The occupied slot is the valid merge target after reloading.
			game.boat_cargo_panel.boat_slots[0]._drop_data(Vector2.ZERO, game.boat_cargo_panel.island_slots[0].drag_data())
			for frame in 5:
				await process_frame
			root.get_texture().get_image().save_png("res://.godot/boat_cargo_stack_preview.png")
	root.remove_child(game)
	game.free()
	await process_frame
	SaveManager.delete_save()
	if had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
	print("Boat cargo: PASS" if failures == 0 else "Boat cargo: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _drag_slots(source: Control, destination: Control) -> void:
	var start := source.get_global_rect().get_center()
	var finish := destination.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = start
	Input.parse_input_event(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = start
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	for point in [start + Vector2(20, 0), finish]:
		motion = InputEventMouseMotion.new()
		motion.position = point
		motion.relative = Vector2(20, 0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await process_frame
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = finish
	press.pressed = false
	Input.parse_input_event(press)
	await process_frame

func _check_hold() -> void:
	var state := {}
	var hold := Cargo.inventory(state)
	var stock := Inventory.new({GameTypes.ResourceType.WOOD: 50, GameTypes.ResourceType.STONE: 30, GameTypes.ResourceType.COAL: 10})
	expect(Cargo.transfer(hold, stock, GameTypes.ResourceType.WOOD, 20, true), "Load full stack")
	expect(not Cargo.transfer(hold, stock, GameTypes.ResourceType.WOOD, 1, true), "Reject overflow")
	expect(Cargo.transfer(hold, stock, GameTypes.ResourceType.STONE, 10, true), "Load second resource")
	expect(not Cargo.transfer(hold, stock, GameTypes.ResourceType.COAL, 1, true), "Reject third resource")
	expect(not Cargo.transfer(hold, stock, GameTypes.ResourceType.STONE, -1, true), "Reject negative amount")
	expect(not Cargo.transfer(hold, stock, GameTypes.ResourceType.STONE, 11, false), "Reject unloading unavailable cargo")
	expect(Cargo.transfer(hold, stock, GameTypes.ResourceType.WOOD, 20, false), "Empty a slot")
	expect(Cargo.transfer(hold, stock, GameTypes.ResourceType.COAL, 5, true), "Reuse emptied slot")
	expect(not Cargo.transfer(hold, stock, GameTypes.ResourceType.COAL, 6, true), "Reject loading unavailable stock")
	expect(hold.get_amount(GameTypes.ResourceType.COAL) + stock.get_amount(GameTypes.ResourceType.COAL) == 10, "Rejected transfer conserves goods")
	var world := WorldData.new()
	world.boats[0] = {cell = Vector2i.ZERO, yaw = 0.0, cargo = state.cargo}
	var restored := WorldData.from_dict(world.to_dict(0.0), 0.0)
	expect(Cargo.inventory(restored.boats[0]).get_amount(GameTypes.ResourceType.COAL) == 5, "World serialization preserves cargo")
	expect(Cargo.inventory({cell = Vector2i.ZERO, yaw = 0.0}).amounts.is_empty(), "Legacy boat starts with empty cargo")

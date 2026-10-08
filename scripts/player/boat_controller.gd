class_name BoatController
extends RefCounted

# The robot and boats: launching a dock's skiff and boarding it, sailing (to a cell, or to an
# island's nearest landing), choosing where to land and disembarking, the boat's cargo hold, and the
# boat actions on the command bar. Walking and work are the RobotController's; what comes into sight
# on the way is Game.look_around's.

# Icons for the boat actions on the robot's command bar. Boarding and disembarking share the boat
# (tools/build_boat_icon.py); Disembark is shown active, which crosses it out (ActionBar).
const BOAT_ICON := preload("res://assets/icons/boat.png")
const CARGO_ICON := preload("res://assets/icons/cargo_crate.png")

var game: Game
var world: WorldData
var world_navigation: WorldNavigation
var world_view: WorldView
var player_unit: PlayerUnit
var dog: Dog
var robot: RobotController
var camera_rig: CameraRig
var toast: Toast
var boat_cargo_panel: BoatCargoPanel

# The island the robot is on, and its renderer: the game's current ones.
var current_island: IslandData:
	get:
		return game.current_island
var renderer: IslandRenderer:
	get:
		return game.renderer

# Where the robot lands when it disembarks, if the player picked a shore (right-click); otherwise
# the first one beside the boat (landing_tile).
var landing_cell := GameTypes.NO_CELL
# The boat whose hold the cargo panel shows.
var cargo_boat_id := -1


# Built once the game has its world, units, robot and UI (Game._ready).
func setup(new_game: Game) -> void:
	game = new_game
	world = game.world
	world_navigation = game.world_navigation
	world_view = game.world_view
	player_unit = game.player_unit
	dog = game.dog
	robot = game.robot
	camera_rig = game.camera_rig
	toast = game.toast
	boat_cargo_panel = game.boat_cargo_panel
	boat_cargo_panel.transfer_requested.connect(transfer)


# Each cell the boat sails into is kept with it (Game.look_around brings islands into sight).
func on_entered_cell(_cell: Vector2i) -> void:
	store_position()
	game.mark_dirty()


# The boat got where it was sailing.
func on_arrived() -> void:
	store_position()
	robot.pending_action_cell = GameTypes.NO_CELL
	game.refresh_action_bar()
	game.save_game()


# Steering the boat, the hover is a marker on the hovered cell: green where the robot can land,
# cyan where the boat can sail, red where it can't go.
func show_hover(cell: Vector2i) -> void:
	var can_land := world_navigation.can_land(player_unit.current_cell, cell)
	var color := Color(0.3, 0.85, 0.95, 0.4) if world_navigation.can_sail(cell, player_unit.boat_id) else Color(1.0, 0.3, 0.25, 0.4)
	world_view.show_sailing_hover(world_view.get_cell_center(cell), Color(0.3, 1.0, 0.55, 0.4) if can_land else color)


# Boat actions for the command bar (Game.refresh_action_bar): aboard, the cargo hold and, beside a
# shore, disembarking; on foot beside a boat, its cargo hold and boarding it. The same order either
# way, so the Cargo button stays put when the robot boards or leaves the boat.
func actions() -> Array:
	var aboard := player_unit.boat_id != -1
	if not aboard and nearby_boat().is_empty():
		return []
	var actions: Array = []
	if has_cargo_hold():
		var label := "Boat cargo — load or unload at the shore" if aboard else "Boat cargo — load or unload supplies"
		actions.append({id = GameTypes.UnitAction.CARGO, icon = CARGO_ICON, caption = "Cargo", label = label, active = false})
	if not aboard:
		actions.append({id = GameTypes.UnitAction.PILOT_BOAT, icon = BOAT_ICON, label = "Pilot boat — board and power the helm (or right-click the boat)", active = false})
	elif landing_tile() != GameTypes.NO_CELL:
		# Piloting is the robot's running task, so leaving the boat reads as cancelling it.
		actions.append({id = GameTypes.UnitAction.DISEMBARK, icon = BOAT_ICON, label = "Disembark (right-click shore to choose landing)", active = true})
	return actions


# The cargo hold opens once the robot finds something worth carrying (the Copper Glint quest).
func has_cargo_hold() -> bool:
	return game.quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.CARGO_HOLD)


# A boat action pressed on the command bar.
func press(action_id: int) -> void:
	match action_id:
		GameTypes.UnitAction.CARGO:
			open_cargo()
		GameTypes.UnitAction.PILOT_BOAT:
			board()
		GameTypes.UnitAction.DISEMBARK:
			disembark()


# Sailing commands always use the world lattice, including clicks between islands.
func command_to(cell: Vector2i) -> bool:
	if player_unit.boat_id == -1:
		return false
	if world_navigation.can_land(player_unit.current_cell, cell) and not player_unit.is_moving():
		landing_cell = cell
		game.refresh_action_bar()
		return true
	if not world_navigation.inside_frontier(cell):
		toast.show_message("The fog blocks passage — " + world_view.locked_frontier_hint())
		return false
	var plan: Dictionary = robot.plan_route(cell, player_unit.next_cell())
	if plan.is_empty():
		return false
	landing_cell = GameTypes.NO_CELL
	robot.pending_action_cell = cell
	if player_unit.is_moving():
		player_unit.reroute(plan.path)
	else:
		player_unit.follow_path(plan.path)
	game.refresh_action_bar()
	return true


func sail_to_island(coord: Vector2i) -> bool:
	if player_unit.boat_id == -1 or not world.has_island(coord) or not world.is_revealed(coord):
		return false
	player_unit.set_selected(true)
	var island: IslandData = world.islands[coord]
	var candidates: Array = []
	for cell: Vector2i in island.terrain:
		if not world_navigation.can_sail(cell, player_unit.boat_id):
			continue
		for shore in HexGrid.neighbors(cell):
			if world_navigation.can_land(cell, shore):
				candidates.append({cell = cell, shore = shore, distance = HexGrid.distance(player_unit.next_cell(), cell)})
				break
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	for candidate in candidates:
		if command_to(candidate.cell):
			landing_cell = candidate.shore
			return true
	toast.show_message("No reachable landing on this island.")
	return false


func landing_tile() -> Vector2i:
	if world_navigation.can_land(player_unit.current_cell, landing_cell):
		return landing_cell
	for shore in HexGrid.neighbors(player_unit.current_cell):
		if world_navigation.can_land(player_unit.current_cell, shore):
			return shore
	return GameTypes.NO_CELL


func disembark() -> void:
	if player_unit.boat_id == -1 or player_unit.is_moving():
		return
	var shore := landing_tile()
	if shore == GameTypes.NO_CELL:
		return
	store_position()
	var destination := world_navigation.island_at(shore)
	world.piloted_boat = -1
	player_unit.leave_boat()
	world_view.hide_sailing_hover()
	if destination != world.current_coord:
		game.switch_to_island(destination)
	player_unit.place_at(shore)
	camera_rig.center_on(player_unit.position)
	robot.sync_dog()
	landing_cell = GameTypes.NO_CELL
	renderer.refresh()
	game.refresh_action_bar()
	game.save_game()


# A boat the robot, ashore and standing still, can board from where it stands: the one at `at`,
# or any beside it.
func nearby_boat(at := GameTypes.NO_CELL) -> Dictionary:
	if player_unit.boat_id != -1 or player_unit.is_moving():
		return {}
	for cell in HexGrid.neighbors(player_unit.current_cell):
		if at != GameTypes.NO_CELL and cell != at:
			continue
		var boat := world_navigation.boat_at(cell)
		if not boat.is_empty() and world_navigation.can_land(cell, player_unit.current_cell):
			return boat
	return {}


func _launch(boat: Dictionary) -> int:
	var id: int = boat.id
	if id == -1:
		id = world.next_boat_id()
		var building: Dictionary = current_island.buildings[boat.anchor]
		var direction := renderer.get_water_center(boat.cell) - renderer.get_cell_center(building.cells[1])
		world.boats[id] = {cell = boat.cell, yaw = atan2(-direction.z, direction.x)}
		building.boat_launched = true
	return id


# Board the boat at `at` (or any beside the robot) and take the helm. False if there's none to board.
func board(at := GameTypes.NO_CELL) -> bool:
	var boat := nearby_boat(at)
	if boat.is_empty():
		return false
	robot.stop_work()
	var id := _launch(boat)
	world.piloted_boat = id
	var state: Dictionary = world.boats[id]
	player_unit.mount_boat(id, state.cell, float(state.yaw))
	# Keep the companion safely ashore until a boat-sized companion pose is authored.
	if world.dog_rescued:
		dog.halt()
	robot.clear_targets()
	landing_cell = GameTypes.NO_CELL
	renderer.clear_interaction()
	renderer.refresh()
	game.refresh_action_bar()
	game.save_game()
	return true


func store_position() -> void:
	if player_unit != null and world != null and world.boats.has(player_unit.boat_id):
		world.boats[player_unit.boat_id].cell = player_unit.current_cell
		world.boats[player_unit.boat_id].yaw = player_unit.boat_yaw()


func open_cargo() -> void:
	if boat_cargo_panel.is_open():
		boat_cargo_panel.close()
		return
	if not has_cargo_hold():
		return
	cargo_boat_id = player_unit.boat_id
	if cargo_boat_id == -1:
		var boat := nearby_boat()
		if boat.is_empty():
			return
		cargo_boat_id = _launch(boat)
		renderer.refresh()
		game.save_game()
	boat_cargo_panel.show_cargo(BoatCargo.inventory(world.boats[cargo_boat_id]), _cargo_island(cargo_boat_id))


# Resolve the shore beside the actual boat, not the last island the robot landed on.
func _cargo_island(id: int) -> IslandData:
	if player_unit.is_moving() or not world.boats.has(id):
		return null
	if player_unit.boat_id == id:
		var shore := landing_tile()
		if shore != GameTypes.NO_CELL:
			return world.get_island(world_navigation.island_at(shore))
	elif player_unit.boat_id == -1:
		var boat := nearby_boat()
		if not boat.is_empty() and boat.id == id:
			return current_island
	return null


func refresh_cargo() -> void:
	if boat_cargo_panel == null or not boat_cargo_panel.is_open():
		return
	if world == null or not world.boats.has(cargo_boat_id):
		boat_cargo_panel.close()
		return
	boat_cargo_panel.update_context(BoatCargo.inventory(world.boats[cargo_boat_id]), _cargo_island(cargo_boat_id))


func transfer(resource: int, amount: int, loading: bool) -> void:
	# Recheck the live location and stock: the boat may have moved since the panel opened.
	var island := _cargo_island(cargo_boat_id)
	if island == null:
		return
	var hold := BoatCargo.inventory(world.boats[cargo_boat_id])
	var before := island.inventory.get_amount(resource)
	if BoatCargo.transfer(hold, island.inventory, resource, amount, loading):
		# Copper brought home to the crash site, for the furnace and the ship (Haul It Home).
		var unloaded := island.inventory.get_amount(resource) - before
		if resource == GameTypes.ResourceType.COPPER_ORE and unloaded > 0 and island == world.get_island(world.start_coord):
			game.stat_tracker.add(GameTypes.Stat.COPPER_ORE_SHIPPED_HOME, unloaded)
		refresh_cargo()
		game.save_game()


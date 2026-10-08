class_name RobotController
extends RefCounted

# The player's robot at work: walking where it's sent and to what it can work there (planning the
# approach), harvesting, operating (hand-powering a building), building blueprints, repairing the
# crashed ship, rescuing K9-DA and keeping the dog at its side, and the work actions on the command
# bar. Sailing is the BoatController's; the Game says which island the robot is on (current_island,
# renderer).

# Seconds per harvest cycle, and what one cycle yields.
const HARVEST_INTERVAL := 3.0
const HARVEST_YIELD := 1
# Working a building or resource node from the tile beside it, the robot leans this far (in
# tiles) toward it — close enough to read as working it, clear of its geometry.
const WORK_LEAN_TILES := 0.15
# Extra steps the robot will walk to work a target from the camera side rather than from behind
# it, where the target would hide it.
const BEHIND_PENALTY := 2

# Icons for the robot's command-bar actions.
const PICKAXE_ICON := preload("res://assets/icons/pickaxe.png")
const POWER_ICON := preload("res://assets/icons/power.png")
const PAW_ICON := preload("res://assets/icons/paw.png")
const HAMMER_ICON := preload("res://assets/icons/hammer.png")

var game: Game
var world: WorldData
var world_navigation: WorldNavigation
var world_view: WorldView
var player_unit: PlayerUnit
var dog: Dog
var building_manager: BuildingManager
var resource_manager: ResourceManager
var resource_node_database: ResourceNodeDatabase
var stat_tracker: StatTracker
var quest_manager: QuestManager

# The island the robot is on, and its renderer: the game's current ones.
var current_island: IslandData:
	get:
		return game.current_island
var renderer: IslandRenderer:
	get:
		return game.renderer

# Where the robot was sent: the target it works on arrival (on foot), or where its boat sails.
var pending_action_cell := GameTypes.NO_CELL
# What the robot can work from where it stands, as found on arrival: offered on the command bar.
var harvestable_cell := GameTypes.NO_CELL
var operable_cell := GameTypes.NO_CELL
var buildable_cell := GameTypes.NO_CELL

var is_harvesting := false
var harvest_cell := GameTypes.NO_CELL
var harvest_resource_type := -1
var _harvest_accum := 0.0

# The robot is the tier-0 power source: while is_operating, it hand-powers the
# power-consuming building anchored at operate_cell (power_manager treats that cell as
# powered for free, see operated_cell).
var is_operating := false
var operate_cell := GameTypes.NO_CELL

# Construction: placing a building puts down a blueprint (IslandData.is_under_construction) and
# sends the robot to raise it. While is_constructing it works the blueprint anchored at
# construct_cell, adding to its build progress.
var is_constructing := false
var construct_cell := GameTypes.NO_CELL

# Repairing the crashed ship: parked beside the wreck (repairable_cell), the robot works on the
# next part (WorldData.next_ship_part) while is_repairing, adding to its progress in
# WorldData.ship_repairs. The part's materials are paid when its repair starts. See ShipRepairs.
var repairable_cell := GameTypes.NO_CELL
var is_repairing := false


# Built once the game has its world and units (Game._ready).
func setup(new_game: Game) -> void:
	game = new_game
	world = game.world
	world_navigation = game.world_navigation
	world_view = game.world_view
	player_unit = game.player_unit
	dog = game.dog
	building_manager = game.building_manager
	resource_manager = game.resource_manager
	resource_node_database = game.resource_node_database
	stat_tracker = game.stat_tracker
	quest_manager = game.quest_manager


# Per frame: the harvest or construction under way makes progress.
func update(delta: float) -> void:
	if is_harvesting:
		_update_harvest(delta)

	if is_constructing:
		_update_construction(delta)

	if is_repairing:
		_update_repair(delta)


# Walk to `cell`. Open ground is walked onto. The robot doesn't park on a building or resource
# node, so for one it walks to where it can work it instead (see plan_approach) and the target
# stays the cell; arriving, it starts the work. False when it can't get there (or is aboard).
# A moving robot finishes the step it's on and re-plans from there, so its model never cuts across
# tiles or parks away from its cell.
func command_to(cell: Vector2i) -> bool:
	if player_unit == null or current_island == null or player_unit.boat_id != -1:
		return false

	# A building's tiles are all targets, even one standing in the water (the dock's pier).
	if cell == GameTypes.NO_CELL or not (HexPathfinder.is_walkable(current_island, cell) or current_island.has_building(cell) or not world_navigation.boat_at(cell).is_empty()):
		return false

	var plan := plan_approach(cell, player_unit.next_cell())
	if plan.is_empty():
		return false

	pending_action_cell = cell

	if not player_unit.is_moving() and plan.path.is_empty() and plan.spot_cell == GameTypes.NO_CELL:
		# Already where it can work the target: switch to it without moving.
		if cell != harvest_cell:
			_stop_harvesting()
		if current_island.get_building_anchor_cell(cell) != operate_cell:
			stop_operating()
		if current_island.get_building_anchor_cell(cell) != construct_cell:
			stop_constructing()
		if not _is_wreck(cell):
			stop_repairing()
		on_arrived()
		return true

	stop_work()
	harvestable_cell = GameTypes.NO_CELL
	operable_cell = GameTypes.NO_CELL
	buildable_cell = GameTypes.NO_CELL
	repairable_cell = GameTypes.NO_CELL
	if player_unit.is_moving():
		# An empty route ends the walk at the cell it's stepping into, where on_arrived starts the work.
		player_unit.reroute(plan.path, plan.spot_cell, plan.spot_position)
	else:
		player_unit.follow_path(plan.path, plan.spot_cell, plan.spot_position)
	game.refresh_action_bar()
	return true


# Collect any ground item the robot walks onto. Fires for every cell stepped through,
# so tools are picked up by passing over them — the intro to movement.
func on_entered_cell(cell: Vector2i) -> void:
	if current_island == null or not current_island.has_item(cell):
		return

	var item_type := current_island.take_item(cell)
	stat_tracker.add(GameTypes.Stat.TOOLS_COLLECTED, 1)
	FloatingText.spawn(
		game,
		renderer.get_cell_center(cell),
		"+%s" % GameTypes.item_display_name(item_type),
		Color(1.0, 0.95, 0.7)
	)
	renderer.refresh()


# Walking, the robot got where it was sent: if it was sent to a boat, it boards it; if it can work
# the target from here, it finds what it can do there and starts it.
func on_arrived() -> void:
	var target := pending_action_cell
	if target == GameTypes.NO_CELL:
		return

	pending_action_cell = GameTypes.NO_CELL
	# Sent to a boat: beside it now, the robot boards it and takes the helm.
	if not world_navigation.boat_at(target).is_empty() and game.boats.board(target):
		return
	if _is_working_position(target):
		harvestable_cell = target if current_island.get_resource_node_type(target) != -1 else GameTypes.NO_CELL
		operable_cell = target if _building_consumes_power(target) else GameTypes.NO_CELL
		buildable_cell = target if current_island.is_under_construction(target) else GameTypes.NO_CELL
		repairable_cell = target if _is_wreck(target) else GameTypes.NO_CELL
		if player_unit.is_at_spot():
			player_unit.face_toward(renderer.get_cell_center(target))
		elif target != player_unit.current_cell:
			player_unit.face_toward(renderer.get_cell_center(target), WORK_LEAN_TILES)
		_start_action_at(target)
	game.refresh_action_bar()


# True for a cell the selected robot would start working on if right-clicked: a boat to board, a
# blueprint, a resource node once harvesting is unlocked, a building that draws power once
# operating is unlocked, the wreck while a part is left to repair once repairing is unlocked, or the
# stranded K9-DA; aboard, a shore it can land on. The hover tints it green
# (IslandRenderer.is_cell_actionable, see Game._is_actionable_cell).
func is_actionable_cell(cell: Vector2i) -> bool:
	if player_unit == null or not player_unit.selected or current_island == null:
		return false
	if player_unit.boat_id != -1:
		return world_navigation.can_land(player_unit.current_cell, cell)
	if not world_navigation.boat_at(cell).is_empty():
		return true
	if current_island.is_under_construction(cell):
		return true
	if current_island.get_resource_node_type(cell) != -1:
		return quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.HARVESTING)
	if _building_consumes_power(cell):
		return _can_operate()
	if _is_wreck(cell):
		return _can_repair()
	return world.is_dog_stranded_on(world.current_coord) and cell == world.dog_cell


# The work the robot can do where it stands, as command-bar descriptors (Game.refresh_action_bar).
func actions() -> Array:
	var actions: Array = []
	for action in [_build_action(), _harvest_action(), _operate_action(), _repair_action(), _rescue_action()]:
		if not action.is_empty():
			actions.append(action)
	return actions


# A work action pressed on the command bar.
func press(action_id: int) -> void:
	match action_id:
		GameTypes.UnitAction.HARVEST:
			_on_harvest_pressed()
		GameTypes.UnitAction.OPERATE:
			_on_operate_pressed()
		GameTypes.UnitAction.RESCUE:
			_on_rescue_pressed()
		GameTypes.UnitAction.BUILD:
			_on_build_pressed()
		GameTypes.UnitAction.REPAIR:
			_on_repair_pressed()


# Stop whatever the robot is working at.
func stop_work() -> void:
	_stop_harvesting()
	stop_operating()
	stop_constructing()
	stop_repairing()


# Forget where the robot was sent and what it could work where it stood.
func clear_targets() -> void:
	pending_action_cell = GameTypes.NO_CELL
	harvestable_cell = GameTypes.NO_CELL
	operable_cell = GameTypes.NO_CELL
	buildable_cell = GameTypes.NO_CELL
	repairable_cell = GameTypes.NO_CELL


# The building the robot hand-powers (PowerManager gives it power for free), or NO_CELL.
func operated_cell() -> Vector2i:
	return operate_cell if is_operating else GameTypes.NO_CELL


# How the robot gets from `start` to `target`: sailing, the boat's route there; on foot, the walk
# to where it can work the target (plan_approach). {} when it can't get there.
func plan_route(target: Vector2i, start: Vector2i) -> Dictionary:
	if player_unit.boat_id == -1:
		return plan_approach(target, start)
	var path := world_navigation.find_path(start, target, player_unit.boat_id)
	return _approach(path) if not path.is_empty() else {}


# How the robot, standing at `start`, gets to work `target`: {path, spot_cell, spot_position} for
# PlayerUnit.follow_path, or {} when it can't get there. Empty path and no spot = already there.
#   - Open ground, or a deck like the dock's pier: walk onto it.
#   - A building with a WorkSpot: the shortest route straight onto the building's tile (walking
#     through buildings is fine), the last step going onto the parking spot instead of the
#     tile's centre. The robot then turns to face the building (see on_arrived).
#   - Anything else (a resource node, or a building whose model fills its tile): the cheapest
#     open neighbour, interacting across the edge, but not across a cliff (see
#     HexPathfinder.MAX_CLIMB). Neighbours behind the target (away from the camera) cost
#     BEHIND_PENALTY extra, so the robot isn't hidden by it.
#   - No open neighbour at all (fully enclosed): stand on the target itself, as a last resort.
func plan_approach(target: Vector2i, start: Vector2i) -> Dictionary:
	var island := current_island
	var no_path: Array[Vector2i] = []
	if not world_navigation.boat_at(target).is_empty():
		var search := HexPathfinder.search(island, start)
		var best := GameTypes.NO_CELL
		var cost := INF
		for shore in HexGrid.neighbors(target):
			if world_navigation.can_land(target, shore) and search.cost.has(shore) and search.cost[shore] < cost:
				best = shore
				cost = search.cost[shore]
		return _approach(HexPathfinder.path_to(search, best)) if best != GameTypes.NO_CELL else {}

	# Checked before the work spot: a deck is a building's tile, but one to walk out onto.
	if HexPathfinder.is_open(island, target):
		var path := HexPathfinder.find_path(island, start, target)
		if path.is_empty() and target != start:
			return {}
		return _approach(path)

	var spot = renderer.get_work_spot(island.get_building_anchor_cell(target)) if island.has_building(target) else null
	# A building bigger than one tile is reached at the tile its spot stands on, not the one clicked.
	var spot_tile: Vector2i = renderer.world_to_cell(spot) if spot != null else target
	if spot != null and not HexPathfinder.is_walkable(island, spot_tile):
		spot = null
	if spot != null:
		if start == spot_tile and player_unit.is_at_spot():
			return _approach(no_path)
		var to_tile := HexPathfinder.find_path(island, start, spot_tile)
		if to_tile.is_empty() and start != spot_tile:
			return {}
		if not to_tile.is_empty():
			to_tile.pop_back()  # the spot leg replaces the step to the tile's centre
		return _approach(to_tile, spot_tile, Vector3(spot.x, renderer.get_cell_center(spot_tile).y, spot.z))

	var search := HexPathfinder.search(island, start)
	var costs: Dictionary = search.cost
	var center := renderer.get_cell_center(target)

	var best := GameTypes.NO_CELL
	var best_score := INF
	for neighbor in HexGrid.neighbors(target):
		if not HexPathfinder.is_open(island, neighbor) or not costs.has(neighbor) \
				or not HexPathfinder.within_climb(island, neighbor, target):
			continue
		var neighbor_z := renderer.get_cell_center(neighbor).z
		var score: float = costs[neighbor] + (BEHIND_PENALTY if neighbor_z < center.z else 0)
		# Equal scores: the tile nearer the camera.
		score -= neighbor_z * 0.0001
		if score < best_score:
			best = neighbor
			best_score = score

	if best != GameTypes.NO_CELL:
		return _approach(HexPathfinder.path_to(search, best))

	return _approach(HexPathfinder.path_to(search, target))


func _approach(path: Array[Vector2i], spot_cell := GameTypes.NO_CELL, spot_position := Vector3.ZERO) -> Dictionary:
	return {path = path, spot_cell = spot_cell, spot_position = spot_position}


# True when the robot can work `target` from where it stands: on it (open ground, a work spot,
# or the enclosed-target fallback) or on a neighbouring tile, not across a cliff.
func _is_working_position(target: Vector2i) -> bool:
	if player_unit == null or target == GameTypes.NO_CELL:
		return false
	if player_unit.boat_id != -1:
		return false
	var cell := player_unit.current_cell
	# On or beside any tile of the target building, however many tiles it covers.
	var target_cells: Array[Vector2i] = [target]
	if current_island.has_building(target):
		target_cells = current_island.get_building_footprint_cells(current_island.get_building_anchor_cell(target))
	for target_cell in target_cells:
		if cell == target_cell or (HexGrid.neighbors(target_cell).has(cell) and HexPathfinder.within_climb(current_island, cell, target_cell)):
			return true
	return false


# Placement veto (IslandRenderer.is_cell_occupied_by_unit): the robot's and K9-DA's cells,
# including the ones they're stepping into.
func is_unit_cell(cell: Vector2i) -> bool:
	for id in world.boats:
		if world.boats[id].cell == cell:
			return true
	if player_unit != null and cell in [player_unit.current_cell, player_unit.next_cell()]:
		return true
	if dog != null and dog.is_on(current_island):
		return cell == dog.current_cell or cell == dog.next_cell()
	return false


# Construction changed the map: re-plan a moving robot's route from the cell it's stepping into,
# so it never ends up parked on a building placed where it was heading (walking through one on the
# way is fine), nor sails into a pier. The last leg into a work spot stays inside the building's
# own tile. A boat left with no route carries on until its old one is blocked, and stops there
# (PlayerUnit checks each step).
func reroute() -> void:
	if player_unit == null or not player_unit.is_moving() or pending_action_cell == GameTypes.NO_CELL:
		return
	if player_unit.is_at_spot():
		return

	var plan := plan_route(pending_action_cell, player_unit.next_cell())
	if not plan.is_empty():
		player_unit.reroute(plan.path, plan.spot_cell, plan.spot_position)


# A building with a deck (the dock's pier) just left the map: a unit standing on the deck, or
# stepping onto it, would be left over the water, so put it back ashore on the building's anchor
# tile (the quay's sand). A robot still on its way out there re-plans.
func land_stranded_units(anchor_cell: Vector2i) -> void:
	if player_unit != null and player_unit.boat_id == -1 and not HexPathfinder.is_walkable(current_island, player_unit.next_cell()):
		pending_action_cell = GameTypes.NO_CELL
		player_unit.place_at(anchor_cell)
	reroute()
	if dog != null and dog.is_on(current_island) \
			and not HexPathfinder.is_walkable(current_island, dog.next_cell()):
		dog.follow(current_island, anchor_cell, player_unit)


# The robot was sent to `target` and can work it from here: start the work right away (what the
# green hover promised, see is_actionable_cell). Work already under way there is left running.
func _start_action_at(target: Vector2i) -> void:
	var can_harvest := quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.HARVESTING)
	if buildable_cell == target and not is_constructing:
		_on_build_pressed()
	elif harvestable_cell == target and not is_harvesting and can_harvest:
		_on_harvest_pressed()
	elif operable_cell == target and not is_operating and _can_operate():
		_on_operate_pressed()
	elif repairable_cell == target and not is_repairing and _can_repair():
		_on_repair_pressed()
	elif _can_rescue_dog() and target == world.dog_cell:
		_on_rescue_pressed()


func _harvest_action() -> Dictionary:
	# Harvesting is locked until the robot recovers its tools (the "Hello World" quest).
	if not quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.HARVESTING):
		return {}

	if harvestable_cell == GameTypes.NO_CELL or not _is_working_position(harvestable_cell):
		return {}

	var resource_node_type := current_island.get_resource_node_type(harvestable_cell)
	if resource_node_type == -1:
		return {}

	var definition := resource_node_database.get_definition(resource_node_type)
	var node_name := definition.display_name if definition != null else ""
	var label := ""
	if is_harvesting:
		label = "Cancel harvesting" if node_name.is_empty() else "Cancel (%s)" % node_name
	else:
		label = "Harvest" if node_name.is_empty() else "Harvest %s" % node_name

	return {id = GameTypes.UnitAction.HARVEST, icon = PICKAXE_ICON, label = label, active = is_harvesting}


func _operate_action() -> Dictionary:
	# Hand-powering is locked until the first extractors stand (the "Lay the Foundations" quest).
	if not _can_operate():
		return {}

	if operable_cell == GameTypes.NO_CELL or not _is_working_position(operable_cell):
		return {}

	if not _building_consumes_power(operable_cell):
		return {}

	var definition := building_manager.get_definition(current_island.get_building_type(operable_cell))
	var building_name := definition.display_name if definition != null else ""
	var label := ""
	if is_operating:
		label = "Cancel operating" if building_name.is_empty() else "Cancel (%s)" % building_name
	else:
		label = "Operate" if building_name.is_empty() else "Operate %s" % building_name

	return {id = GameTypes.UnitAction.OPERATE, icon = POWER_ICON, label = label, active = is_operating}


# Offered while the robot is parked at a blueprint: start (or resume) raising it, or pause.
func _build_action() -> Dictionary:
	if buildable_cell == GameTypes.NO_CELL or not _is_working_position(buildable_cell):
		return {}
	if not current_island.is_under_construction(buildable_cell):
		return {}

	var anchor_cell := current_island.get_building_anchor_cell(buildable_cell)
	var building_name := building_manager.get_display_name(current_island.get_building_type(anchor_cell))
	var percent := int(current_island.get_build_progress(anchor_cell) * 100.0)
	var label := ""
	if is_constructing:
		label = "Pause building"
	elif percent > 0:
		label = "Resume %s (%d%%)" % [building_name, percent]
	else:
		label = "Build %s" % building_name

	return {id = GameTypes.UnitAction.BUILD, icon = HAMMER_ICON, label = label, active = is_constructing}


# Offered while the robot is parked beside the wreck with a ship part left to repair: start the
# next part (paying for it), resume it, or pause.
func _repair_action() -> Dictionary:
	if not _can_repair() or repairable_cell == GameTypes.NO_CELL or not _is_working_position(repairable_cell):
		return {}

	var part := world.next_ship_part()
	var part_name := ShipRepairs.display_name(part)
	var label := ""
	if is_repairing:
		label = "Pause repair"
	elif world.ship_repairs.has(part):
		label = "Resume %s repair (%d%%)" % [part_name, int(float(world.ship_repairs[part]) * 100.0)]
	else:
		label = "Repair %s (%s)" % [part_name, building_manager.format_cost(ShipRepairs.cost(part))]

	return {id = GameTypes.UnitAction.REPAIR, icon = HAMMER_ICON, label = label, active = is_repairing}


# Offered while the robot is parked on or right beside the stranded K9-DA.
func _rescue_action() -> Dictionary:
	if not _can_rescue_dog():
		return {}

	return {id = GameTypes.UnitAction.RESCUE, icon = PAW_ICON, label = "Rescue K9-DA", active = false}


func _can_rescue_dog() -> bool:
	if not world.is_dog_stranded_on(world.current_coord):
		return false

	var robot_cell := player_unit.current_cell
	return robot_cell == world.dog_cell or (HexGrid.neighbors(world.dog_cell).has(robot_cell)
		and HexPathfinder.within_climb(current_island, robot_cell, world.dog_cell))


# True when the cell holds a building that draws power, so the robot can hand-power it
# with the Operate verb (the tier-0 power source — see is_operating / power_manager.gd).
func _building_consumes_power(cell: Vector2i) -> bool:
	var building_type := current_island.get_building_type(cell)
	if building_type == -1 or current_island.is_under_construction(cell):
		return false

	var definition := building_manager.get_definition(building_type)
	return definition != null and definition.power_consumed > 0


func _can_operate() -> bool:
	return quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.OPERATING)


# Repairing is unlocked by the first copper smelting (First Melt), while a ship part is left.
func _can_repair() -> bool:
	return quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.REPAIRING) and world.next_ship_part() != -1


func _is_wreck(cell: Vector2i) -> bool:
	return current_island.get_building_type(cell) == GameTypes.BuildingType.CRASHED_SPACESHIP


func _on_harvest_pressed() -> void:
	if is_harvesting:
		_stop_harvesting()
		game.refresh_action_bar()
		return

	if harvestable_cell == GameTypes.NO_CELL:
		return

	var resource_node_type := current_island.get_resource_node_type(harvestable_cell)
	if resource_node_type == -1:
		return

	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return

	is_harvesting = true
	harvest_cell = harvestable_cell
	harvest_resource_type = definition.extracted_resource_type
	_harvest_accum = 0.0
	# Trees are chopped with the axe; stone, ore and coal are mined with the pickaxe.
	player_unit.set_work("chop" if harvest_resource_type == GameTypes.ResourceType.WOOD else "mine")
	game.refresh_action_bar()


func _stop_harvesting() -> void:
	if not is_harvesting:
		return

	is_harvesting = false
	harvest_cell = GameTypes.NO_CELL
	harvest_resource_type = -1
	_harvest_accum = 0.0
	if player_unit != null:
		player_unit.set_work("")


func _update_harvest(delta: float) -> void:
	# Stop if the robot is no longer parked where it can work the node it was harvesting.
	if (
		player_unit == null
		or player_unit.is_moving()
		or not _is_working_position(harvest_cell)
		or current_island == null
		or current_island.get_resource_node_type(harvest_cell) == -1
	):
		_stop_harvesting()
		game.refresh_action_bar()
		return

	_harvest_accum += delta
	while _harvest_accum >= HARVEST_INTERVAL:
		_harvest_accum -= HARVEST_INTERVAL
		resource_manager.add_amount(harvest_resource_type, HARVEST_YIELD)
		stat_tracker.record_resource_gained(harvest_resource_type, HARVEST_YIELD)
		FloatingText.spawn_resource(
			game,
			renderer.get_cell_center(harvest_cell),
			harvest_resource_type,
			"+%d" % HARVEST_YIELD
		)


func _on_operate_pressed() -> void:
	if is_operating:
		stop_operating()
		game.refresh_action_bar()
		return

	if operable_cell == GameTypes.NO_CELL:
		return

	if not _can_operate() or not _building_consumes_power(operable_cell):
		return

	is_operating = true
	operate_cell = current_island.get_building_anchor_cell(operable_cell)
	# The hand PTO docks into the building's generator socket.
	player_unit.set_work("operate")
	stat_tracker.add(GameTypes.Stat.BUILDINGS_OPERATED, 1)
	game.refresh_action_bar()


# Hand the building back: it loses the robot's power the moment the robot stops
# operating it (or is sent elsewhere / the island is left). power_manager re-allocates
# from the island's generators on the next tick.
func stop_operating() -> void:
	if not is_operating:
		return

	is_operating = false
	operate_cell = GameTypes.NO_CELL
	if player_unit != null:
		player_unit.set_work("")


func _on_build_pressed() -> void:
	if is_constructing:
		stop_constructing()
		game.refresh_action_bar()
		return

	if buildable_cell == GameTypes.NO_CELL or not current_island.is_under_construction(buildable_cell):
		return

	is_constructing = true
	construct_cell = current_island.get_building_anchor_cell(buildable_cell)
	player_unit.set_work("build")
	game.refresh_action_bar()


# Leave the blueprint as it stands; its progress stays on the map (and in the save) to resume.
func stop_constructing() -> void:
	if not is_constructing:
		return

	is_constructing = false
	construct_cell = GameTypes.NO_CELL
	if player_unit != null:
		player_unit.set_work("")


func _update_construction(delta: float) -> void:
	# Stop if the robot walked off or the blueprint is gone (cancelled from its panel).
	if (
		player_unit == null
		or player_unit.is_moving()
		or current_island == null
		or not current_island.is_under_construction(construct_cell)
		or not _is_working_position(construct_cell)
	):
		stop_constructing()
		game.refresh_action_bar()
		return

	var definition := building_manager.get_definition(current_island.get_building_type(construct_cell))
	var build_seconds := definition.build_seconds if definition != null else 6.0
	var progress := current_island.get_build_progress(construct_cell) + delta / maxf(build_seconds, 0.1)
	if progress < 1.0:
		current_island.set_build_progress(construct_cell, progress)
		game.mark_dirty()
		return

	_finish_construction(construct_cell)


# The robot finished a blueprint: the building starts working, counts as built for quests, and
# the robot moves on to the next blueprint on the island, if any.
func _finish_construction(anchor_cell: Vector2i) -> void:
	var building_type := current_island.get_building_type(anchor_cell)
	current_island.complete_construction(anchor_cell)
	stop_constructing()
	buildable_cell = GameTypes.NO_CELL
	renderer.refresh()
	# Standing at a machine that needs power, the robot can Operate it straight away.
	if _building_consumes_power(anchor_cell) and _is_working_position(anchor_cell):
		operable_cell = anchor_cell
	game.play_placement_sound()
	FloatingText.spawn(
		game,
		renderer.get_cell_center(anchor_cell),
		"%s built!" % building_manager.get_display_name(building_type),
		Color(0.55, 1.0, 0.85)
	)
	stat_tracker.record_building_built(building_type)
	if not _build_next_blueprint():
		game.refresh_action_bar()
	game.save_game()


func _on_repair_pressed() -> void:
	if is_repairing:
		stop_repairing()
		game.refresh_action_bar()
		return

	if repairable_cell == GameTypes.NO_CELL or not _can_repair():
		return

	# The materials go in when the part's repair starts; a paused repair resumes for free.
	var part := world.next_ship_part()
	if not world.ship_repairs.has(part):
		var cost := ShipRepairs.cost(part)
		if not resource_manager.can_afford(cost):
			game.toast.show_message("Repairing the %s takes %s from this island's stock." % [
				ShipRepairs.display_name(part), building_manager.format_cost(cost)])
			return
		resource_manager.spend(cost)
		world.ship_repairs[part] = 0.0

	is_repairing = true
	player_unit.set_work("build")
	game.refresh_action_bar()
	game.save_game()


# Leave the part as it stands; its progress stays in WorldData.ship_repairs (and the save) to resume.
func stop_repairing() -> void:
	if not is_repairing:
		return

	is_repairing = false
	if player_unit != null:
		player_unit.set_work("")


func _update_repair(delta: float) -> void:
	var part := world.next_ship_part()
	# Stop if the robot walked off, or the part isn't under repair.
	if (
		player_unit == null
		or player_unit.is_moving()
		or current_island == null
		or part == -1
		or not world.ship_repairs.has(part)
		or not _is_working_position(repairable_cell)
	):
		stop_repairing()
		game.refresh_action_bar()
		return

	var progress := float(world.ship_repairs[part]) + delta / maxf(ShipRepairs.work_seconds(part), 0.1)
	if progress < 1.0:
		world.ship_repairs[part] = progress
		game.mark_dirty()
		return

	world.ship_repairs[part] = 1.0
	stop_repairing()
	game.play_placement_sound()
	FloatingText.spawn(
		game,
		renderer.get_cell_center(repairable_cell),
		"%s repaired!" % ShipRepairs.display_name(part),
		Color(0.55, 1.0, 0.85)
	)
	stat_tracker.add(GameTypes.Stat.SHIP_PARTS_REPAIRED, 1)
	game.refresh_action_bar()
	game.save_game()


# Send the robot to the nearest unfinished blueprint on this island. Returns false when none is left.
func _build_next_blueprint() -> bool:
	var sites := current_island.construction_sites()
	if sites.is_empty() or player_unit == null:
		return false

	var search := HexPathfinder.search(current_island, player_unit.current_cell)
	var costs: Dictionary = search.cost
	var best := GameTypes.NO_CELL
	var best_cost := INF
	for site in sites:
		for cell in current_island.get_building_footprint_cells(site):
			var cost: float = costs.get(cell, INF)
			if cost < best_cost or best == GameTypes.NO_CELL:
				best = site
				best_cost = cost
	return best != GameTypes.NO_CELL and command_to(best)


# A blueprint was just placed: put the robot to work on it, unless it is already building (or on its
# way to) another one — it moves on to this one when that is done (_build_next_blueprint).
func send_to_build(anchor_cell: Vector2i) -> void:
	if is_constructing:
		return
	if pending_action_cell != GameTypes.NO_CELL and current_island.is_under_construction(pending_action_cell):
		return
	command_to(anchor_cell)


# Bring K9-DA aboard: it starts following the robot, and the DOG_RESCUED stat completes the MAIN
# quest (whose completion toasts and saves). dog_rescued is set first so that save records it.
func _on_rescue_pressed() -> void:
	if not _can_rescue_dog():
		return

	world.dog_rescued = true
	dog.follow(current_island, dog.current_cell, player_unit)
	dog.celebrate()
	FloatingText.spawn(game, dog.position, "K9-DA rescued!", Color(1.0, 0.85, 0.45), 26)
	world_view.set_current_coord(world.current_coord)
	stat_tracker.add(GameTypes.Stat.DOG_RESCUED, 1)
	game.refresh_action_bar()
	game.save_game()


# Put K9-DA where the rescue state says: beside the robot once rescued; otherwise waiting at its
# spot as soon as its island is discovered, alongside the resources revealed on approach.
func sync_dog() -> void:
	if world.dog_rescued and player_unit.boat_id != -1:
		dog.halt()
		return
	if world.dog_rescued:
		dog.follow(current_island, _find_dog_follow_cell(), player_unit)
		return

	# Waits where it was left, once its island is drawn and discovered.
	var dog_island := world.get_island(world.dog_coord)
	if dog_island == null or world_view.renderer_for(world.dog_coord) == null or not dog_island.visited \
			or world_view.is_opening(world.dog_coord):
		dog.halt()
		return

	dog.strand(dog_island, world.dog_cell)


# Where the rescued dog appears when the robot lands: an open cell beside the robot, one step
# away (not up or down a cliff).
func _find_dog_follow_cell() -> Vector2i:
	for neighbor in HexGrid.neighbors(player_unit.current_cell):
		if WorldBuilder.is_open_ground(current_island, neighbor) \
				and HexPathfinder.can_step(current_island, player_unit.current_cell, neighbor):
			return neighbor
	return player_unit.current_cell


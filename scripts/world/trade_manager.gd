class_name TradeManager
extends RefCounted

# Runs every TradeRoute in the world each frame, moving goods between island inventories
# directly (all islands simulate in the background, so it doesn't matter which one the player
# is on). See docs/island-unlocks.md, "Trade routes move goods".
#
# Boats: each island allows one Dock carrying one boat, so it can be the HOME of one route.
# Existing saves keep their docks and routes. A route runs only while its home island has a dock
# for it and the away island has at least one dock; otherwise it idles at home
# (blocked_reason says why).
#
# Throughput is deliberately a trickle for now (the salvage skiff): BOAT_CAPACITY per leg, with
# trip time growing with world-map distance. Boat tiers will raise capacity and reach later.

signal route_created(route: TradeRoute)
signal route_removed(route: TradeRoute)
# Fired when a boat unloads at an island (coord), after the goods are in its inventory.
signal cargo_delivered(route: TradeRoute, coord: Vector2i, resource_type: int, amount: int)

const TradeRouteScript := preload("res://scripts/world/trade_route.gd")

const BOAT_CAPACITY := 5
# One-way sailing time: a fixed launch/landing overhead plus time per world-map hex crossed.
const BASE_TRIP_SECONDS := 12.0
const SECONDS_PER_HEX := 10.0
# How often a boat waiting at home for outbound cargo checks the stock again.
const RELOAD_CHECK_SECONDS := 2.0

var world: WorldData
var building_manager: BuildingManager


func setup(new_world: WorldData, new_building_manager: BuildingManager) -> void:
	world = new_world
	building_manager = new_building_manager


func update(now: float) -> void:
	if world == null:
		return
	for route in world.trade_routes:
		if now >= route.phase_end_time:
			_advance(route, now)


# --- Queries ---

func routes_involving(coord: Vector2i) -> Array[TradeRoute]:
	var result: Array[TradeRoute] = []
	for route in world.trade_routes:
		if route.involves(coord):
			result.append(route)
	return result


func routes_from(coord: Vector2i) -> Array[TradeRoute]:
	var result: Array[TradeRoute] = []
	for route in world.trade_routes:
		if route.home_coord == coord:
			result.append(route)
	return result


func dock_count(coord: Vector2i) -> int:
	var island := world.get_island(coord)
	if island == null:
		return 0
	var count := 0
	for anchor_cell in island.buildings:
		if island.buildings[anchor_cell].type == GameTypes.BuildingType.DOCK and not island.is_under_construction(anchor_cell):
			count += 1
	return count


# Boats at this island's docks not yet assigned to a route.
func free_boats(coord: Vector2i) -> int:
	return maxi(0, dock_count(coord) - routes_from(coord).size())


# Islands (other than coord) with a dock, i.e. valid destinations for a route from coord.
func reachable_destinations(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for other in world.ordered_coords():
		if other != coord and dock_count(other) > 0:
			result.append(other)
	return result


func trip_seconds(route: TradeRoute) -> float:
	return BASE_TRIP_SECONDS + SECONDS_PER_HEX * _world_distance(route.home_coord, route.away_coord)


# "" when the route can sail, else a short player-facing reason it's idle.
func blocked_reason(route: TradeRoute) -> String:
	var home_routes := routes_from(route.home_coord)
	if home_routes.find(route) >= dock_count(route.home_coord):
		return "Needs a free Dock on %s" % _island_name(route.home_coord)
	if dock_count(route.away_coord) == 0:
		return "Needs a Dock on %s" % _island_name(route.away_coord)
	return ""


# One-line status for UI, e.g. "Sailing to World 2 with 5 Wood (12s)".
func describe_status(route: TradeRoute, now: float) -> String:
	var remaining := maxi(0, ceili(route.phase_end_time - now))
	match route.phase:
		TradeRoute.Phase.OUTBOUND:
			return "Sailing to %s%s (%ds)" % [_island_name(route.away_coord), _cargo_text(route), remaining]
		TradeRoute.Phase.RETURNING:
			return "Returning to %s%s (%ds)" % [_island_name(route.home_coord), _cargo_text(route), remaining]
	var blocked := blocked_reason(route)
	if not blocked.is_empty():
		return "Idle: " + blocked
	return "Waiting for %s at %s" % [
		ResourceManager.get_display_name_for_type(route.outbound_resource),
		_island_name(route.home_coord),
	]


# --- Changes ---

func create_route(home_coord: Vector2i, away_coord: Vector2i, outbound_resource: int, return_resource: int) -> TradeRoute:
	if home_coord == away_coord or free_boats(home_coord) <= 0 or dock_count(away_coord) <= 0:
		return null
	if outbound_resource == TradeRoute.NO_RESOURCE and return_resource == TradeRoute.NO_RESOURCE:
		return null

	var route := TradeRouteScript.new(home_coord, away_coord, outbound_resource, return_resource, BOAT_CAPACITY)
	# phase_end_time 0 = load on the next update.
	world.trade_routes.append(route)
	route_created.emit(route)
	return route


# Anything aboard goes back to the island it was loaded at, so removing a route never loses goods.
func remove_route(route: TradeRoute) -> void:
	if not world.trade_routes.has(route):
		return
	if route.cargo_amount > 0:
		var source := route.home_coord if route.phase == TradeRoute.Phase.OUTBOUND else route.away_coord
		_inventory(source).add_amount(route.cargo_resource(), route.cargo_amount)
		route.cargo_amount = 0
	world.trade_routes.erase(route)
	route_removed.emit(route)


# --- The shuttle loop ---

func _advance(route: TradeRoute, now: float) -> void:
	match route.phase:
		TradeRoute.Phase.LOADING:
			_try_depart(route, now)
		TradeRoute.Phase.OUTBOUND:
			_unload(route, route.away_coord, route.outbound_resource)
			# Load the return leg (possibly nothing) and head straight back.
			route.cargo_amount = _load(route.away_coord, route.return_resource, route.capacity)
			_start_phase(route, TradeRoute.Phase.RETURNING, now, trip_seconds(route))
		TradeRoute.Phase.RETURNING:
			_unload(route, route.home_coord, route.return_resource)
			_start_phase(route, TradeRoute.Phase.LOADING, now, 0.0)
			_try_depart(route, now)


# Leave home if the route may sail and there is something to do: outbound cargo to carry, or a
# return resource to fetch. Otherwise wait and check again shortly.
func _try_depart(route: TradeRoute, now: float) -> void:
	if not blocked_reason(route).is_empty():
		_start_phase(route, TradeRoute.Phase.LOADING, now, RELOAD_CHECK_SECONDS)
		return

	var loaded := _load(route.home_coord, route.outbound_resource, route.capacity)
	if loaded == 0 and route.return_resource == TradeRoute.NO_RESOURCE:
		_start_phase(route, TradeRoute.Phase.LOADING, now, RELOAD_CHECK_SECONDS)
		return

	route.cargo_amount = loaded
	_start_phase(route, TradeRoute.Phase.OUTBOUND, now, trip_seconds(route))


func _load(coord: Vector2i, resource_type: int, capacity: int) -> int:
	if resource_type == TradeRoute.NO_RESOURCE:
		return 0
	var inventory := _inventory(coord)
	if inventory == null:
		return 0
	var amount := mini(capacity, inventory.get_amount(resource_type))
	if amount > 0:
		inventory.add_amount(resource_type, -amount)
	return amount


func _unload(route: TradeRoute, coord: Vector2i, resource_type: int) -> void:
	var amount := route.cargo_amount
	route.cargo_amount = 0
	if amount <= 0 or resource_type == TradeRoute.NO_RESOURCE:
		return
	var inventory := _inventory(coord)
	if inventory == null:
		return
	inventory.add_amount(resource_type, amount)
	route.delivered_total += amount
	cargo_delivered.emit(route, coord, resource_type, amount)


func _start_phase(route: TradeRoute, phase: int, now: float, duration: float) -> void:
	route.phase = phase
	route.phase_start_time = now
	route.phase_end_time = now + duration


func _inventory(coord: Vector2i) -> Inventory:
	var island := world.get_island(coord)
	return island.inventory if island != null else null


func _island_name(coord: Vector2i) -> String:
	var island := world.get_island(coord)
	return island.island_name if island != null else "?"


func _cargo_text(route: TradeRoute) -> String:
	if route.cargo_amount <= 0:
		return " (empty)"
	return " with %d %s" % [route.cargo_amount, ResourceManager.get_display_name_for_type(route.cargo_resource())]


# Hex distance between two world-map slots (axial coords).
static func _world_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

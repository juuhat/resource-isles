class_name TradeRoute
extends RefCounted

# A standing boat link between two islands' docks (see docs/island-unlocks.md, "Trade routes
# move goods"). One boat, based at a dock on the HOME island, shuttles forever: load up to
# `capacity` of outbound_resource at home, sail to the AWAY island, unload, load up to `capacity`
# of return_resource there, sail home, unload, repeat. Either leg's resource may be NO_RESOURCE
# (the boat sails that leg empty). Data and saved state only — TradeManager runs the loop.

const NO_RESOURCE := -1

enum Phase {
	LOADING, # at the home dock, loading (or waiting for) outbound cargo
	OUTBOUND, # sailing home -> away with cargo_amount of outbound_resource
	RETURNING, # sailing away -> home with cargo_amount of return_resource
}

var home_coord: Vector2i
var away_coord: Vector2i
var outbound_resource := NO_RESOURCE
var return_resource := NO_RESOURCE
var capacity := 0

var phase := Phase.LOADING
var cargo_amount := 0
# Absolute session-clock times (Time.get_ticks_msec() / 1000) bounding the current phase, like
# IslandData's production timers; saved relative to a reference time and rebased on load.
var phase_start_time := 0.0
var phase_end_time := 0.0
# Lifetime goods this route has unloaded (both legs), for the dock panel.
var delivered_total := 0


func _init(
	new_home_coord := Vector2i.ZERO,
	new_away_coord := Vector2i.ZERO,
	new_outbound_resource := NO_RESOURCE,
	new_return_resource := NO_RESOURCE,
	new_capacity := 0
) -> void:
	home_coord = new_home_coord
	away_coord = new_away_coord
	outbound_resource = new_outbound_resource
	return_resource = new_return_resource
	capacity = new_capacity


func involves(coord: Vector2i) -> bool:
	return home_coord == coord or away_coord == coord


# 0..1 progress through the current phase (sailing legs only; LOADING reports 0).
func phase_progress(now: float) -> float:
	if phase == Phase.LOADING or phase_end_time <= phase_start_time:
		return 0.0
	return clampf((now - phase_start_time) / (phase_end_time - phase_start_time), 0.0, 1.0)


# The resource currently aboard (NO_RESOURCE when empty or loading).
func cargo_resource() -> int:
	if cargo_amount <= 0:
		return NO_RESOURCE
	match phase:
		Phase.OUTBOUND:
			return outbound_resource
		Phase.RETURNING:
			return return_resource
	return NO_RESOURCE


# --- Save/load ---

func to_dict(reference_time: float) -> Dictionary:
	return {
		home_coord = home_coord,
		away_coord = away_coord,
		outbound_resource = outbound_resource,
		return_resource = return_resource,
		capacity = capacity,
		phase = phase,
		cargo_amount = cargo_amount,
		phase_start_time = phase_start_time - reference_time,
		phase_end_time = phase_end_time - reference_time,
		delivered_total = delivered_total,
	}


static func from_dict(data: Dictionary, reference_time: float) -> TradeRoute:
	var route := TradeRoute.new(
		data.get("home_coord", Vector2i.ZERO),
		data.get("away_coord", Vector2i.ZERO),
		int(data.get("outbound_resource", NO_RESOURCE)),
		int(data.get("return_resource", NO_RESOURCE)),
		int(data.get("capacity", 0))
	)
	route.phase = int(data.get("phase", Phase.LOADING))
	route.cargo_amount = int(data.get("cargo_amount", 0))
	route.phase_start_time = reference_time + float(data.get("phase_start_time", 0.0))
	route.phase_end_time = reference_time + float(data.get("phase_end_time", 0.0))
	route.delivered_total = int(data.get("delivered_total", 0))
	return route

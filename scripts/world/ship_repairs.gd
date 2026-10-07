class_name ShipRepairs
extends RefCounted

# Static catalog of the crashed ship's parts the robot repairs, one after another in
# GameTypes.ShipPart order: each part's name, the materials it takes (paid from the wreck island's
# stock when the repair starts) and the seconds of robot work at the wreck. Repair progress is
# WorldData.ship_repairs; the robot's Repair action is RobotController's. See
# docs/copper-and-the-radar.md.

const PARTS := {
	GameTypes.ShipPart.RADAR: {
		name = "Radar",
		cost = {GameTypes.ResourceType.COPPER_INGOT: 3},
		seconds = 8.0,
	},
}


static func display_name(part: int) -> String:
	return PARTS[part].name if PARTS.has(part) else "Unknown"


static func cost(part: int) -> Dictionary:
	return PARTS[part].cost if PARTS.has(part) else {}


static func work_seconds(part: int) -> float:
	return float(PARTS[part].seconds) if PARTS.has(part) else 1.0

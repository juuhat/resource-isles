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
		model_node = "Radar",
	},
}

# Repairable parts on the wreck model (tools/build_spaceship.py PARTS), each a '<Name>Broken' and a
# '<Name>Repaired' node. A part's model_node above names its own; the rest have no ShipPart yet
# and stay broken. See ShipWreck.
const MODEL_NODES: Array[String] = ["Radar", "Windshield", "Hull", "Wing", "Engine"]


static func display_name(part: int) -> String:
	return PARTS[part].name if PARTS.has(part) else "Unknown"


static func cost(part: int) -> Dictionary:
	return PARTS[part].cost if PARTS.has(part) else {}


static func work_seconds(part: int) -> float:
	return float(PARTS[part].seconds) if PARTS.has(part) else 1.0


# The ShipPart shown by the wreck model's node pair model_node (one of MODEL_NODES), or -1 if that
# part can't be repaired yet.
static func part_for_model_node(model_node: String) -> int:
	for part in PARTS:
		if PARTS[part].get("model_node", "") == model_node:
			return part
	return -1

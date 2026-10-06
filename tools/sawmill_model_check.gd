extends SceneTree

# Godot --headless --path . --script tools/sawmill_model_check.gd
# The imported sawmill (tools/build_sawmill.py) keeps its spinning parts separate, and the shared
# generator's socket sits where the robot's right forearm reaches when held level at the WorkSpot.

# Robot at 0.45 tiles tall = 0.9 model units (scale 0.75 from its native 1.2): right shoulder
# 0.29 * 0.75 to the side, elbow 0.52 * 0.75 up, forearm and gripper about 0.20 long.

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const HAND_SIDE := 0.2175
const ELBOW_HEIGHT := 0.39
const HAND_REACH := 0.20


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check")


func _check() -> void:
	var model := (load("res://assets/models/buildings/sawmill.glb") as PackedScene).instantiate() as Node3D
	root.add_child(model)
	for part_name in ["SawBladePivot", "FlywheelPivot", "SocketRotor"]:
		var part := model.find_child(part_name, true, false) as Node3D
		CheckWatchdog.require(part != null and part.get_child_count() > 0, part_name + " must keep its spinning meshes")
	var spot := model.find_child("WorkSpot", true, false) as Node3D
	var dock := model.find_child("DockPoint", true, false) as Node3D
	CheckWatchdog.require(spot != null and dock != null, "WorkSpot and the generator's DockPoint must survive export")

	# The robot at the spot faces the tile centre (-Z), so its right hand is toward +X.
	var spot_pos := model.to_local(spot.global_position)
	var dock_pos := model.to_local(dock.global_position)
	var offset := dock_pos - spot_pos
	print("WorkSpot ", spot_pos, "  DockPoint ", dock_pos, "  offset ", offset)
	CheckWatchdog.require(absf(offset.x - HAND_SIDE) < 0.01, "Socket lines up with the robot's right arm")
	CheckWatchdog.require(absf(dock_pos.y - ELBOW_HEIGHT) < 0.03, "Socket at the level forearm's height")
	CheckWatchdog.require(absf(-offset.z - HAND_REACH) < 0.02, "Socket just ahead of the robot's hand")

	var bounds := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local_bounds := model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
	print("Sawmill bounds ", bounds, "  width in tiles ", maxf(bounds.size.x, bounds.size.z) / 2.0)
	CheckWatchdog.require(bounds.position.y > -0.001, "Nothing reaches below the ground")
	print("SAWMILL MODEL CHECK OK")
	quit()

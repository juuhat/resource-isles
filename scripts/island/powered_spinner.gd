class_name PoweredSpinner
extends Node

# Spins a power consumer's moving parts (a saw blade, the shared generator's flywheel and
# socket) only while the building is powered, easing up to speed and coasting down when the
# power stops. Like BladeSpinner, it is added as a child of the spawned model, polls its
# island's powered flag (set every frame by PowerManager, including the robot's Operate
# hand-power) and is freed with the model on the next re-render.

# Seconds to reach full speed, and to coast back to a stop.
const SPIN_UP_SECONDS := 0.6
const SPIN_DOWN_SECONDS := 1.4

var island: IslandData
var anchor_cell := Vector2i(-1, -1)
var _targets: Array[Node3D] = []
var _axes: Array[Vector3] = []
var _speeds: Array[float] = []
var _throttle := 0.0


func add_target(target: Node3D, axis: Vector3, degrees_per_second: float) -> void:
	_targets.append(target)
	_axes.append(axis.normalized())
	_speeds.append(deg_to_rad(degrees_per_second))


func has_targets() -> bool:
	return not _targets.is_empty()


func _process(delta: float) -> void:
	var powered := island != null and island.buildings.has(anchor_cell) and island.is_consumer_powered(anchor_cell)
	var goal := 1.0 if powered else 0.0
	var rate := 1.0 / (SPIN_UP_SECONDS if powered else SPIN_DOWN_SECONDS)
	_throttle = move_toward(_throttle, goal, rate * delta)
	if _throttle <= 0.0:
		return
	for i in _targets.size():
		if is_instance_valid(_targets[i]):
			_targets[i].rotate_object_local(_axes[i], _speeds[i] * _throttle * delta)

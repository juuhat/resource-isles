class_name PoweredSpinner
extends Node

# Spins or chops a power consumer's moving parts (blades, generator pivots and the logger's
# axe) only while the building is powered, easing up to speed and coasting down when the
# power stops. Like BladeSpinner, it is added as a child of the spawned model, polls its
# island's powered flag (set every frame by PowerManager, including the robot's Operate
# hand-power) and is freed with the model on the next re-render.

# Seconds to reach full speed, and to coast back to a stop.
const SPIN_UP_SECONDS := 0.6
const SPIN_DOWN_SECONDS := 1.4
# The chop stroke as fractions of its period: a fast swing in, a pause in the wood, a slow pull back.
const CHOP_DROP_END := 0.12
const CHOP_LIFT_START := 0.58

var island: IslandData
var anchor_cell := GameTypes.NO_CELL
var _targets: Array[Node3D] = []
var _axes: Array[Vector3] = []
var _speeds: Array[float] = []
var _throttle := 0.0
var _chops: Array[Dictionary] = []
var _bellows: Array[Dictionary] = []


func add_target(target: Node3D, axis: Vector3, degrees_per_second: float) -> void:
	_targets.append(target)
	_axes.append(axis.normalized())
	_speeds.append(deg_to_rad(degrees_per_second))


func has_targets() -> bool:
	return not _targets.is_empty() or not _chops.is_empty() or not _bellows.is_empty()


# The accordion scales vertically from a fixed base; its rigid top follows the same stroke.
func add_bellows(body: Node3D, top: Node3D, height: float, period_seconds: float) -> void:
	_bellows.append({body = body, top = top, rest_scale = body.scale, rest_top = top.position,
		height = height, period = maxf(period_seconds, .01), phase = 0.0})


# Chopping stroke for the logger's felling axe: the authored pose is the blade in the wood, where
# an idle camp rests. Each period the axe pulls back strike_degrees about axis, swings in fast,
# then rests in the wood. Phase advances with the same throttle as the spinning parts, and
# starts in the wood so powering up begins from the authored pose.
func add_chop(target: Node3D, axis: Vector3, strike_degrees: float, period_seconds: float) -> void:
	var strike := deg_to_rad(strike_degrees)
	var rest := target.transform
	rest.basis = rest.basis * Basis(axis.normalized(), -strike)
	_chops.append({target = target, axis = axis.normalized(), rest = rest, strike = strike,
		period = maxf(period_seconds, .01), phase = CHOP_DROP_END})


# 0 pulled back, 1 with the blade in the wood.
static func chop_depth(phase: float) -> float:
	if phase < CHOP_DROP_END:
		var t := phase / CHOP_DROP_END
		return t * t
	if phase < CHOP_LIFT_START:
		return 1.0
	return 1.0 - smoothstep(CHOP_LIFT_START, 1.0, phase)


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
	for chop in _chops:
		var target := chop.target as Node3D
		if not is_instance_valid(target):
			continue
		chop.phase = fmod(float(chop.phase) + delta * _throttle / float(chop.period), 1.0)
		target.transform = chop.rest
		target.rotate_object_local(chop.axis, chop_depth(float(chop.phase)) * float(chop.strike))
	for bellows in _bellows:
		var body := bellows.body as Node3D
		var top := bellows.top as Node3D
		if not is_instance_valid(body) or not is_instance_valid(top):
			continue
		bellows.phase = fmod(float(bellows.phase) + delta * _throttle / float(bellows.period), 1.0)
		var expansion := 0.7 + 0.3 * cos(TAU * float(bellows.phase))
		body.scale = bellows.rest_scale
		body.scale.y *= expansion
		top.position = bellows.rest_top + Vector3(0, float(bellows.height) * (expansion - 1.0), 0)

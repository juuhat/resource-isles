extends RefCounted

# Shared by the world robot and the command-bar portrait.
const BLINK_DURATION := 0.20

var _eyes: Array[MeshInstance3D] = []
var _eye_rest_transforms: Array[Transform3D] = []
var _blink_wait := 0.0
var _blink_elapsed := -1.0

func _init(model: Node3D) -> void:
	for node in model.find_children("Amber eye*", "MeshInstance3D", true, false):
		_eyes.append(node as MeshInstance3D)
		_eye_rest_transforms.append(node.transform)
	_blink_wait = randf_range(2.5, 5.0)


# Compress the amber displays vertically about their centres. This runs independently
# of the body clips, so moving faster or changing tools never speeds up a blink.
func update(delta: float) -> void:
	if _eyes.is_empty():
		return
	if _blink_elapsed < 0.0:
		_blink_wait -= delta
		if _blink_wait > 0.0:
			return
		_blink_elapsed = 0.0
	else:
		_blink_elapsed += delta
	var openness := 1.0
	if _blink_elapsed >= BLINK_DURATION:
		_blink_elapsed = -1.0
		_blink_wait = randf_range(2.5, 5.0)
	else:
		# Fast close, brief slit, softer reopening.
		if _blink_elapsed < 0.06:
			openness = lerpf(1.0, 0.08, _blink_elapsed / 0.06)
		elif _blink_elapsed < 0.10:
			openness = 0.08
		else:
			openness = lerpf(0.08, 1.0, smoothstep(0.10, BLINK_DURATION, _blink_elapsed))
	for i in _eyes.size():
		var rest := _eye_rest_transforms[i]
		var center := _eyes[i].get_aabb().get_center()
		var pose := rest
		pose.basis = Basis.from_scale(Vector3(1.0, openness, 1.0)) * rest.basis
		pose.origin = rest * center - pose.basis * center
		_eyes[i].transform = pose



class_name CameraRig
extends Node3D

# Orbit camera rig: this node IS the pivot the camera circles, and it owns the Camera3D used
# for rendering and for picking rays. main.gd routes input here (zoom_in/zoom_out, pan,
# center_on) and reads get_camera() for ray casts; all the transform math lives in this file.
#
# Pitch is tied to zoom: close in we sit at a low hero angle, zoomed out we tilt up toward a
# top-down strategic view. Wheel zoom and drag pan are gameplay and work in every build; the
# Q/E/R/F orbit/tilt and the C-key framing print are debug-build-only angle-finding tools.

const ZOOM_STEP := 1.1
const MIN_DISTANCE := 300.0
const MAX_DISTANCE := 1200.0
# Pitch as a function of zoom: MIN_PITCH at closest zoom, MAX_PITCH at farthest.
const MIN_PITCH_DEGREES := 50.0
const MAX_PITCH_DEGREES := 65.0

var _camera: Camera3D
var _distance := 800.0
var _pitch_degrees := MIN_PITCH_DEGREES


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.far = 20000.0
	_camera.current = true
	add_child(_camera)
	_set_distance(_distance)
	# The Q/E/R/F live tilt in _process is debug-only; never spin it up in a shipped build.
	set_process(OS.is_debug_build())


func get_camera() -> Camera3D:
	return _camera


func zoom_in() -> void:
	_set_distance(_distance / ZOOM_STEP)


func zoom_out() -> void:
	_set_distance(_distance * ZOOM_STEP)


# Slide the pivot across the ground relative to the current yaw so it tracks the cursor
# whatever direction the camera faces. Scaled by distance so it keeps pace with zoom.
func pan(screen_delta: Vector2) -> void:
	var pan_scale := _distance * 0.0016
	var local_delta := Vector3(-screen_delta.x, 0.0, -screen_delta.y) * pan_scale
	position += basis * local_delta


func center_on(world_position: Vector3) -> void:
	position = world_position


func _set_distance(new_distance: float) -> void:
	_distance = clampf(new_distance, MIN_DISTANCE, MAX_DISTANCE)
	_pitch_degrees = _pitch_for_distance(_distance)
	_update_camera()


func _set_pitch(degrees: float) -> void:
	_pitch_degrees = clampf(degrees, 10.0, 89.0)
	_update_camera()


# Position the camera at the current distance/pitch behind the pivot and look at it.
func _update_camera() -> void:
	if _camera == null:
		return
	var pitch := deg_to_rad(_pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch) * _distance, cos(pitch) * _distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


# 0 at MIN_DISTANCE (closest) → 1 at MAX_DISTANCE (farthest), lerped between the pitch bounds
# so zooming out eases into the top-down strategic view.
func _pitch_for_distance(distance: float) -> float:
	var t := 0.0 if MAX_DISTANCE <= MIN_DISTANCE else clampf(
		(distance - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE), 0.0, 1.0
	)
	return lerpf(MIN_PITCH_DEGREES, MAX_PITCH_DEGREES, t)


# DEBUG BUILD ONLY (gated via set_process in _ready): live angle-finding controls — Q/E orbit
# (yaw), R/F tilt (pitch). Wheel zoom and drag pan are gameplay and run through the public
# methods instead, so they stay live in shipped builds.
func _process(delta: float) -> void:
	var yaw_speed := 1.5
	var pitch_speed := 40.0
	if Input.is_key_pressed(KEY_Q):
		rotation.y -= yaw_speed * delta
	if Input.is_key_pressed(KEY_E):
		rotation.y += yaw_speed * delta
	if Input.is_key_pressed(KEY_R):
		_set_pitch(_pitch_degrees + pitch_speed * delta)
	if Input.is_key_pressed(KEY_F):
		_set_pitch(_pitch_degrees - pitch_speed * delta)


# DEBUG BUILD ONLY: press C to print the current framing so a good test angle can be recorded.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		print("Camera: pitch=%.1f  yaw=%.1f  distance=%.0f" % [
			_pitch_degrees, rad_to_deg(rotation.y), _distance
		])

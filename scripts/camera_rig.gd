class_name CameraRig
extends Node3D

# Orbit camera rig: this node IS the pivot the camera circles, and it owns the Camera3D used
# for rendering and for picking rays. main.gd routes input here (zoom_in/zoom_out, pan,
# center_on, toggle_overview) and reads get_camera() for ray casts; all the transform math lives
# in this file.
#
# One continuous zoom covers both play and the world overview. Across the play range
# (MIN_DISTANCE..PLAY_MAX_DISTANCE) pitch is tied to zoom: close in we sit at a low hero angle,
# zoomed out we tilt up toward a top-down strategic view. Pull back further and the camera eases
# into the overview: the pivot drifts from the island to the centre of the disc, the view flattens
# into a three-quarter shot of the whole planet against the stars, the field of view narrows and
# the distance haze clears. overview_amount() (0..1) tells the world how far along that is.
#
# Zoom and pans glide toward their targets. Wheel zoom and drag pan are gameplay and work in
# every build; the Q/E/R/F orbit/tilt and the C-key framing print are debug-build-only
# angle-finding tools.

const ZOOM_STEP := 1.1
# Wheel steps grow beyond the play range so the long pull-back to the overview is quick.
const OVERVIEW_ZOOM_STEP := 1.3
const MIN_DISTANCE := 300.0
const PLAY_MAX_DISTANCE := 1200.0
# Pitch as a function of zoom: MIN_PITCH at closest zoom, MAX_PITCH at the top of the play
# range, easing to OVERVIEW_PITCH as the overview takes over.
const MIN_PITCH_DEGREES := 50.0
const MAX_PITCH_DEGREES := 65.0
const OVERVIEW_PITCH_DEGREES := 32.0
const PLAY_FOV := 75.0
const OVERVIEW_FOV := 40.0
# The overview blend runs (in log distance) from here to the overview distance.
const OVERVIEW_START_DISTANCE := 2500.0
const SMOOTHING := 7.0
# Depth fog range as multiples of the camera distance: starts just past the pivot (so the
# island in view stays clear) and is fully hazy toward the horizon. Zoomed out the view is
# more top-down and sees less distant water, so the range tightens to keep the haze visible.
# The haze fades away entirely as the overview takes over.
const FOG_BEGIN_FACTOR := 1.1
const FOG_END_FACTOR_NEAR := 4.0
const FOG_END_FACTOR_FAR := 2.3
# Sun shadows reach this many camera distances, so islands keep their shadows when zoomed out.
const SHADOW_DISTANCE_FACTOR := 4.0
const MIN_SHADOW_DISTANCE := 4000.0

var _camera: Camera3D
var _fog_environment: Environment
var _fog_density := 0.0
var _sun: DirectionalLight3D

# Targets (set by input) and the smoothed values actually shown.
var _target_pivot := Vector3.ZERO
var _pivot := Vector3.ZERO
var _target_distance := 800.0
var _distance := 800.0

var _overview_pivot := Vector3.ZERO
var _overview_distance := PLAY_MAX_DISTANCE
# Where toggle_overview returns to.
var _return_distance := 800.0
# Yaw from dragging in the overview; it unwinds as you zoom back into play.
var _overview_yaw := 0.0
# Debug-only tilt/orbit offsets (Q/E/R/F).
var _debug_yaw := 0.0
var _debug_pitch := 0.0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.far = 400000.0
	_camera.current = true
	add_child(_camera)
	_apply()


func get_camera() -> Camera3D:
	return _camera


func zoom_in() -> void:
	_set_target_distance(_target_distance / _zoom_step(_target_distance / ZOOM_STEP))


func zoom_out() -> void:
	_set_target_distance(_target_distance * _zoom_step(_target_distance))


# Slide the pivot across the ground relative to the current yaw so it tracks the cursor
# whatever direction the camera faces. Scaled by distance so it keeps pace with zoom. In the
# overview, dragging orbits around the disc instead.
func pan(screen_delta: Vector2) -> void:
	if overview_amount() > 0.5:
		_overview_yaw -= screen_delta.x * 0.006
		return

	var pan_scale := _distance * 0.0016
	var local_delta := Vector3(-screen_delta.x, 0.0, -screen_delta.y) * pan_scale
	var offset := Basis(Vector3.UP, _yaw()) * local_delta
	# Pans apply immediately (no glide) so the ground stays under the cursor.
	_target_pivot += offset
	_pivot += offset


# Glide the pivot to a point (e.g. the island just travelled to); `instant` jumps there.
func center_on(world_position: Vector3, instant := false) -> void:
	_target_pivot = world_position
	if instant:
		_pivot = world_position
		_apply()


# The disc-wide view the zoom eases into at its far end (set by the world, which knows its size).
func set_overview(pivot: Vector3, distance: float) -> void:
	_overview_pivot = pivot
	_overview_distance = maxf(distance, OVERVIEW_START_DISTANCE * 1.5)
	_set_target_distance(_target_distance)


# Jump between play and the full-disc overview (the M key).
func toggle_overview() -> void:
	if is_heading_to_overview():
		_set_target_distance(_return_distance)
	else:
		_return_distance = minf(_target_distance, PLAY_MAX_DISTANCE)
		_set_target_distance(_overview_distance)


# Zoom back down into play (Esc, or picking an island from the overview).
func exit_overview() -> void:
	_set_target_distance(_return_distance)


func is_heading_to_overview() -> bool:
	return _target_distance >= _overview_distance * 0.9


# 0 across the play range, rising to 1 at full overview.
func overview_amount() -> float:
	return _overview_for_distance(_distance)


# The environment whose depth fog should track the zoom (see FOG_BEGIN_FACTOR).
func set_fog_environment(environment: Environment) -> void:
	_fog_environment = environment
	_fog_density = environment.fog_density
	_apply()


# The sun whose shadow range should grow with the zoom.
func set_sun(sun: DirectionalLight3D) -> void:
	_sun = sun
	_apply()


func _process(delta: float) -> void:
	if OS.is_debug_build():
		_debug_controls(delta)

	var blend := 1.0 - exp(-SMOOTHING * delta)
	# Zoom eases in log space so the long pull-back to the overview feels even.
	_distance = exp(lerpf(log(_distance), log(_target_distance), blend))
	_pivot = _pivot.lerp(_target_pivot, blend)
	if overview_amount() <= 0.0 and _overview_for_distance(_target_distance) <= 0.0:
		_overview_yaw = 0.0
	_apply()


func _set_target_distance(distance: float) -> void:
	_target_distance = clampf(distance, MIN_DISTANCE, _overview_distance)


func _zoom_step(distance: float) -> float:
	return ZOOM_STEP if distance < PLAY_MAX_DISTANCE * 1.25 else OVERVIEW_ZOOM_STEP


func _yaw() -> float:
	return _debug_yaw + _overview_yaw * overview_amount()


# Position the rig at the (blended) pivot and the camera at the current distance/pitch behind it.
func _apply() -> void:
	if _camera == null:
		return
	var overview := overview_amount()
	position = _pivot.lerp(_overview_pivot, overview)
	rotation = Vector3(0.0, _yaw(), 0.0)
	var pitch := deg_to_rad(clampf(_pitch_for_distance(_distance) + _debug_pitch, 10.0, 89.0))
	_camera.position = Vector3(0.0, sin(pitch) * _distance, cos(pitch) * _distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	_camera.fov = lerpf(PLAY_FOV, OVERVIEW_FOV, overview)
	# Keep depth precision sensible across a 300..80000 unit zoom range.
	_camera.near = clampf(_distance * 0.01, 0.5, 400.0)

	if _fog_environment != null:
		_fog_environment.fog_depth_begin = _distance * FOG_BEGIN_FACTOR
		var zoom_t := inverse_lerp(MIN_DISTANCE, PLAY_MAX_DISTANCE, clampf(_distance, MIN_DISTANCE, PLAY_MAX_DISTANCE))
		_fog_environment.fog_depth_end = _distance * lerpf(FOG_END_FACTOR_NEAR, FOG_END_FACTOR_FAR, zoom_t)
		_fog_environment.fog_density = _fog_density * (1.0 - overview)
		_fog_environment.fog_enabled = overview < 0.999

	if _sun != null:
		_sun.directional_shadow_max_distance = maxf(MIN_SHADOW_DISTANCE, _distance * SHADOW_DISTANCE_FACTOR)


# Across the play range pitch lerps MIN -> MAX with zoom, so zooming out eases into the top-down
# strategic view; beyond it, the overview flattens it toward a three-quarter shot of the disc.
func _pitch_for_distance(distance: float) -> float:
	var t := 0.0 if PLAY_MAX_DISTANCE <= MIN_DISTANCE else clampf(
		(distance - MIN_DISTANCE) / (PLAY_MAX_DISTANCE - MIN_DISTANCE), 0.0, 1.0
	)
	var play_pitch := lerpf(MIN_PITCH_DEGREES, MAX_PITCH_DEGREES, t)
	return lerpf(play_pitch, OVERVIEW_PITCH_DEGREES, _overview_for_distance(distance))


func _overview_for_distance(distance: float) -> float:
	if _overview_distance <= OVERVIEW_START_DISTANCE:
		return 0.0
	var t := inverse_lerp(log(OVERVIEW_START_DISTANCE), log(_overview_distance), log(distance))
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))


# DEBUG BUILD ONLY: live angle-finding controls — Q/E orbit (yaw), R/F tilt (pitch). Wheel zoom
# and drag pan are gameplay and run through the public methods instead, so they stay live in
# shipped builds.
func _debug_controls(delta: float) -> void:
	var yaw_speed := 1.5
	var pitch_speed := 40.0
	if Input.is_key_pressed(KEY_Q):
		_debug_yaw -= yaw_speed * delta
	if Input.is_key_pressed(KEY_E):
		_debug_yaw += yaw_speed * delta
	if Input.is_key_pressed(KEY_R):
		_debug_pitch += pitch_speed * delta
	if Input.is_key_pressed(KEY_F):
		_debug_pitch -= pitch_speed * delta


# DEBUG BUILD ONLY: press C to print the current framing so a good test angle can be recorded.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		print("Camera: pitch=%.1f  yaw=%.1f  distance=%.0f  overview=%.2f" % [
			_pitch_for_distance(_distance) + _debug_pitch, rad_to_deg(_yaw()), _distance, overview_amount()
		])

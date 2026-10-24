## Smooth third-person chase camera with GTA-style mouse look.
##
## Sits behind and above the target, swings round smoothly when the target
## turns, pulls in when a wall is in the way and shakes briefly on crashes.
## Moving the mouse orbits the camera around the rickshaw (left/right and
## up/down); the mouse wheel zooms. While riding, the camera eases back behind
## the rickshaw a couple of seconds after you stop moving the mouse.
extends Camera3D

@export var target_path: NodePath
@export var distance := 5.0
## Extra distance at top speed so more road is visible.
@export var speed_distance := 1.2
@export var height := 2.5
## Height above the target's origin that the camera orbits around.
@export var pivot_height := 1.3
## How far ahead of the rickshaw the camera aims.
@export var look_ahead := 3.0
## Higher = the camera swings round faster after a turn.
@export var yaw_sharpness := 4.0
@export var base_fov := 68.0
@export var speed_fov := 6.0
## Physics layers that block the camera (world geometry).
@export_flags_3d_physics var obstacle_mask := 1

@export_group("Mouse look")
## Seconds without mouse movement before the camera recentres (while riding).
@export var recenter_delay := 1.8
## Up/down limits of the orbit, in radians of elevation.
@export var min_elevation := -0.12
@export var max_elevation := 1.25
@export var min_zoom := 0.6
@export var max_zoom := 1.7

var _target: Node3D
var _yaw := 0.0
var _distance_now := 0.0
var _trauma := 0.0
var _time := 0.0
## Mouse-look offsets from the normal chase view.
var orbit_yaw := 0.0
var orbit_pitch := 0.0
var zoom := 1.0
var _since_mouse := 10.0


func _ready() -> void:
	# We move the camera ourselves every rendered frame using the target's
	# interpolated transform, so engine interpolation must stay off here.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node_or_null(target_path)
	fov = base_fov
	if _target and _target.has_signal("was_reset"):
		_target.was_reset.connect(snap_to_target)
	snap_to_target()


## Adds screen shake. 0.3 = small jolt, 1.0 = big crash.
func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Instantly places the camera behind the target (no smoothing).
func snap_to_target() -> void:
	if _target == null:
		return
	_yaw = _target_yaw(_target.global_transform)
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	_distance_now = distance
	_update_camera(0.0, true)


func _target_yaw(xf: Transform3D) -> float:
	var fwd := -xf.basis.z
	return atan2(-fwd.x, -fwd.z)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	# On touchscreens fingers also make (fake) mouse events: the touch
	# controls turn the camera with their own drags instead.
	if event is InputEventMouseMotion and not Settings.touch_mode:
		orbit_by((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom * 0.9, min_zoom)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom * 1.1, max_zoom)


## Turns the camera round the rickshaw by a mouse or finger movement (pixels).
func orbit_by(motion: Vector2) -> void:
	var k := 0.0015 + Settings.mouse_sensitivity * 0.007  # radians per pixel
	orbit_yaw = wrapf(orbit_yaw - motion.x * k, -PI, PI)
	var y_sign := -1.0 if Settings.invert_mouse_y else 1.0
	orbit_pitch += motion.y * k * y_sign
	_since_mouse = 0.0


func _process(delta: float) -> void:
	if _target == null:
		return
	_time += delta
	_since_mouse += delta
	# Like GTA: when riding and the mouse is left alone, swing back behind.
	var moving: bool = "speed" in _target and absf(_target.speed) > 1.0
	if _since_mouse > recenter_delay and moving:
		var k := 1.0 - exp(-2.5 * delta)
		orbit_yaw = lerp_angle(orbit_yaw, 0.0, k)
		orbit_pitch = lerpf(orbit_pitch, 0.0, k)
	_update_camera(delta, false)


func _update_camera(delta: float, instant: bool) -> void:
	var xf := _target.get_global_transform_interpolated() if not instant else _target.global_transform
	var speed_t := 0.0
	if _target.has_method("get_speed_fraction"):
		speed_t = _target.get_speed_fraction()

	var wanted_yaw := _target_yaw(xf)
	if instant:
		_yaw = wanted_yaw
	else:
		_yaw = lerp_angle(_yaw, wanted_yaw, 1.0 - exp(-yaw_sharpness * delta))

	# Orbit position: the usual chase offset, turned and tilted by mouse look.
	var pivot := xf.origin + Vector3.UP * pivot_height
	var wanted_dist := distance + speed_distance * speed_t
	var base_elevation := atan2(height - pivot_height, wanted_dist)
	var radius := Vector2(wanted_dist, height - pivot_height).length() * zoom
	var elevation := clampf(base_elevation + orbit_pitch, min_elevation, max_elevation)
	orbit_pitch = elevation - base_elevation
	var offset := Basis(Vector3.UP, _yaw + orbit_yaw) * Vector3(0.0, sin(elevation), cos(elevation)) * radius
	var full_len := offset.length()
	var dir := offset / full_len

	# Pull in if a building or wall is between the rickshaw and the camera.
	var allowed := full_len
	var space := get_world_3d().direct_space_state
	if space:
		var exclude: Array[RID] = []
		if _target is CollisionObject3D:
			exclude.append((_target as CollisionObject3D).get_rid())
		var query := PhysicsRayQueryParameters3D.create(pivot, pivot + dir * (full_len + 0.3), obstacle_mask, exclude)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			allowed = maxf((hit.position - pivot).length() - 0.3, 1.2)
	if instant or allowed < _distance_now:
		_distance_now = allowed  # pull in immediately
	else:
		_distance_now = lerpf(_distance_now, allowed, 1.0 - exp(-2.0 * delta))

	global_position = pivot + dir * _distance_now
	# Look down the road normally; look at the rickshaw while orbiting.
	var fwd := -xf.basis.z
	fwd.y = 0.0
	var road_aim := xf.origin + Vector3.UP * (pivot_height * 0.75) + fwd.normalized() * look_ahead
	var orbit_amount := clampf(absf(orbit_yaw) / 0.6 + absf(orbit_pitch) / 0.6, 0.0, 1.0)
	var aim := road_aim.lerp(pivot, orbit_amount)
	if not global_position.is_equal_approx(aim):
		look_at(aim, Vector3.UP)

	var wanted_fov := base_fov + speed_fov * speed_t
	fov = wanted_fov if instant else lerpf(fov, wanted_fov, 1.0 - exp(-3.0 * delta))

	# Restrained crash shake using the camera's lens offsets.
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var shake := _trauma * _trauma
	h_offset = shake * 0.3 * (sin(_time * 41.0) + 0.5 * sin(_time * 87.0))
	v_offset = shake * 0.22 * (cos(_time * 37.0) + 0.5 * sin(_time * 71.0))

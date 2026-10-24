## Arcade controller for the player's pedal rickshaw.
##
## Uses a CharacterBody3D with a simple "bicycle" steering model instead of a
## full vehicle simulation: it is stable, cheap and cannot flip over.
## Crash *effects* (sounds, particles, damage) live in collision_manager.gd;
## this script detects impacts and plays the rickshaw's own sounds
## (bell, pedalling, freewheel, brakes, scraping).
extends CharacterBody3D

## Emitted when the rickshaw hits something hard enough to matter.
## severity: 0 = light bump, 1 = medium, 2 = heavy crash
## See last_impact_point / last_impact_normal for where it happened.
signal crashed(severity: int, impact_speed: float, other: Object)
signal horn_pressed
signal was_reset

const BELL_SOUNDS := ["res://assets/audio/rickshaw_bell.wav", "res://assets/audio/bell_short.wav"]
const FREEWHEEL_SOUND := "res://assets/audio/freewheel_loop.wav"
const PEDAL_SOUND := "res://assets/audio/pedal_loop.wav"
const SQUEAL_SOUND := "res://assets/audio/squeal.wav"
const SCRAPE_SOUND := "res://assets/audio/scrape_loop.wav"
const SFX_BUS := "SFX"
const CityLayout := preload("res://scripts/city_layout.gd")

@export_group("Speed")
@export var max_speed_kmh := 35.0
@export var max_reverse_kmh := 7.0
## Pedalling acceleration in m/s².
@export var acceleration := 2.0
@export var reverse_acceleration := 1.4
@export var brake_deceleration := 6.0
@export var handbrake_deceleration := 11.0
## Slow-down when neither pedalling nor braking.
@export var coast_deceleration := 0.45

@export_group("Steering")
@export var wheelbase := 1.6
@export var max_steer_degrees := 34.0
## Steering lock left at top speed, so fast turns stay controllable.
@export var high_speed_steer_degrees := 13.0
## How fast the handlebar turns, in radians per second.
@export var steer_rate := 2.6

@export_group("Collisions")
## Impact speeds (m/s) for medium and heavy crashes. Anything above
## `bump_threshold` is a light bump. Only the part of the speed going *into*
## the obstacle counts, so glancing scrapes stay light.
@export var bump_threshold := 1.2
@export var medium_threshold := 3.0
@export var heavy_threshold := 5.0

## Current forward speed in m/s (negative when reversing).
var speed := 0.0
## Current front fork angle in radians (positive = left).
var steer_angle := 0.0
## True when control input is accepted (e.g. disabled during cutscenes).
var controls_enabled := true
## Set by the collision manager: a battered rickshaw is a bit slower (0.75..1).
var damage_speed_factor := 1.0
## Where and how the last impact happened (for effects).
var last_impact_point := Vector3.ZERO
var last_impact_normal := Vector3.FORWARD
## True when the rickshaw is wrecked (condition 0%): it can't move until repaired.
var broken_down := false
## True while grinding along a wall or vehicle.
var scraping := false
## Seconds spent pushing against something without moving (stuck hint).
var pushing_time := 0.0

var _model: Node3D
var _bells: Array[AudioStream] = []
var _bell: AudioStreamPlayer
var _bell_index := 0
var _bell_repeat := 0.0
var _freewheel: AudioStreamPlayer
var _pedal: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _squeal_ready := true
var _spawn_transform: Transform3D
var _safe_transforms: Array[Transform3D] = []
var _safe_timer := 0.0
var _since_contact := 10.0
var _crash_cooldown := 0.0
var _lean := Vector2.ZERO  # x = pitch, y = roll
var _prev_speed := 0.0
var _kick := 0.0
var _kick_time := 0.0
var _hop := 0.0
var _hop_velocity := 0.0
# Footpath riding: wheels' height above the road (front, rear) and whether
# the rickshaw is up on the footpath.
var _wheel_lift := Vector2.ZERO
var on_footpath := false
var _curb_sound: AudioStreamPlayer
var _smoke: CPUParticles3D


func _ready() -> void:
	_model = $Model
	_spawn_transform = global_transform
	for path in BELL_SOUNDS:
		var s := _load_optional(path)
		if s:
			_bells.append(s)
	_bell = _make_player("", -4.0)
	_freewheel = _make_player(FREEWHEEL_SOUND, -14.0, true)
	_pedal = _make_player(PEDAL_SOUND, -13.0, true)
	_squeal = _make_player(SQUEAL_SOUND, -10.0)
	_scrape = _make_player(SCRAPE_SOUND, -9.0, true)
	_curb_sound = _make_player("res://assets/audio/bump.wav", -12.0)


func _load_optional(path: String) -> AudioStream:
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null


func _make_player(path: String, volume_db: float, loop := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _load_optional(path)
	p.volume_db = volume_db
	p.bus = SFX_BUS
	if loop and p.stream is AudioStreamWAV:
		var wav: AudioStreamWAV = p.stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	add_child(p)
	return p


func get_speed_kmh() -> float:
	return absf(speed) * 3.6


## 0..1 fraction of top speed, used by the camera and HUD.
func get_speed_fraction() -> float:
	return clampf(absf(speed) / (max_speed_kmh / 3.6), 0.0, 1.0)


func get_passenger_seat() -> Node3D:
	return _model.passenger_seat


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_input := 0.0
	var handbrake := false
	if controls_enabled and not broken_down:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake_reverse")
		steer_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		handbrake = Input.is_action_pressed("handbrake")
		_update_bell(delta)
		if Input.is_action_just_pressed("reset_vehicle"):
			reset_to_safe_position()
			return

	if broken_down:
		handbrake = true  # a wreck grinds to a halt
	_update_speed(throttle, handbrake, delta)
	_update_steering(steer_input, delta)

	# Bicycle model: yaw rate depends on speed, wheelbase and fork angle.
	var yaw_rate := speed / wheelbase * tan(steer_angle)
	rotate_y(yaw_rate * delta)

	var forward := -global_transform.basis.z
	var fall := velocity.y
	if is_on_floor():
		fall = -0.5  # keeps the body pressed onto the ground
	else:
		fall -= 20.0 * delta
	velocity = forward * speed + Vector3.UP * fall
	var pre_velocity := velocity
	move_and_slide()
	_handle_collisions(pre_velocity, forward, delta)

	# Pushing into something without getting anywhere (for the stuck hint).
	# Uses the real movement: contact reports flicker when pressing on a wall.
	if absf(throttle) > 0.1 and get_real_velocity().length() < 0.4 and _since_contact < 1.0:
		pushing_time += delta
	else:
		pushing_time = 0.0

	_update_safe_points(delta)
	if global_position.y < -10.0:
		reset_to_safe_position()

	_update_visuals(throttle, handbrake, delta)


func _update_speed(throttle: float, handbrake: bool, delta: float) -> void:
	var max_fwd := max_speed_kmh / 3.6 * damage_speed_factor
	var max_rev := max_reverse_kmh / 3.6
	if throttle > 0.05:
		if speed < -0.1:
			speed = move_toward(speed, 0.0, brake_deceleration * delta)
		else:
			# Pedalling gets harder near top speed.
			var effort := 1.0 - pow(clampf(speed / max_fwd, 0.0, 1.0), 2.0)
			speed += acceleration * throttle * maxf(effort, 0.0) * delta
	elif throttle < -0.05:
		if speed > 0.1:
			speed = move_toward(speed, 0.0, brake_deceleration * -throttle * delta)
		else:
			speed = move_toward(speed, -max_rev, reverse_acceleration * -throttle * delta)
	else:
		speed = move_toward(speed, 0.0, coast_deceleration * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, handbrake_deceleration * delta)
	speed = clampf(speed, -max_rev, max_fwd)


func _update_steering(steer_input: float, delta: float) -> void:
	var t := get_speed_fraction()
	var lock := deg_to_rad(lerpf(max_steer_degrees, high_speed_steer_degrees, t))
	var target := steer_input * lock
	# Return to centre (or swing to the other side) faster than turning in,
	# so quick left-right corrections feel responsive.
	var returning := absf(target) < absf(steer_angle) or signf(target) != signf(steer_angle)
	var rate := steer_rate * (1.8 if returning else 1.0)
	steer_angle = move_toward(steer_angle, target, rate * delta)


func _handle_collisions(pre_velocity: Vector3, forward: Vector3, delta: float) -> void:
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	var hardest := 0.0
	var hardest_obj: Object = null
	var hardest_col: KinematicCollision3D = null
	var hit_wall := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if n.y > 0.7:
			continue  # ground contact
		hit_wall = true
		var other := col.get_collider()
		# Works for moving traffic too (their velocity comes from the physics server).
		# Capped, so a vehicle being teleported can't fake a huge impact.
		var rel := pre_velocity - col.get_collider_velocity().limit_length(15.0)
		rel.y = 0.0
		n.y = 0.0
		# Direction matters: only the speed going into the obstacle counts.
		var impact := maxf(-rel.dot(n.normalized()), 0.0)
		# Heavier vehicles (buses!) hit harder.
		if other != null and "impact_multiplier" in other:
			impact *= other.impact_multiplier
		if impact > hardest or hardest_col == null:
			hardest = maxf(impact, hardest)
			hardest_obj = other
			hardest_col = col
	scraping = hit_wall and absf(speed) > 1.5
	if not hit_wall:
		_since_contact += delta
		return
	_since_contact = 0.0
	last_impact_point = hardest_col.get_position()
	last_impact_normal = hardest_col.get_normal()

	# Keep only the speed that survived sliding along the obstacle.
	var horizontal := velocity
	horizontal.y = 0.0
	var slid_speed := horizontal.dot(forward)
	if hardest > medium_threshold:
		# Bounce back a little on hard hits.
		speed = -signf(speed) * minf(hardest * 0.25, 2.0)
	elif absf(slid_speed) < absf(speed):
		speed = slid_speed

	if hardest >= bump_threshold and _crash_cooldown <= 0.0:
		var severity := 0
		if hardest >= heavy_threshold:
			severity = 2
		elif hardest >= medium_threshold:
			severity = 1
		_crash_cooldown = 0.6
		if hardest_obj != null and hardest_obj.has_method("on_player_impact"):
			hardest_obj.on_player_impact(hardest)
		crashed.emit(severity, hardest, hardest_obj)


## Visual jolt after a crash: a wobble, and a little hop on heavy hits.
func react_to_crash(severity: int) -> void:
	_kick = [0.04, 0.1, 0.17][clampi(severity, 0, 2)]
	_kick_time = 0.0
	if severity >= 2:
		_hop_velocity = 2.2
		if _model.has_method("show_dizzy"):
			_model.show_dizzy(2.5)


func play_horn() -> void:
	horn_pressed.emit()
	if _bells.is_empty():
		return
	# Alternate between the double "kring-kring" and a single ring.
	_bell.stream = _bells[_bell_index % _bells.size()]
	_bell_index += 1
	_bell.pitch_scale = randf_range(0.96, 1.04)
	_bell.play()


## Tap H for one ring; hold it and the puller keeps ringing.
func _update_bell(delta: float) -> void:
	if Input.is_action_just_pressed("horn"):
		play_horn()
		_bell_repeat = 0.6
	elif Input.is_action_pressed("horn"):
		_bell_repeat -= delta
		if _bell_repeat <= 0.0:
			play_horn()
			_bell_repeat = 0.55


## Remembers recent positions where the rickshaw was driving freely, so
## reset never drops it inside a wall or into the same jam.
func _update_safe_points(delta: float) -> void:
	_safe_timer += delta
	if _safe_timer < 1.0:
		return
	_safe_timer = 0.0
	if is_on_floor() and _since_contact > 1.5:
		_safe_transforms.append(global_transform)
		if _safe_transforms.size() > 6:
			_safe_transforms.pop_front()


## Puts the rickshaw back on its wheels at a recent safe spot (or the spawn
## point). Safe to call at any time.
func reset_to_safe_position() -> void:
	# Candidates: remembered safe spots (oldest first, furthest from whatever
	# went wrong), then the spawn point; each also shifted along the road.
	# The first one not blocked by buildings or traffic wins.
	var candidates: Array[Transform3D] = []
	for xf in _safe_transforms:
		candidates.append(_upright(xf))
	candidates.append(_upright(_spawn_transform))
	var target: Transform3D = candidates[0]
	var found := false
	for xf in candidates:
		for shift in [0.0, 5.0, -5.0, 10.0, -10.0]:
			var c := xf.translated(-xf.basis.z * shift)
			if _spot_is_free(c):
				target = c
				found = true
				break
		if found:
			break
	_safe_transforms.clear()
	_safe_transforms.append(target)
	global_transform = target
	velocity = Vector3.ZERO
	speed = 0.0
	steer_angle = 0.0
	_since_contact = 10.0
	_lean = Vector2.ZERO
	_kick = 0.0
	_hop = 0.0
	_hop_velocity = 0.0
	_wheel_lift = Vector2(_kerb_height(target.origin), _kerb_height(target.origin))
	pushing_time = 0.0
	_crash_cooldown = 1.0  # grace period: no crash events right after a reset
	reset_physics_interpolation()
	was_reset.emit()


## Same place, standing upright, slightly above the ground, and turned to
## face along the road (the road direction closest to its old heading), so
## you can pedal straight off after a reset.
func _upright(xf: Transform3D) -> Transform3D:
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var best := -2.0
	var aligned := fwd
	for d in CityLayout.road_directions_at(xf.origin.x, xf.origin.z):
		if d.dot(fwd) > best:
			best = d.dot(fwd)
			aligned = d
	return Transform3D(Basis.looking_at(aligned, Vector3.UP), Vector3(xf.origin.x, 0.05, xf.origin.z))


## True if the rickshaw's box at `xf` would not overlap buildings or traffic.
func _spot_is_free(xf: Transform3D) -> bool:
	var shape_node: CollisionShape3D = $CollisionShape3D
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape_node.shape
	q.transform = xf.translated(Vector3.UP * 0.1) * shape_node.transform
	q.collision_mask = 1 | 4  # world and traffic
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Wrecks the rickshaw: it stops, slumps to one side and smokes.
func break_down() -> void:
	if broken_down:
		return
	broken_down = true
	_hop_velocity = 2.5
	if _model.has_method("show_dizzy"):
		_model.show_dizzy(6.0)
	if _smoke == null:
		_smoke = CPUParticles3D.new()
		_smoke.amount = 24
		_smoke.lifetime = 2.2
		_smoke.direction = Vector3.UP
		_smoke.spread = 20.0
		_smoke.initial_velocity_min = 0.8
		_smoke.initial_velocity_max = 1.6
		_smoke.gravity = Vector3(0.3, 0.4, 0)
		_smoke.scale_amount_min = 1.0
		_smoke.scale_amount_max = 2.2
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.5)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		quad.material = mat
		_smoke.mesh = quad
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.15, 0.15, 0.15, 0.8))
		ramp.set_color(1, Color(0.35, 0.35, 0.35, 0.0))
		_smoke.color_ramp = ramp
		_smoke.position = Vector3(0, 0.9, 0.4)
		add_child(_smoke)
	_smoke.emitting = true


## Repaired and moved (e.g. towed to the mechanic): ready to ride again.
func repair_at(xf: Transform3D) -> void:
	broken_down = false
	if _smoke:
		_smoke.emitting = false
	_safe_transforms.clear()
	_safe_transforms.append(_upright(xf))
	reset_to_safe_position()


## Hard reset to where the level placed the rickshaw (used by restart).
func reset_to_spawn() -> void:
	_safe_transforms.clear()
	reset_to_safe_position()


func _update_visuals(throttle: float, handbrake: bool, delta: float) -> void:
	var pedaling := throttle > 0.05 and speed > -0.1
	_model.update_motion(speed, steer_angle, pedaling, delta)
	# A little arcade body roll in turns and pitch when braking/accelerating.
	var accel := (speed - _prev_speed) / maxf(delta, 0.0001)
	_prev_speed = speed
	var target_pitch := clampf(accel * 0.012, -0.05, 0.03)
	var target_roll := clampf(-steer_angle * get_speed_fraction() * 0.25, -0.07, 0.07)
	var k := 1.0 - exp(-8.0 * delta)
	_lean.x = lerpf(_lean.x, target_pitch, k)
	_lean.y = lerpf(_lean.y, target_roll, k)
	# Crash wobble and hop.
	_kick_time += delta
	_kick = move_toward(_kick, 0.0, delta * 0.3)
	var wobble := _kick * sin(_kick_time * 24.0)
	if _hop > 0.0 or _hop_velocity > 0.0:
		_hop_velocity -= 12.0 * delta
		_hop = maxf(_hop + _hop_velocity * delta, 0.0)
		if _hop == 0.0:
			_hop_velocity = 0.0
	_update_footpath(delta)
	var curb_pitch := atan2(_wheel_lift.x - _wheel_lift.y, 1.6)
	_model.rotation = Vector3(_lean.x + wobble * 0.4 + curb_pitch, 0.0, _lean.y + wobble)
	if broken_down:
		# Slumped on a broken rear wheel.
		_model.rotation += Vector3(-0.06, 0.0, 0.2)
	_model.position.y = _hop + (_wheel_lift.x + _wheel_lift.y) * 0.5

	# Rickshaw sounds: freewheel ticking when coasting, chain and creak when
	# pedalling, a squeal on hard braking, grinding along walls.
	var rolling := absf(speed) > 0.6
	_loop(_freewheel, rolling and not pedaling, clampf(0.5 + absf(speed) * 0.12, 0.5, 1.6))
	_loop(_pedal, pedaling and absf(speed) > 0.3, clampf(0.6 + absf(speed) * 0.12, 0.6, 1.5))
	_loop(_scrape, scraping, clampf(0.7 + absf(speed) * 0.08, 0.7, 1.3))
	var hard_brake := (handbrake or throttle < -0.5) and speed > 3.0
	if hard_brake and _squeal_ready and _squeal.stream:
		_squeal.pitch_scale = randf_range(0.95, 1.08)
		_squeal.play()
		_squeal_ready = false
	elif not hard_brake and speed < 1.0:
		_squeal_ready = true


## Footpaths are 15 cm above the road. The rickshaw rides up and down the
## kerb: each wheel rises in turn (tilting the body), with a bump and a
## little lost speed when climbing up.
func _update_footpath(delta: float) -> void:
	var front := global_transform * Vector3(0, 0, -1.05)
	var rear := global_transform * Vector3(0, 0, 0.55)
	var target := Vector2(_kerb_height(front), _kerb_height(rear))
	var was := on_footpath
	on_footpath = target.x > 0.0 or target.y > 0.0
	if target.x > _wheel_lift.x + 0.05 and absf(speed) > 1.0:
		_kick = maxf(_kick, 0.035)
		_kick_time = 0.0
		speed *= 0.93
		if _curb_sound.stream and not _curb_sound.playing:
			_curb_sound.pitch_scale = randf_range(1.1, 1.3)
			_curb_sound.play()
	elif was != on_footpath and absf(speed) > 1.0:
		_kick = maxf(_kick, 0.025)
		_kick_time = 0.0
	var rate := 1.2 + absf(speed) * 0.6
	_wheel_lift.x = move_toward(_wheel_lift.x, target.x, rate * delta)
	_wheel_lift.y = move_toward(_wheel_lift.y, target.y, rate * delta)


func _kerb_height(p: Vector3) -> float:
	return 0.0 if CityLayout.is_road(p.x, p.z) else 0.15


func _loop(p: AudioStreamPlayer, on: bool, pitch: float) -> void:
	if p.stream == null:
		return
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()
	p.pitch_scale = pitch

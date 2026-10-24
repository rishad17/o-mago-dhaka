## The passenger job: find a passenger, stop, press E, drive them to their
## destination, stop, press E, get paid.
##
## Trip states:  NONE -> BOARDING -> ON_BOARD -> EXITING -> NONE
## Only one passenger rides at a time. Every transition checks the current
## state, so a passenger can't be picked up twice, a fare can't be paid twice,
## and drop-off only works inside the destination zone. Some walking
## pedestrians become waiting passengers by themselves; jobs are optional.
extends Node

const Pedestrian := preload("res://scripts/pedestrian.gd")
const PersonModel := preload("res://scripts/person_model.gd")
const CityLayout := preload("res://scripts/city_layout.gd")
const CHIME := "res://assets/audio/chime.wav"
const COINS := "res://assets/audio/coins.wav"

enum Trip { NONE, BOARDING, ON_BOARD, EXITING }

## How close (m) the rickshaw must be to a waiting passenger.
const PICKUP_RADIUS := 5.0
## Max speed (m/s, about 5 km/h) for picking up or dropping off.
const MAX_STOP_SPEED := 1.5
const MAX_WAITING := 4
## Illustrative game values, not real Dhaka fares.
const BASE_FARE := 20
const FARE_PER_METRE := 0.1
const QUICK_TIP := 10
const ACCIDENT_PENALTY := 5

signal trip_started(destination: String, fare: int)
signal trip_completed(fare: int)
signal trip_cancelled(reason: String)

@export var player_path: NodePath
@export var camera_path: NodePath
@export var hud_path: NodePath
@export var destinations_path: NodePath
@export var pedestrians_path: NodePath
## -1 = different every game; set a number for repeatable tests.
@export var passenger_seed := -1

var trip_state: Trip = Trip.NONE
var passenger: Node3D = null
var destination: Node3D = null
var fare_estimate := 0
var trips_completed := 0
var fares_paid := 0

var _player: Node3D
var _camera: Camera3D
var _hud: Node
var _dest: Node
var _peds: Node
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 0.5
var _trip_time := 0.0
var _trip_accidents := 0
var _trip_distance := 0.0
var _trip_id := 0
var _paid_trip_id := -1
var _wrong_place_cooldown := 0.0
var _pickup_spots: Array[Vector3] = []
var _chime: AudioStreamPlayer
var _coins: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	if passenger_seed >= 0:
		_rng.seed = passenger_seed
	else:
		_rng.randomize()
	_player = get_node_or_null(player_path)
	_camera = get_node_or_null(camera_path)
	_hud = get_node_or_null(hud_path)
	_dest = get_node_or_null(destinations_path)
	_peds = get_node_or_null(pedestrians_path)
	_chime = _make_sound(CHIME, -4.0)
	_coins = _make_sound(COINS, -2.0)
	# Good places to wait for a rickshaw: landmarks and street corners.
	for d in CityLayout.destinations():
		_pickup_spots.append(d.sidewalk)
	if _peds:
		for p in _peds.network.node_pos:
			_pickup_spots.append(p)
	if _player:
		_player.crashed.connect(_on_player_crashed)
	_update_hud()


func _make_sound(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = db
	p.bus = "UI"
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	if _player == null or _dest == null or _peds == null:
		return
	_wrong_place_cooldown -= delta
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 2.0
		_manage_waiting_passengers()
	var pressed: bool = Input.is_action_just_pressed("interact") and _player.controls_enabled
	match trip_state:
		Trip.NONE:
			_look_for_passenger(pressed)
		Trip.ON_BOARD:
			_trip_time += delta
			_drive_to_destination(pressed)
		_:
			_show_prompt("")


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _player_speed() -> float:
	return absf(_player.speed)


func _show_prompt(text: String) -> void:
	if _hud:
		_hud.show_prompt(text)


# --- Waiting passengers ------------------------------------------------------------------

func waiting_passengers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for ped in _peds.pedestrians:
		if ped.state == Pedestrian.State.WAITING_FOR_PICKUP:
			out.append(ped)
	return out


func _manage_waiting_passengers() -> void:
	var waiting := waiting_passengers()
	# People don't wait forever.
	for ped in waiting:
		if ped.waiting_time() > 150.0 and _peds.distance_to_player(ped.global_position) > 40.0:
			ped.stop_waiting()
	if waiting.size() >= MAX_WAITING:
		return
	# A walking pedestrian near a good pickup spot decides to take a rickshaw.
	var best: Node3D = null
	var best_score := 1e9
	for k in 14:
		var ped: Node3D = _peds.pedestrians[_rng.randi() % _peds.pedestrians.size()]
		if not ped.is_free_walker():
			continue
		var d_player: float = _peds.distance_to_player(ped.global_position)
		if d_player < 25.0 or d_player > 160.0:
			continue
		var crowded := false
		for w in waiting:
			if _flat_distance(w.global_position, ped.global_position) < 30.0:
				crowded = true
		if crowded:
			continue
		var score := 1e9
		for s in _pickup_spots:
			score = minf(score, _flat_distance(s, ped.global_position))
		score += d_player * 0.1  # prefer passengers not too far from the player
		if score < best_score:
			best_score = score
			best = ped
	if best:
		best.become_waiting_passenger()


# --- Pickup ------------------------------------------------------------------------------

func _nearest_waiting(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	var c: Vector3 = _player.global_transform * Vector3(0, 0, -0.24)
	for ped in _peds.pedestrians:
		if ped.state != Pedestrian.State.WAITING_FOR_PICKUP:
			continue
		var d := _flat_distance(ped.global_position, c)
		if d < best_d:
			best_d = d
			best = ped
	return best


func _look_for_passenger(pressed: bool) -> void:
	var ped := _nearest_waiting(PICKUP_RADIUS)
	if ped == null:
		_show_prompt("")
		return
	if _player_speed() > MAX_STOP_SPEED:
		_show_prompt("যাত্রী নিতে থামুন")
		return
	_show_prompt("যাত্রী নিতে E চাপুন")
	if pressed:
		begin_pickup(ped)


## Starts boarding. Returns false (and does nothing) if not allowed.
func begin_pickup(ped: Node3D) -> bool:
	if trip_state != Trip.NONE or passenger != null:
		return false
	if ped == null or ped.state != Pedestrian.State.WAITING_FOR_PICKUP:
		return false
	if _player_speed() > MAX_STOP_SPEED:
		return false
	if _flat_distance(ped.global_position, _player.global_position) > PICKUP_RADIUS + 1.5:
		return false
	var pickup_zone: Node3D = _dest.zone_at(ped.global_position)
	var dest: Node3D = _dest.pick_destination(ped.global_position, 60.0, pickup_zone)
	if dest == null:
		return false
	trip_state = Trip.BOARDING
	_trip_id += 1
	passenger = ped
	destination = dest
	_trip_distance = absf(dest.global_position.x - ped.global_position.x) + absf(dest.global_position.z - ped.global_position.z)
	fare_estimate = BASE_FARE + roundi(_trip_distance * FARE_PER_METRE)
	ped.accept_ride()
	ped.say(dest.zone_name + " যাবেন?", 2.5)
	_hold_player(true)
	_show_prompt("")
	# Walk to the side of the rickshaw nearest to them, then climb on.
	var local: Vector3 = _player.global_transform.affine_inverse() * ped.global_position
	var side := 1.0 if local.x > 0.0 else -1.0
	var start: Vector3 = ped.global_position
	var target: Vector3 = _player.global_transform * Vector3(side * 1.1, 0, 0.4)
	target.y = start.y
	var dir := target - start
	if dir.length_squared() > 0.001:
		ped.rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
	var duration := clampf(start.distance_to(target) / 1.6, 0.4, 1.6)
	_tween = create_tween()
	_tween.tween_method(_move_on.bind(start, target), 0.0, 1.0, duration)
	_tween.tween_callback(_seat_passenger)
	return true


func _move_on(f: float, start: Vector3, target: Vector3) -> void:
	passenger.global_position = start.lerp(target, f)


func _seat_passenger() -> void:
	if trip_state != Trip.BOARDING or passenger == null:
		return
	var seat: Node3D = _player.get_passenger_seat()
	passenger.reparent(seat, false)
	passenger.transform = Transform3D(Basis(), Vector3(0, -PersonModel.HIP_Y + 0.05, 0.02))
	passenger.sit_down()
	passenger.model.animate = true
	passenger.model.set_far(false)
	trip_state = Trip.ON_BOARD
	_trip_time = 0.0
	_trip_accidents = 0
	_dest.set_active_zone(destination)
	_hold_player(false)
	if _chime.stream:
		_chime.play()
	GameManager.post_message("যাত্রী উঠেছেন!\nগন্তব্য: " + destination.zone_name, GameManager.MSG_GOOD)
	_update_hud()
	trip_started.emit(destination.zone_name, fare_estimate)


# --- Driving to the destination ------------------------------------------------------------

func is_at_destination() -> bool:
	if destination == null:
		return false
	return _flat_distance(_player.global_position, destination.global_position) <= destination.radius


func _drive_to_destination(pressed: bool) -> void:
	_update_hud()
	if is_at_destination():
		if _player_speed() > MAX_STOP_SPEED:
			_show_prompt("থামুন, যাত্রী নামবেন")
		else:
			_show_prompt("যাত্রী নামাতে E চাপুন")
			if pressed:
				begin_dropoff()
		return
	_show_prompt("")
	if pressed and _wrong_place_cooldown <= 0.0:
		_wrong_place_cooldown = 3.0
		GameManager.post_message("এখানে নয়!\nগন্তব্য: " + destination.zone_name, GameManager.MSG_WARN)


func final_fare() -> Dictionary:
	var expected_time := _trip_distance / 5.0 * 1.3 + 12.0
	var tip := QUICK_TIP if _trip_time <= expected_time and _trip_accidents == 0 else 0
	var penalty := ACCIDENT_PENALTY * _trip_accidents
	var total := maxi(BASE_FARE, fare_estimate + tip - penalty)
	return {"total": total, "tip": tip, "penalty": penalty}


## Starts the drop-off. Returns false (and does nothing) if not allowed.
func begin_dropoff() -> bool:
	if trip_state != Trip.ON_BOARD or passenger == null or not is_at_destination():
		return false
	if _player_speed() > MAX_STOP_SPEED:
		return false
	trip_state = Trip.EXITING
	_hold_player(true)
	_show_prompt("")
	# Pay exactly once per trip, right away.
	var fare := final_fare()
	if _paid_trip_id != _trip_id:
		_paid_trip_id = _trip_id
		GameManager.add_earnings(fare.total)
		fares_paid += 1
	# The trip is done the moment the fare is paid: tell the player right away.
	_dest.set_active_zone(null)
	if _hud:
		_hud.set_passenger_status("যাত্রী: নেই")
		_hud.set_trip_info("", 0, 0)
		_hud.set_compass(false, 0.0)
	if _coins.stream:
		_coins.play()
	var text := "যাত্রা সম্পন্ন!\nভাড়া পেয়েছেন: " + GameManager.format_taka(fare.total)
	if fare.tip > 0:
		text += "  (বখশিশ " + GameManager.format_taka(fare.tip) + ")"
	elif fare.penalty > 0:
		text += "  (দুর্ঘটনার জন্য -" + GameManager.format_taka(fare.penalty) + ")"
	GameManager.post_message(text, GameManager.MSG_GOOD)
	passenger.say("ধন্যবাদ ভাই!", 3.0)
	_step_off(destination.sidewalk_point, _finish_dropoff.bind(fare))
	return true


func _finish_dropoff(fare: Dictionary) -> void:
	passenger.finish_trip()
	passenger.say("ধন্যবাদ ভাই!", 2.0)
	_end_trip()
	trips_completed += 1
	GameManager.add_trip()
	get_tree().create_timer(3.2, false).timeout.connect(_suggest_new_trip)
	trip_completed.emit(fare.total)


func _suggest_new_trip() -> void:
	if trip_state == Trip.NONE:
		GameManager.post_message("নতুন যাত্রীর খোঁজ করুন", GameManager.MSG_INFO)


## Passenger climbs down from the seat and walks to `target` on the sidewalk.
func _step_off(target: Vector3, done: Callable) -> void:
	var ped := passenger
	ped.reparent(_peds, true)
	ped.state = Pedestrian.State.EXITING
	ped.model.set_pose(PersonModel.Pose.WALK)
	ped.model.speed = 1.5
	var start := ped.global_position
	start.y = 0.0
	var dir := target - start
	ped.rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
	var duration := clampf(start.distance_to(target) / 1.8, 0.6, 2.2)
	_tween = create_tween()
	_tween.tween_method(_move_off.bind(start, target), 0.0, 1.0, duration)
	_tween.tween_callback(done)


func _move_off(f: float, start: Vector3, target: Vector3) -> void:
	var p := start.lerp(target, f)
	p.y = lerpf(0.0, target.y, f)
	passenger.global_position = p


func _end_trip() -> void:
	passenger = null
	destination = null
	fare_estimate = 0
	trip_state = Trip.NONE
	_dest.set_active_zone(null)
	_hold_player(false)
	_update_hud()


# --- Accidents with a passenger on board ------------------------------------------------

func _on_player_crashed(severity: int, _impact: float, _other: Object) -> void:
	if trip_state != Trip.ON_BOARD:
		return
	if severity == 1:
		_trip_accidents += 1
		passenger.say("আস্তে চালান!", 2.0)
	elif severity >= 2:
		cancel_trip("যাত্রী নেমে গেছেন!")


## Cancels the current trip (no fare). The passenger gets off safely.
func cancel_trip(reason: String) -> void:
	if trip_state != Trip.ON_BOARD or passenger == null:
		return
	trip_state = Trip.EXITING
	_hold_player(true)
	_show_prompt("")
	var hit: Array = _peds.network.nearest_walk_point(_player.global_position)
	var target: Vector3 = _peds.network.point_on(hit[0], hit[1])
	_step_off(target, _finish_cancel.bind(reason))


func _finish_cancel(reason: String) -> void:
	passenger.finish_trip("আর যাবো না!")
	_end_trip()
	GameManager.post_message("দুর্ঘটনা!\n" + reason, GameManager.MSG_BAD)
	trip_cancelled.emit(reason)


# --- Helpers ------------------------------------------------------------------------------

func _hold_player(hold: bool) -> void:
	_player.controls_enabled = not hold
	if hold:
		_player.speed = 0.0
		_player.velocity = Vector3.ZERO


func _update_hud() -> void:
	if _hud == null:
		return
	if trip_state == Trip.ON_BOARD and destination:
		var dist := _flat_distance(_player.global_position, destination.global_position)
		_hud.set_passenger_status("যাত্রী: আছে")
		_hud.set_trip_info(destination.zone_name, fare_estimate, roundi(dist))
		_hud.set_compass(true, _compass_angle(destination.global_position))
	else:
		_hud.set_passenger_status("যাত্রী: নেই")
		_hud.set_trip_info("", 0, 0)
		_hud.set_compass(false, 0.0)


## Screen angle (radians, clockwise) from the camera's forward to the target.
func _compass_angle(target: Vector3) -> float:
	var basis: Basis = _camera.global_transform.basis if _camera else _player.global_transform.basis
	var fwd := -basis.z
	var to := target - _player.global_position
	var f := Vector2(fwd.x, fwd.z).normalized()
	var t := Vector2(to.x, to.z).normalized()
	return f.angle_to(t)

## A pedestrian walking the sidewalks of Dhaka. Some become passengers.
##
## Updated by PedestrianManager (step()) rather than every frame on its own,
## so far-away pedestrians can be simulated less often.
extends Node3D

const PersonModel := preload("res://scripts/person_model.gd")
const PedestrianNetwork := preload("res://scripts/pedestrian_network.gd")
const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"

enum State {
	WALKING,             ## following the sidewalk network
	WAIT_CROSS,          ## at the kerb, looking before crossing
	CROSSING,            ## on the road
	WAITING_FOR_PICKUP,  ## a potential passenger, waving for a rickshaw
	ACCEPTED,            ## the player stopped for them; boarding
	ON_BOARD,            ## sitting in the player's rickshaw
	EXITING,             ## getting off at the destination
	KNOCKED,             ## knocked down by a vehicle
	RECOVERING,          ## getting up and walking back to the sidewalk
	VICTIM,              ## being mugged (held by the mugging manager)
}

const KNOCK_DOWN_TIME := 3.0
const CROSS_PATIENCE := Vector2(4.0, 9.0)
const CALLS := ["রিকশা!", "এই রিকশা!", "মামা, যাবেন?", "রিকশা! রিকশা!"]
## "ও মাগো!" (oh mother!) is the classic cry; it comes up often, the other
## complaints the rest of the time.
static func random_hit_shout(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.35:
		return "ও মাগো!"
	return HIT_SHOUTS[rng.randi() % HIT_SHOUTS.size()]


const HIT_SHOUTS := ["আরে! দেখে চালান!", "আস্তে চালাও!", "এই রিকশা!", "চোখ নাই নাকি?",
	"তোর রিকশা ভইরা দিমু!", "তোর রিকশা ভাঙমু!", "কানের উপর একটা দিমু!"]

var state: State = State.WALKING
var model: Node3D
## Shared record for traffic sensing while on the road.
var obstacle := {}
var walk_speed := 1.3
## Off for muggers sneaking up on someone (no sudden road crossings).
var allow_crossing := true
## True while a mugger is after this person (they can't become a passenger).
var targeted := false
var on_road := false

var _manager: Node
var _network
var _rng := RandomNumberGenerator.new()
var _edge := -1
var _t := 0.0
var _dir := 1
# Free path (crossings, getting back to the sidewalk, stepping to the kerb).
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _path_t := 0.0
var _land_edge := -1
var _land_t := 0.0
var _speed_now := 0.0
var _timer := 0.0
var _patience := 0.0
var _careless := false
var _knock_vel := Vector3.ZERO
var _yaw := 0.0
var _bubble: Label3D
var _bubble_time := 0.0
var _badge: Node3D
var _waiting_time := 0.0
var _blocked_time := 0.0
var _call_timer := 0.0


func setup(manager: Node, network, variant: int, seed_value: int) -> void:
	_manager = manager
	_network = network
	_rng.seed = seed_value
	walk_speed = _rng.randf_range(1.1, 1.6)
	model = PersonModel.new()
	model.variant = variant
	add_child(model)
	obstacle = {"node": self, "ai": false, "ped": true, "half": Vector3(0.3, 0.9, 0.3),
		"radius": 0.4, "pos": Vector3.ZERO, "inv": Transform3D(), "speed": 0.0}
	_make_bubble()
	_make_badge()
	set_process(false)  # only runs while a speech bubble is up


func _make_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.name = "Speech"
	if ResourceLoader.exists(FONT_PATH):
		_bubble.font = load(FONT_PATH)
	_bubble.font_size = 40
	_bubble.pixel_size = 0.008
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.modulate = Color(1, 1, 1)
	_bubble.outline_size = 12
	_bubble.outline_modulate = Color(0.1, 0.05, 0.1)
	_bubble.position = Vector3(0, 2.15, 0)
	_bubble.visible = false
	_bubble.visibility_range_end = 40.0


func _make_badge() -> void:
	# Floating "যাত্রী" (passenger) badge above someone waiting for a rickshaw.
	_badge = Node3D.new()
	_badge.name = "PassengerBadge"
	_badge.position = Vector3(0, 2.35, 0)
	_show(_badge, false)
	var label := Label3D.new()
	if ResourceLoader.exists(FONT_PATH):
		label.font = load(FONT_PATH)
	label.text = "যাত্রী"
	label.font_size = 44
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.45, 1.0, 0.35)
	label.outline_size = 14
	label.outline_modulate = Color(0.05, 0.2, 0.05)
	label.visibility_range_end = 90.0
	_badge.add_child(label)
	# A green cone pointing down at them (a mesh: web builds have no
	# system fonts to draw a ▼ with).
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.14
	mesh.bottom_radius = 0.0
	mesh.height = 0.24
	mesh.radial_segments = 8
	mesh.rings = 1
	cone.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 1.0, 0.35)
	mat.no_depth_test = true
	cone.material_override = mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position = Vector3(0, -0.32, 0)
	cone.visibility_range_end = 90.0
	_badge.add_child(cone)


## Labels are only in the scene while shown: hidden ones would still be
## updated every physics tick as the person walks.
func _show(n: Node3D, on: bool) -> void:
	n.visible = on
	if on and n.get_parent() == null:
		add_child(n)
		n.reset_physics_interpolation()
	elif not on and n.get_parent() == self:
		remove_child(n)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n: Node in [_bubble, _badge]:
			if n and n.get_parent() == null:
				n.free()


## Shows a short Bangla speech bubble.
func say(text: String, seconds := 2.5) -> void:
	_bubble.text = text
	_show(_bubble, true)
	set_process(true)
	_bubble_time = seconds


func place_on_edge(edge: int, t: float, dir := 1) -> void:
	_edge = edge
	_t = t
	_dir = dir
	state = State.WALKING
	on_road = false
	_set_position(_network.point_on(edge, t))
	model.set_pose(PersonModel.Pose.WALK)


func current_edge() -> int:
	return _edge


func is_free_walker() -> bool:
	return state == State.WALKING and not targeted


## Called by the manager. `dt` may be several frames' worth for far pedestrians.
func step(dt: float) -> void:
	match state:
		State.WALKING:
			_walk(dt)
		State.WAIT_CROSS:
			_wait_cross(dt)
		State.CROSSING, State.RECOVERING:
			_follow_path(dt)
		State.WAITING_FOR_PICKUP:
			_wait_for_rickshaw(dt)
		State.KNOCKED:
			_knocked(dt)
	_update_obstacle()


# Speech bubbles time out on their own (also while riding as a passenger).
func _process(delta: float) -> void:
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_show(_bubble, false)
			set_process(false)


func _set_position(p: Vector3) -> void:
	p.y = PedestrianNetwork.ground_y(p.x, p.z)
	global_position = p


func _face(dir: Vector3, dt: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var wanted := atan2(-dir.x, -dir.z)
	_yaw = lerp_angle(_yaw, wanted, 1.0 - exp(-10.0 * dt)) if dt > 0.0 else wanted
	rotation = Vector3(0, _yaw, 0)


# --- Walking the sidewalk ------------------------------------------------------------

func _walk(dt: float) -> void:
	if _edge < 0:
		return  # not placed on a footpath (should not happen)
	var e: Dictionary = _network.edges[_edge]
	_speed_now = walk_speed
	_t += _dir * walk_speed * dt
	var dir_vec: Vector3 = ((e.pb as Vector3) - e.pa).normalized() * _dir
	if _t >= e.length or _t <= 0.0:
		_t = clampf(_t, 0.0, e.length)
		_arrive_at_node(e.b if _dir > 0 else e.a)
		return
	_set_position(_network.point_on(_edge, _t))
	_face(dir_vec, dt)
	model.speed = walk_speed
	# Now and then, cross the road right here instead of at the junction.
	if not e.cross and (e.inward as Vector3) != Vector3.ZERO and allow_crossing and _rng.randf() < 0.012 * dt:
		var opp: Array = _network.opposite_point(global_position, e.inward)
		if not opp.is_empty() and not _manager.crossing_danger(global_position, _network.point_on(opp[0], opp[1])):
			_begin_crossing(global_position, _network.point_on(opp[0], opp[1]), opp[0], opp[1], true)


func _arrive_at_node(node: int) -> void:
	var options: Array = _network.node_edges[node]
	var choices: Array[int] = []
	for id in options:
		if id != _edge:
			choices.append(id)
	var next: int = _edge if choices.is_empty() else choices[_rng.randi() % choices.size()]
	var ne: Dictionary = _network.edges[next]
	var forward: bool = ne.a == node
	if ne.cross:
		var to: Vector3 = ne.pb if forward else ne.pa
		var land_t: float = ne.length if forward else 0.0
		# After crossing we keep walking from the far node.
		_begin_crossing(_network.node_pos[node], to, next, land_t, false)
		return
	_edge = next
	_dir = 1 if forward else -1
	_t = 0.0 if forward else ne.length


## Starts the look-then-cross routine towards `to`.
func _begin_crossing(from: Vector3, to: Vector3, land_edge: int, land_t: float, sudden: bool) -> void:
	_from = from
	_to = to
	_path_t = 0.0
	_land_edge = land_edge
	_land_t = land_t
	_careless = sudden or _rng.randf() < 0.1
	_timer = _rng.randf_range(0.4, 1.8) if not _careless else 0.0
	_patience = _rng.randf_range(CROSS_PATIENCE.x, CROSS_PATIENCE.y)
	state = State.WAIT_CROSS
	model.set_pose(PersonModel.Pose.STAND)
	_face(to - from, 0.0)


func _wait_cross(dt: float) -> void:
	_timer -= dt
	_patience -= dt
	_speed_now = 0.0
	if _timer > 0.0:
		return
	# Careful people wait for a proper gap (until they lose patience);
	# careless ones only check that nothing is right on top of them.
	if _careless or _patience <= 0.0:
		if _manager.crossing_danger(_from, _to, 1.5):
			return
	elif _manager.crossing_danger(_from, _to):
		return
	state = State.CROSSING
	model.set_pose(PersonModel.Pose.WALK)


## Walks a straight free path (crossing the road or getting back to the sidewalk).
func _follow_path(dt: float) -> void:
	var length := _from.distance_to(_to)
	var spd := walk_speed
	var dir := (_to - _from).normalized()
	if on_road or state == State.CROSSING:
		var blocked: bool = _manager.path_blocked(global_position, dir)
		# Something standing still in the way (the player's parked rickshaw):
		# after a few seconds, squeeze past it instead of waiting forever.
		_blocked_time = _blocked_time + dt if blocked and not _manager.blocker_moving else 0.0
		if blocked and _blocked_time < 4.0:
			spd = 0.0  # a vehicle is passing right in front: wait, don't walk into it
		elif not blocked and _manager.vehicle_close(global_position, 7.0):
			spd = 3.0  # something is coming at me: hurry
	_speed_now = spd
	_path_t += spd * dt
	var f := clampf(_path_t / maxf(length, 0.001), 0.0, 1.0)
	_set_position(_from.lerp(_to, f))
	on_road = PedestrianNetwork.ground_y(global_position.x, global_position.z) < 0.01
	_face(_to - _from, dt)
	model.speed = spd
	if f >= 1.0:
		on_road = false
		_land()


func _land() -> void:
	if _land_edge < 0:
		var hit: Array = _network.nearest_walk_point(global_position)
		_land_edge = hit[0]
		_land_t = hit[1]
	var e: Dictionary = _network.edges[_land_edge]
	if e.cross:
		# Landed at the end of a crossing edge: continue from that node.
		_edge = _land_edge
		_arrive_at_node(e.b if _land_t >= e.length * 0.5 else e.a)
		if state == State.WAIT_CROSS:
			return
	else:
		_edge = _land_edge
		_t = _land_t
		_dir = 1 if _rng.randf() < 0.5 else -1
	state = State.WALKING
	model.set_pose(PersonModel.Pose.WALK)


# --- Passenger -------------------------------------------------------------------------

## Stops walking, steps to the kerb and waves for a rickshaw.
func become_waiting_passenger() -> bool:
	if state != State.WALKING or _edge < 0:
		return false
	var e: Dictionary = _network.edges[_edge]
	if e.cross or (e.inward as Vector3) == Vector3.ZERO:
		return false
	state = State.WAITING_FOR_PICKUP
	var kerb_spot := global_position - (e.inward as Vector3) * 0.55
	if _manager.is_spot_free(kerb_spot):
		_set_position(kerb_spot)
	_face(-(e.inward as Vector3), 0.0)
	model.set_pose(PersonModel.Pose.STAND)
	_show(_badge, true)
	_waiting_time = 0.0
	_call_timer = _rng.randf_range(1.0, 4.0)
	return true


## Gives up waiting (or was picked up): back to normal life.
func stop_waiting() -> void:
	_show(_badge, false)
	if state == State.WAITING_FOR_PICKUP:
		var hit: Array = _network.nearest_walk_point(global_position)
		place_on_edge(hit[0], hit[1], 1 if _rng.randf() < 0.5 else -1)


func waiting_time() -> float:
	return _waiting_time


func _wait_for_rickshaw(dt: float) -> void:
	_waiting_time += dt
	_speed_now = 0.0
	var near: bool = _manager.distance_to_player(global_position) < 30.0
	model.set_pose(PersonModel.Pose.WAVE if near else PersonModel.Pose.STAND)
	_call_timer -= dt
	if near and _call_timer <= 0.0:
		_call_timer = _rng.randf_range(4.0, 8.0)
		say(CALLS[_rng.randi() % CALLS.size()], 2.0)
	_badge.position.y = 2.35 + sin(_waiting_time * 3.0) * 0.08


## Called by the passenger manager when the trip is accepted.
func accept_ride() -> void:
	_show(_badge, false)
	state = State.ACCEPTED
	model.set_pose(PersonModel.Pose.WALK)
	model.speed = 1.5


func sit_down() -> void:
	state = State.ON_BOARD
	on_road = false
	model.set_pose(PersonModel.Pose.SIT)


## Back on the sidewalk after a trip (or a cancelled one).
func finish_trip(text := "") -> void:
	var hit: Array = _network.nearest_walk_point(global_position)
	place_on_edge(hit[0], hit[1], 1 if _rng.randf() < 0.5 else -1)
	if text != "":
		say(text, 3.0)


# --- Getting hit -----------------------------------------------------------------------

func can_be_hit() -> bool:
	return state in [State.WALKING, State.WAIT_CROSS, State.CROSSING, State.WAITING_FOR_PICKUP, State.RECOVERING]


## Arcade knock-down: flies back a little, lies dazed, then gets up.
func knock(from: Vector3, impact: float, by_player: bool) -> void:
	if state == State.WAITING_FOR_PICKUP:
		_show(_badge, false)
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	away = away.normalized()
	_knock_vel = away * clampf(impact * 0.7, 1.5, 6.0) + Vector3.UP * clampf(impact * 0.5, 1.5, 4.0)
	_face(-away, 0.0)  # facing the vehicle, falling backwards
	state = State.KNOCKED
	_timer = KNOCK_DOWN_TIME + clampf(impact * 0.2, 0.0, 2.0)
	model.set_pose(PersonModel.Pose.FALLEN)
	if by_player:
		say(random_hit_shout(_rng), 3.0)


func _knocked(dt: float) -> void:
	_timer -= dt
	_speed_now = 0.0
	var p := global_position
	if _knock_vel.length_squared() > 0.0001:
		var next := p + _knock_vel * dt
		if not _manager.is_clear_line(p, next):
			# Stopped by a wall: drop straight down.
			_knock_vel.x = 0.0
			_knock_vel.z = 0.0
			next = Vector3(p.x, next.y, p.z)
		_knock_vel.y -= 14.0 * dt
		var g := PedestrianNetwork.ground_y(next.x, next.z)
		if next.y <= g:
			next.y = g
			_knock_vel = Vector3(_knock_vel.x * 0.5, 0.0, _knock_vel.z * 0.5)
			if Vector2(_knock_vel.x, _knock_vel.z).length() < 0.3:
				_knock_vel = Vector3.ZERO
		global_position = next
	on_road = PedestrianNetwork.ground_y(global_position.x, global_position.z) < 0.01
	if _timer <= 0.0:
		walk_back_to_footpath()  # get up and walk back to the nearest sidewalk


## Walks from wherever this person is to the nearest footpath, then on as usual.
## With `away_from`, prefers the footpath on the far side from that point
## (e.g. not past the rickshaw they were just shouting at).
func walk_back_to_footpath(away_from := Vector3.INF) -> void:
	var probe := global_position
	if away_from != Vector3.INF:
		var away := global_position - away_from
		away.y = 0.0
		probe += away.normalized() * 4.0
	var hit: Array = _network.nearest_walk_point(probe)
	_from = global_position
	_to = _network.point_on(hit[0], hit[1])
	_path_t = 0.0
	_land_edge = hit[0]
	_land_t = hit[1]
	state = State.RECOVERING
	model.set_pose(PersonModel.Pose.WALK)


func _update_obstacle() -> void:
	obstacle.pos = global_position
	obstacle.inv = global_transform.affine_inverse()
	obstacle.speed = _speed_now

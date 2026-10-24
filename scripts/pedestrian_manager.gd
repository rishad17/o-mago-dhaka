## Spawns and updates pedestrians, and handles them getting hit.
##
## Pedestrians are not solid physics bodies (the rickshaw would stop dead
## against them like a wall). Instead this manager checks for overlaps with
## the player and with traffic and triggers an arcade knock-down. Nearby
## pedestrians are simulated every tick, distant ones less often, and
## pedestrians far from the player are moved closer (out of sight) to keep
## the sidewalks busy.
extends Node3D

const PedestrianNetwork := preload("res://scripts/pedestrian_network.gd")
const PedestrianScene := preload("res://scenes/pedestrians/pedestrian.tscn")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const HIT_SOUND := "res://assets/audio/boing.wav"
const PLAYER_HALF := Vector3(0.65, 0.95, 1.2)
const PLAYER_CENTER_Z := -0.24
const PED_RADIUS := 0.3
## Pedestrians closer than this get the full jointed model (7 draw calls
## each); phones keep it for the nearest few only.
var detail_distance := 14.0
## Above this speed (m/s) hitting someone counts as an accident.
const ACCIDENT_SPEED := 2.0

## Emitted when the player's rickshaw knocks someone over.
signal pedestrian_hit_by_player(ped: Node3D, speed: float, counts_as_accident: bool)

@export var player_path: NodePath
@export var camera_path: NodePath
@export var traffic_path: NodePath
@export var count := 130
@export var ped_seed := 777
## Keep at least this many pedestrians within 60 m of the player.
@export var nearby_target := 65

var network: PedestrianNetwork
var pedestrians: Array[Node3D] = []
## Pedestrians currently on the road, as obstacle records for traffic.
var road_obstacles: Array[Dictionary] = []
var hits_by_player := 0
var hits_by_traffic := 0
## Set by path_blocked(): whether what is in the way is moving.
var blocker_moving := false
var recycled_count := 0

var _player: Node3D
var _camera: Camera3D
var _traffic: Node
var _rng := RandomNumberGenerator.new()
var _tick := 0
var _manage_timer := 0.0
var _hit_sound: AudioStreamPlayer
var _walk_edges: Array[int] = []
var _movers_cache := []
var _movers_frame := -1


func _ready() -> void:
	_rng.seed = ped_seed
	# Fewer people overall (light traffic, phones) means fewer around you too.
	nearby_target = roundi(nearby_target * Settings.density_factor())
	if Settings.touch_mode:
		detail_distance = 9.0
	network = PedestrianNetwork.new()
	_player = get_node_or_null(player_path)
	_camera = get_node_or_null(camera_path)
	_traffic = get_node_or_null(traffic_path)
	for id in network.edges.size():
		if not network.edges[id].cross and network.edges[id].length > 4.0:
			_walk_edges.append(id)
	var total := roundi(count * Settings.density_factor())
	for i in total:
		var ped: Node3D = PedestrianScene.instantiate()
		add_child(ped)
		ped.setup(self, network, _rng.randi() % 16, ped_seed + i * 131)
		ped.name = "Pedestrian%d" % i
		# The first few start right around the player, so the street is busy at once.
		if i < nearby_target:
			if not _place_randomly(ped, 6.0, 55.0, false):
				_place_randomly(ped, 0.0, 1e9, false)  # never leave anyone unplaced
		else:
			_place_randomly(ped, 0.0, 1e9, false)
		pedestrians.append(ped)
	_hit_sound = AudioStreamPlayer.new()
	if ResourceLoader.exists(HIT_SOUND):
		_hit_sound.stream = load(HIT_SOUND)
	_hit_sound.volume_db = -3.0
	_hit_sound.bus = "SFX"
	add_child(_hit_sound)
	Settings.log_time("pedestrian_manager ready")
	if _player and _player.has_signal("horn_pressed"):
		_player.horn_pressed.connect(_on_player_horn)


func _place_randomly(ped: Node3D, min_d: float, max_d: float, hidden: bool) -> bool:
	# Spots near the player are rare on the big map, so try plenty of times.
	for attempt in (400 if max_d < 1e8 else 60):
		var e: int = _walk_edges[_rng.randi() % _walk_edges.size()]
		var t := _rng.randf_range(1.0, network.edges[e].length - 1.0)
		var p: Vector3 = network.point_on(e, t)
		var d := distance_to_player(p)
		if d < min_d or d > max_d:
			continue
		if hidden and _camera and _camera.is_position_in_frustum(p + Vector3.UP):
			continue
		ped.place_on_edge(e, t, 1 if _rng.randf() < 0.5 else -1)
		return true
	return false


func distance_to_player(p: Vector3) -> float:
	if _player == null:
		return 1e9
	return Vector2(p.x - _player.global_position.x, p.z - _player.global_position.z).length()


func _physics_process(delta: float) -> void:
	_tick += 1
	road_obstacles.clear()
	for i in pedestrians.size():
		var ped = pedestrians[i]
		if ped.state in [Pedestrian.State.ACCEPTED, Pedestrian.State.ON_BOARD, Pedestrian.State.EXITING, Pedestrian.State.VICTIM]:
			# The passenger, mugging or mob manager is in charge; traffic
			# still has to see someone (e.g. an angry crowd) on the road.
			if ped.on_road:
				road_obstacles.append(ped.obstacle)
			continue
		var d := distance_to_player(ped.global_position)
		# Crossing the road is the moment that matters: always every tick.
		var crossing: bool = ped.on_road or ped.state == Pedestrian.State.WAIT_CROSS
		if d < 30.0 or (crossing and d < 70.0):
			ped.step(delta)
		elif d < 70.0:
			if (_tick + i) % 2 == 0:
				ped.step(delta * 2.0)
		elif (_tick + i) % 4 == 0:
			ped.step(delta * 4.0)
		# Jointed, fully animated body only up close (it takes 7 draw calls);
		# further out a one-mesh flip-book walk, and beyond 45 m a still one.
		ped.model.animate = d < 45.0
		var waving: bool = ped.state == Pedestrian.State.WAITING_FOR_PICKUP and d < 30.0
		ped.model.set_far(d > detail_distance and ped.state != Pedestrian.State.KNOCKED and not waving)
		if ped.on_road:
			road_obstacles.append(ped.obstacle)
	_check_player_hits()
	_check_traffic_hits()
	_manage_timer -= delta
	if _manage_timer <= 0.0:
		_manage_timer = 2.0
		_keep_sidewalks_busy()


# --- Collisions ------------------------------------------------------------------------

func _check_player_hits() -> void:
	if _player == null:
		return
	var pxf := _player.global_transform.translated_local(Vector3(0, 0, PLAYER_CENTER_Z))
	var inv := pxf.affine_inverse()
	var spd := absf(_player.speed)
	if spd < 0.6:
		return  # creeping along: people just step around
	for ped in pedestrians:
		if not ped.can_be_hit():
			continue
		if ped.global_position.distance_squared_to(pxf.origin) > 9.0:
			continue
		var local: Vector3 = inv * ped.global_position
		if absf(local.x) < PLAYER_HALF.x + PED_RADIUS and absf(local.z) < PLAYER_HALF.z + PED_RADIUS:
			ped.knock(pxf.origin, spd, true)
			hits_by_player += 1
			if _hit_sound.stream:
				_hit_sound.pitch_scale = _rng.randf_range(0.9, 1.15)
				_hit_sound.play()
			pedestrian_hit_by_player.emit(ped, spd, spd >= ACCIDENT_SPEED)


func _check_traffic_hits() -> void:
	if _traffic == null or road_obstacles.is_empty():
		return
	for o in road_obstacles:
		var ped: Node3D = o.node
		if not ped.can_be_hit():
			continue
		for m in _movers():
			var v = m[3]
			if v == null or m[2] < 1.0 or (m[0] as Vector3).distance_squared_to(ped.global_position) > 36.0:
				continue
			var local: Vector3 = (m[4] as Transform3D) * ped.global_position
			if absf(local.x) < v.half.x + PED_RADIUS and absf(local.z) < v.half.z + PED_RADIUS:
				if OS.has_feature("debug") and OS.get_cmdline_user_args().has("--debug-hits"):
					print("  diag  %s hit %s (%s, careless %s): veh speed %.1f lat %.2f turn %s ignore_ai %s gap_v %.1f blocker %s local %s" % [
						v.name, ped.name, Pedestrian.State.keys()[ped.state], ped._careless, v.speed, v.lat,
						v._pieces[0].is_turn(), v._controller.time < v._ignore_ai_until, v._gap_speed,
						str(v._blocker.node.name) if not v._blocker.is_empty() else "-", local])
				ped.knock(v.get_center(), v.speed, false)
				v.on_pedestrian_hit()
				hits_by_traffic += 1
				break


# --- Questions pedestrians ask -------------------------------------------------------

## Vehicles (and the player): [position, forward, speed, vehicle or null,
## inverse of the body-centred transform, half size]. Built once per physics
## tick and shared by every pedestrian's questions.
func _movers() -> Array:
	var frame := Engine.get_physics_frames()
	if frame == _movers_frame:
		return _movers_cache
	_movers_frame = frame
	_movers_cache = []
	if _traffic:
		for v in _traffic.vehicles:
			var xf: Transform3D = v.global_transform.translated_local(Vector3(0, 0, v.center_z))
			_movers_cache.append([xf.origin, -xf.basis.z, v.speed, v, xf.affine_inverse(), v.half])
	if _player:
		var pxf := _player.global_transform.translated_local(Vector3(0, 0, PLAYER_CENTER_Z))
		_movers_cache.append([_player.global_position, -pxf.basis.z, _player.speed, null, pxf.affine_inverse(), PLAYER_HALF])
	return _movers_cache


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var f := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * f).length()


## Is a vehicle on, or due within `horizon` seconds at, the crossing from `a` to `b`?
func crossing_danger(a: Vector3, b: Vector3, horizon := 3.5) -> bool:
	for m in _movers():
		var p: Vector3 = m[0]
		if Vector2(p.x - a.x, p.z - a.z).length() > 45.0:
			continue
		if _dist_to_segment(p, a, b) < 3.0:
			return true
		var spd: float = m[2]
		if spd < 0.5:
			continue
		for k in range(1, int(horizon / 0.5) + 1):
			# Traffic: predict along its planned route (so turns are seen);
			# the player: straight ahead.
			var ahead: float = spd * k * 0.5
			var q: Vector3 = m[3].predict_position(ahead) if m[3] else p + (m[1] as Vector3) * ahead
			if _dist_to_segment(q, a, b) < 2.5:
				return true
	return false


## True if a vehicle (or the player's rickshaw) is right in front of a
## pedestrian walking in direction `dir`, so they should stop, not walk into it.
func path_blocked(pos: Vector3, dir: Vector3) -> bool:
	for m in _movers():
		# Only wait for vehicles that are moving: a stopped one is waiting
		# for us, so walk on (otherwise both wait forever). The player's
		# rickshaw always counts.
		if (m[3] != null and m[2] < 0.5) or (m[0] as Vector3).distance_squared_to(pos) > 64.0:
			continue
		var inv: Transform3D = m[4]
		var h: Vector3 = m[5]
		# Traffic: also keep out of the strip it will cover in the next
		# moment (unless already standing in it: then better keep going).
		var sweep: float = h.z + 0.45 + (m[2] * 0.6 if m[3] != null else 0.0)
		var here: Vector3 = inv * pos
		var in_path_now := absf(here.x) < h.x + 0.45 and here.z < h.z + 0.45 and here.z > -sweep
		for d: float in [0.5, 1.1]:
			var local: Vector3 = inv * (pos + dir * d)
			if absf(local.x) >= h.x + 0.45 or local.z >= h.z + 0.45:
				continue
			if local.z > -(h.z + 0.45) or (local.z > -sweep and not in_path_now):
				blocker_moving = absf(m[2]) >= 0.5
				return true
	return false


## Is something moving towards `pos` within `radius` metres?
func vehicle_close(pos: Vector3, radius: float) -> bool:
	for m in _movers():
		var p: Vector3 = m[0]
		var to := pos - p
		to.y = 0.0
		if to.length() < radius and m[2] > 1.0 and to.dot(m[1]) > 0.0:
			return true
	return false


## True if a person could stand at `p` without being inside a pole or tree.
func is_spot_free(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.35
	q.shape = s
	q.transform = Transform3D(Basis(), p + Vector3(0, 1.0, 0))
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## True if nothing solid (walls, buildings) lies between a and b at chest height.
func is_clear_line(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.8, 0), b + Vector3(0, 0.8, 0), 1)
	return space.intersect_ray(q).is_empty()


func _on_player_horn() -> void:
	for ped in pedestrians:
		if ped.state == Pedestrian.State.WALKING and distance_to_player(ped.global_position) < 10.0 and _rng.randf() < 0.3:
			ped.say(["যাচ্ছি তো!", "কি হলো ভাই?", "এত হর্ন কেন?"][_rng.randi() % 3], 2.0)


## Moves far-away pedestrians closer (out of sight) so the player's area stays lively.
## Puts a pedestrian 20-65 m from the player, preferably ahead, where they
## won't be seen appearing: out of view, or far enough away not to notice.
func _place_near_player(ped: Node3D) -> bool:
	var fwd := Vector3.FORWARD
	if _camera:
		fwd = -_camera.global_transform.basis.z
	for attempt in 400:
		var e: int = _walk_edges[_rng.randi() % _walk_edges.size()]
		var t := _rng.randf_range(1.0, network.edges[e].length - 1.0)
		var p: Vector3 = network.point_on(e, t)
		var d := distance_to_player(p)
		if d < 20.0 or d > 65.0:
			continue
		if attempt < 250 and (p - _player.global_position).dot(fwd) < 0.0:
			continue  # first try spots ahead of the player
		var seen: bool = _camera != null and _camera.is_position_in_frustum(p + Vector3.UP)
		if seen and d < 50.0:
			continue
		ped.place_on_edge(e, t, 1 if _rng.randf() < 0.5 else -1)
		return true
	return false


func _keep_sidewalks_busy() -> void:
	if _player == null:
		return
	var near := 0
	var far: Array[Node3D] = []
	for ped in pedestrians:
		var d := distance_to_player(ped.global_position)
		if d < 60.0:
			near += 1
		elif d > 100.0 and ped.state == Pedestrian.State.WALKING \
				and (_camera == null or not _camera.is_position_in_frustum(ped.global_position + Vector3.UP)):
			far.append(ped)
	var moves := mini(nearby_target - near, 8)
	for i in moves:
		if far.is_empty():
			break
		var ped: Node3D = far.pop_at(_rng.randi() % far.size())
		if _place_near_player(ped):
			recycled_count += 1


func count_in_state(state: int) -> int:
	var n := 0
	for ped in pedestrians:
		if ped.state == state:
			n += 1
	return n

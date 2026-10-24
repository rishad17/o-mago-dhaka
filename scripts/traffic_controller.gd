## Spawns and manages Dhaka traffic.
##
## Keeps the shared list of obstacles (all vehicles plus the player) that
## vehicles look at, limits how many horns sound at once, plays the street
## ambience, and recycles vehicles: ones stuck for too long are moved out of
## sight, and distant ones are brought closer to keep the player's streets busy.
extends Node3D

const TrafficNetwork := preload("res://scripts/traffic_network.gd")
const VehicleScene := preload("res://scenes/vehicles/traffic_vehicle.tscn")
const VehicleModels := preload("res://scripts/vehicle_models.gd")
const CityLayout := preload("res://scripts/city_layout.gd")
const AMBIENCE := "res://assets/audio/traffic_ambience_loop.wav"
const PLAYER_HALF := Vector3(0.65, 0.95, 1.2)
const PLAYER_CENTER_Z := -0.24

@export var player_path: NodePath
@export var camera_path: NodePath
## Pedestrians crossing the road are obstacles too.
@export var pedestrians_path: NodePath
## How many of each vehicle type to spawn.
@export var counts := {"bus": 9, "cng": 18, "car": 9, "microbus": 4, "motorcycle": 12, "rickshaw": 16}
@export var traffic_seed := 2024
## Keep at least this many vehicles within 70 m of the player.
@export var nearby_target := 24

var network: TrafficNetwork
var vehicles: Array[Node] = []
## Shared obstacle records: {node, pos, inv, half, radius, ai, speed}.
var obstacles: Array[Dictionary] = []
var bus_stops: Array[Vector3] = []
var time := 0.0
var horn_count := 0
var recycled_count := 0
## Times AI vehicles bumped into each other while pushing through a jam.
var ai_bumps := 0

var _player: Node3D
var _camera: Camera3D
var _player_obstacle := {}
var _pedestrians: Node
var _base_obstacles := 0
var _rng := RandomNumberGenerator.new()
var _horn_times: Array[float] = []
var _manage_timer := 0.0
var _bump_cooldown := {}
var _bump_sound: AudioStreamPlayer3D


func _ready() -> void:
	_rng.seed = traffic_seed
	# Light traffic keeps fewer vehicles around the player too.
	nearby_target = roundi(nearby_target * Settings.density_factor())
	network = TrafficNetwork.new()
	_player = get_node_or_null(player_path)
	_camera = get_node_or_null(camera_path)
	_pedestrians = get_node_or_null(pedestrians_path)
	for d in CityLayout.destinations():
		if "বাসস্ট্যান্ড" in d.name:
			bus_stops.append(d.position)
	var vid := 0
	for type in counts:
		# Light / normal / heavy traffic setting.
		var n := maxi(1, roundi(int(counts[type]) * Settings.density_factor()))
		for i in n:
			var v := VehicleScene.instantiate()
			add_child(v)
			v.setup(type, _rng.randi() % VehicleModels.variant_count(type) if type != "rickshaw" else _rng.randi() % 4,
				self, network, vid, traffic_seed + vid * 7919)
			vehicles.append(v)
			vid += 1
	# A shuffled order, so the vehicles near the player are a good mix.
	var order := range(vehicles.size())
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in order.size():
		var v = vehicles[order[i]]
		# The first few start near the player, so the roads are busy at once.
		if i < nearby_target:
			if not _place_somewhere(v, 15.0, false, 80.0):
				_place_somewhere(v, 18.0, false)
		else:
			_place_somewhere(v, 18.0, false)
	Settings.log_time("traffic_controller ready")
	_refresh_obstacles()
	_start_ambience()
	_bump_sound = AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://assets/audio/clang.wav"):
		_bump_sound.stream = load("res://assets/audio/clang.wav")
	_bump_sound.bus = "Traffic"
	_bump_sound.max_distance = 45.0
	_bump_sound.unit_size = 6.0
	add_child(_bump_sound)


func _start_ambience() -> void:
	if not ResourceLoader.exists(AMBIENCE):
		return
	var stream: AudioStream = load(AMBIENCE)
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	var amb := AudioStreamPlayer.new()
	amb.name = "Ambience"
	amb.stream = stream
	amb.volume_db = -17.0
	amb.bus = "Ambience"
	add_child(amb)
	amb.play()


func _physics_process(delta: float) -> void:
	time += delta
	_refresh_obstacles()
	_check_ai_bumps()
	_manage_timer -= delta
	if _manage_timer <= 0.0:
		_manage_timer = 1.0
		_manage()


## Vehicles pushing through a deadlock may nudge another one: make that a
## small, visible and audible bump instead of a silent overlap.
func _check_ai_bumps() -> void:
	for v in vehicles:
		if not v.is_pushing_through() or v.speed < 0.5:
			continue
		for o in vehicles:
			if o == v or o.global_position.distance_squared_to(v.global_position) > 64.0:
				continue
			var local: Vector3 = o.global_transform.translated_local(Vector3(0, 0, o.center_z)).affine_inverse() * v.get_center()
			if absf(local.x) < o.half.x + v.half.x * 0.8 and absf(local.z) < o.half.z + v.half.z * 0.8:
				var key := mini(v.id, o.id) * 1000 + maxi(v.id, o.id)
				if time < _bump_cooldown.get(key, 0.0):
					continue
				_bump_cooldown[key] = time + 4.0
				ai_bumps += 1
				v.bump_reaction(false)
				o.bump_reaction(true)
				if _bump_sound.stream and distance_to_player(v.global_position) < 45.0:
					_bump_sound.global_position = (v.global_position + o.global_position) * 0.5
					_bump_sound.pitch_scale = randf_range(0.9, 1.1)
					_bump_sound.play()


func player_position() -> Vector3:
	return _player.global_position if _player else Vector3(9999, 0, 9999)


func player_speed() -> float:
	return absf(_player.speed) if _player and "speed" in _player else 0.0


func distance_to_player(pos: Vector3) -> float:
	return pos.distance_to(player_position())


## Global horn limiter so the soundscape stays chaotic but bearable.
func request_horn() -> bool:
	while not _horn_times.is_empty() and time - _horn_times[0] > 1.2:
		_horn_times.pop_front()
	if _horn_times.size() >= 3:
		return false
	_horn_times.append(time)
	horn_count += 1
	return true


func _refresh_obstacles() -> void:
	if _base_obstacles == 0:
		obstacles.clear()
		for v in vehicles:
			obstacles.append({"node": v, "ai": true, "half": v.half,
				"radius": maxf(v.half.x, v.half.z), "pos": Vector3.ZERO, "inv": Transform3D(), "speed": 0.0})
		if _player:
			_player_obstacle = {"node": _player, "ai": false, "half": PLAYER_HALF,
				"radius": PLAYER_HALF.z, "pos": Vector3.ZERO, "inv": Transform3D(), "speed": 0.0}
			obstacles.append(_player_obstacle)
		_base_obstacles = obstacles.size()
	obstacles.resize(_base_obstacles)
	for i in vehicles.size():
		var v = vehicles[i]
		var o: Dictionary = obstacles[i]
		var xf: Transform3D = v.global_transform.translated_local(Vector3(0, 0, v.center_z))
		o.pos = xf.origin
		o.inv = xf.affine_inverse()
		o.speed = v.speed
	if _player:
		var pxf := _player.global_transform.translated_local(Vector3(0, 0, PLAYER_CENTER_Z))
		_player_obstacle.pos = pxf.origin
		_player_obstacle.inv = pxf.affine_inverse()
		_player_obstacle.speed = player_speed()
	if _pedestrians:
		obstacles.append_array(_pedestrians.road_obstacles)


## Finds a free spot on a lane and puts the vehicle there.
## `hidden` = the spot must be out of the camera's view (for recycling).
func _place_somewhere(v: Node, min_player_dist: float, hidden: bool, max_player_dist := 1e9) -> bool:
	for attempt in (300 if max_player_dist < 1e8 else 80):
		var spot := network.random_spot(_rng, 5.0)
		var piece = network.edge_piece(spot[0])
		var pos: Vector3 = piece.position_at(spot[1])
		var pd := distance_to_player(pos)
		if pd < min_player_dist or pd > max_player_dist:
			continue
		if hidden and _camera and _camera.is_position_in_frustum(pos + Vector3.UP):
			continue
		var free := true
		for other in vehicles:
			if other != v and other.current_edge >= 0 and other.global_position.distance_to(pos) < 12.0:
				free = false
				break
		# Never drop a vehicle right next to someone crossing the road.
		if free and _pedestrians:
			for o in _pedestrians.road_obstacles:
				if (o.pos as Vector3).distance_to(pos) < 12.0:
					free = false
					break
		if not free:
			continue
		v.place(spot[0], spot[1])
		return true
	return false


func _is_hidden(v: Node) -> bool:
	if v.dist_to_player < 30.0:
		return false
	return _camera == null or not _camera.is_position_in_frustum(v.global_position + Vector3.UP)


## Once a second: recycle stuck vehicles and keep traffic near the player.
func _manage() -> void:
	for v in vehicles:
		if v.stuck_time > 20.0 and _is_hidden(v):
			if _place_somewhere(v, 30.0, true):
				recycled_count += 1
	if _player == null:
		return
	var near := 0
	var far: Array[Node] = []
	for v in vehicles:
		if v.dist_to_player < 70.0:
			near += 1
		elif v.dist_to_player > 110.0 and _is_hidden(v):
			far.append(v)
	# Bring up to two far-away vehicles closer each second.
	for i in mini(nearby_target - near, 3):
		if far.is_empty():
			break
		var v: Node = far.pop_at(_rng.randi() % far.size())
		if _place_somewhere(v, 35.0, true, 80.0):
			recycled_count += 1


func count_by_type() -> Dictionary:
	var out := {}
	for v in vehicles:
		out[v.vehicle_type] = out.get(v.vehicle_type, 0) + 1
	return out

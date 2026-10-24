## One AI vehicle in Dhaka traffic (bus, CNG, car, microbus, motorcycle or
## pedal rickshaw).
##
## It moves kinematically along lane pieces from TrafficNetwork, so it never
## leaves the road. A few times per second it "looks" along its own future
## path for other vehicles and the player, and slows, stops, honks, pulls
## over, weaves or overtakes. A deadlock breaker makes sure jams always clear.
extends AnimatableBody3D

signal honked(vehicle: Node)

const VehicleModels := preload("res://scripts/vehicle_models.gd")
const RickshawModel := preload("res://scripts/rickshaw_model.gd")
const PersonModel := preload("res://scripts/person_model.gd")
const PedestrianNetworkGround := preload("res://scripts/pedestrian_network.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const BIKER_LINES := ["আমার বাইক!", "আরে ভাই!", "দেখে চালাতে পারেন না?", "হাত-পা ভাঙলো রে!"]
const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"
const TRAFFIC_LAYER := 4  # physics layer 3 "traffic"

## speed: top speed m/s, turn: speed through corners, impact: how hard a hit
## feels for the player, weave: how much it wanders across the lane,
## stop: chance per street of pulling over.
const TYPES := {
	"bus": {"speed": 8.5, "accel": 1.3, "decel": 4.0, "turn": 3.2, "impact": 1.6, "weave": 0.15, "stop": 0.3,
		"horn": "res://assets/audio/bus_horn.wav", "engine": "res://assets/audio/bus_engine_loop.wav"},
	"cng": {"speed": 8.0, "accel": 2.2, "decel": 5.0, "turn": 4.2, "impact": 1.0, "weave": 1.0, "stop": 0.15,
		"horn": "res://assets/audio/cng_horn.wav", "engine": "res://assets/audio/cng_engine_loop.wav"},
	"car": {"speed": 9.5, "accel": 2.5, "decel": 5.5, "turn": 4.5, "impact": 1.2, "weave": 0.25, "stop": 0.05,
		"horn": "res://assets/audio/car_horn.wav", "engine": ""},
	"microbus": {"speed": 9.0, "accel": 2.0, "decel": 5.0, "turn": 4.0, "impact": 1.3, "weave": 0.25, "stop": 0.1,
		"horn": "res://assets/audio/car_horn.wav", "engine": ""},
	"motorcycle": {"speed": 10.5, "accel": 3.5, "decel": 6.0, "turn": 5.0, "impact": 0.8, "weave": 1.4, "stop": 0.03,
		"horn": "res://assets/audio/bike_horn.wav", "engine": "res://assets/audio/cng_engine_loop.wav"},
	"rickshaw": {"speed": 4.2, "accel": 1.2, "decel": 4.0, "turn": 3.0, "impact": 0.7, "weave": 0.5, "stop": 0.2,
		"horn": "res://assets/audio/rickshaw_bell.wav", "engine": ""},
}
const RICKSHAW_PAINTS := [
	[Color(0.85, 0.12, 0.15), Color(0.1, 0.55, 0.25)], [Color(0.12, 0.35, 0.85), Color(0.95, 0.75, 0.1)],
	[Color(0.95, 0.55, 0.1), Color(0.6, 0.1, 0.5)], [Color(0.1, 0.62, 0.25), Color(0.85, 0.12, 0.15)],
]
const ANGRY_LINES := ["এই রিকশা!", "চোখে দেখো না?", "দেখে চালাও মিয়া!", "আরে আরে আরে!", "মাথা খারাপ নাকি?"]
const BUMP_LINES := ["আরে ভাই!", "ধাক্কা দিলেন কেন?", "সরেন তো!"]
const RICKSHAW_SLOGANS := ["মায়ের দোয়া", "বাবার দোয়া", "আল্লাহ ভরসা", "সোনার বাংলা", "ঢাকা শহর"]

var vehicle_type := "cng"
var id := 0
## Half extents of the collision box (used by sensing too).
var half := Vector3(0.7, 0.9, 1.4)
## Collision box centre along local Z (rickshaw model is not centred).
var center_z := 0.0
var impact_multiplier := 1.0
var speed := 0.0
var lat := 0.0
## Seconds spent stuck without meaning to be (used by the recycler).
var stuck_time := 0.0
var dist_to_player := 0.0
var current_edge := -1

var _controller: Node
var _network
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _max_speed := 8.0
var _pieces: Array = []
var _s := 0.0
var _lat_target := 0.0
var _lat_vel := 0.0
var _yaw := 0.0
var _model: Node3D
var _rickshaw: Node3D
var _horn: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
var _sense_timer := 0.0
var _far_tick := 0
## Traffic rickshaws show their full model (about 20 parts) only this close.
var _detail_distance := 16.0 if Settings.touch_mode else 28.0
var _far_dt := 0.0
var _gap_speed := 99.0
var _blocker: Dictionary = {}
var blocked_time := 0.0
var _ignore_ai_until := 0.0
var _overtake_until := 0.0
var _stop_s := -1.0
var _stop_duration := 0.0
var _stop_pull := false
var _stopped_until := 0.0
var _slow_until := 0.0
var _weave_timer := 0.0
var _cut_in_timer := 0.0
var _horn_cooldown := 0.0
var _jolt := 0.0
var _allowed_speed := 99.0
var _bubble: Label3D
var _bubble_time := 0.0
var _variant := 0
var _mesh: MeshInstance3D
## A motorcycle whose riders fell off (lying on its side for a while).
var bike_down := false
var _fallen: Array[Node3D] = []
var _bike_tween: Tween


func setup(type: String, variant: int, controller: Node, network, vehicle_id: int, seed_value: int) -> void:
	vehicle_type = type
	id = vehicle_id
	name = "%s_%d" % [type, vehicle_id]
	_controller = controller
	_network = network
	_cfg = TYPES[type]
	_rng.seed = seed_value
	_max_speed = _cfg.speed * _rng.randf_range(0.85, 1.1)
	impact_multiplier = _cfg.impact
	collision_layer = TRAFFIC_LAYER
	collision_mask = 0
	sync_to_physics = true
	_build_model(variant)
	var shape := BoxShape3D.new()
	shape.size = half * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, half.y, center_z)
	add_child(cs)
	_horn = _make_audio(_cfg.horn, 60.0, 2.0)
	if _cfg.engine != "":
		_engine = _make_audio(_cfg.engine, 30.0, -8.0)
		if _engine.stream is AudioStreamWAV:
			var wav: AudioStreamWAV = _engine.stream
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * wav.mix_rate)


func _build_model(variant: int) -> void:
	if vehicle_type == "rickshaw":
		var r := RickshawModel.new()
		var paint: Array = RICKSHAW_PAINTS[variant % RICKSHAW_PAINTS.size()]
		r.body_paint = paint[0]
		r.guard_paint = paint[1]
		r.backboard_text = RICKSHAW_SLOGANS[variant % RICKSHAW_SLOGANS.size()]
		add_child(r)
		_model = r
		_rickshaw = r
		half = Vector3(0.65, 0.95, 1.2)
		center_z = -0.24
		return
	_variant = variant
	var data := VehicleModels.build(vehicle_type, variant)
	half = data.half
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var mi := MeshInstance3D.new()
	_mesh = mi
	mi.mesh = data.mesh
	mi.visibility_range_end = 170.0
	_model.add_child(mi)
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	for spec in data.labels:
		var label := Label3D.new()
		label.text = spec.text
		label.font_size = 48
		if font:
			label.font = font
			var px := font.get_string_size(spec.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
			label.pixel_size = minf(spec.size.x / maxf(px.x, 1.0), spec.size.y / maxf(px.y, 1.0))
		label.modulate = spec.color
		label.outline_size = 0
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.visibility_range_end = 45.0
		label.transform = spec.xf
		_model.add_child(label)


func _make_audio(path: String, max_dist: float, volume: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if path != "" and ResourceLoader.exists(path):
		p.stream = load(path)
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.volume_db = volume
	p.bus = "Traffic"
	add_child(p)
	return p


## Puts the vehicle on lane `edge` at distance `s` and resets its state.
func place(edge: int, s: float) -> void:
	if bike_down:
		_remount()
	_pieces = [_network.edge_piece(edge)]
	_s = s
	current_edge = edge
	speed = 0.0
	lat = 0.0
	_lat_target = 0.0
	_stop_s = -1.0
	_stopped_until = 0.0
	_sense_timer = 0.0  # look around straight away after being placed
	stuck_time = 0.0
	blocked_time = 0.0
	_blocker = {}
	_ensure_pieces()
	var t: Vector3 = _pieces[0].tangent_at(_s)
	_yaw = atan2(-t.x, -t.z)
	# Teleport without physics sync, so the jump is not seen as a huge velocity.
	sync_to_physics = false
	_apply_pose(0.0)
	reset_physics_interpolation()
	set_deferred("sync_to_physics", true)


func get_center() -> Vector3:
	return global_transform * Vector3(0, 0, center_z)


func get_road_width() -> float:
	return _pieces[0].road_width if not _pieces.is_empty() else 7.0


func _ensure_pieces() -> void:
	var ahead: float = _pieces[0].length - _s
	for k in range(1, _pieces.size()):
		ahead += _pieces[k].length
	while ahead < 70.0:
		var last = _pieces[_pieces.size() - 1]
		var last_edge := -1
		for k in range(_pieces.size() - 1, -1, -1):
			if not _pieces[k].is_turn():
				last_edge = _pieces[k].edge
				break
		var nxt: int = _network.next_edge(last_edge, _rng)
		var turn = _network.turn_piece(last_edge, nxt)
		var lane = _network.edge_piece(nxt)
		if not last.is_turn():
			_pieces.append(turn)
			ahead += turn.length
		_pieces.append(lane)
		ahead += lane.length


## Point on the planned path `dist` metres ahead of the vehicle centre,
## shifted sideways by `offset` (positive = towards the road centre).
func _path_point(dist: float, offset: float) -> Vector3:
	var d := _s + dist
	for p in _pieces:
		if d <= p.length:
			var t: Vector3 = p.tangent_at(d)
			return p.position_at(d) + t.cross(Vector3.UP) * offset
		d -= p.length
	var last = _pieces[_pieces.size() - 1]
	return last.position_at(last.length)


## Where the vehicle will be after driving `dist` more metres on its route.
func predict_position(dist: float) -> Vector3:
	return _path_point(dist, lat)


func _lane_room() -> float:
	return maxf(get_road_width() * 0.25 - half.x - 0.25, 0.0)


func _overtake_offset() -> float:
	var w := get_road_width()
	return minf(w * 0.25 + 0.7, w * 0.75 - half.x - 0.3)


# --- Driving -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _pieces.is_empty():
		return
	var now: float = _controller.time
	dist_to_player = _controller.distance_to_player(global_position)
	# Far from the player, drive in steps of three ticks (nobody can see the
	# difference from there, and it saves a lot of work in heavy traffic).
	if dist_to_player > 80.0:
		_far_dt += delta
		_far_tick = (_far_tick + 1) % 3
		if _far_tick != id % 3:
			return
		delta = _far_dt
	_far_dt = 0.0
	_horn_cooldown -= delta
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		# A little jitter keeps vehicles from all looking around on the same tick.
		# Far from the player with a clear road it can look less often; with
		# something ahead it keeps looking, or it brakes too late.
		var relaxed := dist_to_player >= 70.0 and _blocker.is_empty()
		_sense_timer = (0.4 if relaxed else 0.1) * _rng.randf_range(0.8, 1.25)
		_sense(now)
		_think(now)

	var target := minf(_max_speed, minf(_allowed_speed, _gap_speed))
	if now < _slow_until:
		target *= 0.35
	if now < _stopped_until:
		target = 0.0
	var rate: float = _cfg.accel if target > speed else _cfg.decel
	if _gap_speed < speed - 2.0:
		rate *= 2.0  # emergency braking
	speed = move_toward(speed, target, rate * delta)

	# Intentional stops (pull-over, bus stop, pausing at a junction).
	if _stop_s >= 0.0 and not _pieces[0].is_turn() and _s >= _stop_s - 0.8 and speed < 0.4:
		_stopped_until = now + _stop_duration
		_stop_s = -1.0
	if now >= _stopped_until and _stop_pull and _stop_s < 0.0:
		_stop_pull = false
		_lat_target = 0.0

	var intentional := now < _stopped_until
	if speed < 0.2 and not intentional:
		stuck_time += delta
	else:
		stuck_time = 0.0

	_s += speed * delta
	while _s >= _pieces[0].length and _pieces.size() > 1:
		_s -= _pieces[0].length
		_pieces.pop_front()
		if not _pieces[0].is_turn():
			current_edge = _pieces[0].edge
			_on_enter_edge()
		_ensure_pieces()

	var prev_lat := lat
	# Never aim beyond this road's edges (a pull-over or overtake from a
	# wider road carries on after turning into a narrower one).
	_lat_target = clampf(_lat_target, -_lane_room(), maxf(_overtake_offset(), 0.0))
	# Real vehicles can't slide sideways when stopped: lane changes need speed.
	if bike_down:
		_lat_target = lat  # a fallen bike stays where it fell
	lat = move_toward(lat, _lat_target, clampf(0.25 + speed * 0.25, 0.25, 1.3) * delta)
	_lat_vel = (lat - prev_lat) / maxf(delta, 0.0001)
	_apply_pose(delta)
	_animate(delta)


func _apply_pose(delta: float) -> void:
	var p = _pieces[0]
	var t: Vector3 = p.tangent_at(_s)
	var right := t.cross(Vector3.UP)
	var pos: Vector3 = p.position_at(_s) + right * lat
	var heading := t * maxf(speed, 2.0) + right * _lat_vel * 0.6
	var wanted := atan2(-heading.x, -heading.z)
	_yaw = wanted if delta == 0.0 else lerp_angle(_yaw, wanted, 1.0 - exp(-10.0 * delta))
	var basis := Basis(Vector3.UP, _yaw)
	global_transform = Transform3D(basis, pos - basis * Vector3(0, 0, center_z))


func _on_enter_edge() -> void:
	_stop_s = -1.0
	_stop_pull = false
	var piece = _pieces[0]
	# Buses stop at bus stops on their lane.
	if vehicle_type == "bus":
		for stop: Vector3 in _controller.bus_stops:
			var e: Dictionary = _network.edges[current_edge]
			var along: float = (stop - e.start).dot(e.dir)
			var off: float = ((stop - e.start) - e.dir * along).length()
			if off < 4.5 and along > 3.0 and along < piece.length - 3.0:
				_stop_s = along
				_stop_duration = _rng.randf_range(4.0, 7.0)
				_stop_pull = true
				return
	if piece.length > 25.0 and _rng.randf() < _cfg.stop:
		# Pull over to drop or pick up someone.
		_stop_s = piece.length * _rng.randf_range(0.3, 0.75)
		_stop_duration = _rng.randf_range(2.0, 5.0)
		_stop_pull = true
	elif _rng.randf() < 0.18:
		# Pause before the next junction, as if looking around.
		_stop_s = piece.length - 0.8
		_stop_duration = _rng.randf_range(0.5, 1.8)


## Looks ahead along the planned path for obstacles and upcoming corners.
func _sense(now: float) -> void:
	var look := maxf(8.0, speed * 1.7 + 6.0)
	var ignore_ai := now < _ignore_ai_until
	var hit := _first_obstacle(lat, look, ignore_ai)
	var stop_gap := 1.6 if vehicle_type == "bus" else 1.0
	if hit.is_empty():
		_gap_speed = 99.0
		_blocker = {}
	else:
		# The real gap can be up to one sampling step shorter than the hit distance.
		var gap: float = maxf(hit.gap - 1.5, 0.0)
		_gap_speed = sqrt(2.0 * _cfg.decel * maxf(gap - stop_gap, 0.0))
		# Follow a moving vehicle ahead instead of stopping dead.
		var o: Dictionary = hit.obstacle
		if gap > stop_gap + 1.5 and o.speed > 0.5:
			_gap_speed = maxf(_gap_speed, o.speed * 0.9)
		_blocker = o

	# Slow down for corners and planned stops.
	var allowed := 99.0
	var turn_speed: float = _cfg.turn
	if _pieces[0].is_turn() and _pieces[0].points.size() > 2:
		allowed = turn_speed
	var dist: float = _pieces[0].length - _s
	for k in range(1, _pieces.size()):
		var p = _pieces[k]
		if p.is_turn() and p.points.size() > 2:
			allowed = minf(allowed, sqrt(turn_speed * turn_speed + 2.0 * _cfg.decel * dist))
			break
		dist += p.length
	if _stop_s >= 0.0 and not _pieces[0].is_turn():
		var to_stop := _stop_s - _s
		allowed = minf(allowed, sqrt(2.0 * _cfg.decel * maxf(to_stop - 0.5, 0.0)))
		if _stop_pull and to_stop < 12.0:
			_lat_target = -_lane_room()
	_allowed_speed = allowed


## Returns {gap, obstacle} for the first obstacle on the path, or {}.
func _first_obstacle(offset: float, look: float, ignore_ai: bool) -> Dictionary:
	# Only obstacles within reach of the stretch of path being checked.
	var c := get_center()
	var room := half.z + look + absf(offset - lat) + half.x + 2.5
	var obstacles: Array = []
	for o: Dictionary in _controller.obstacles:
		if o.node == self or (ignore_ai and o.ai):
			continue
		var r: float = room + o.radius
		if (o.pos as Vector3).distance_squared_to(c) <= r * r:
			obstacles.append(o)
	if obstacles.is_empty():
		return {}
	# Start just behind the front bumper, so someone lying right in front
	# of the vehicle (e.g. just knocked over) is seen too.
	var d := -0.5
	while d <= look:
		var q := _path_point(half.z + d, offset)
		for o: Dictionary in obstacles:
			# People get a wider berth than vehicles.
			var margin: float = 0.7 if o.get("ped", false) else 0.2
			var reach: float = o.radius + half.x + margin + 0.4
			if (o.pos as Vector3).distance_squared_to(q) > reach * reach:
				continue
			var local: Vector3 = o.inv * q
			if absf(local.x) < o.half.x + half.x + margin and absf(local.z) < o.half.z + 0.5:
				return {"gap": maxf(d, 0.0), "obstacle": o}
		d += 1.5
	return {}


## Decisions: honking, overtaking, weaving, cutting in, breaking deadlocks.
func _think(now: float) -> void:
	var blocked := not _blocker.is_empty() and _gap_speed < 0.6 and speed < 0.8
	blocked_time = blocked_time + 0.1 if blocked else 0.0
	var near_turn: bool = _pieces[0].is_turn() or (_pieces[0].length - _s) < 10.0
	var player_blocks: bool = blocked and not _blocker.ai

	if blocked and blocked_time > 0.7:
		honk()
	elif not _blocker.is_empty() and not _blocker.ai and dist_to_player < 12.0 and _rng.randf() < 0.05:
		honk()
	elif speed > 1.0 and dist_to_player < 45.0 and _rng.randf() < 0.003:
		honk()  # Dhaka drivers honk just because

	# Try to go round a stopped obstacle, using the other lane if it is free.
	if blocked and not near_turn and blocked_time > (2.5 if player_blocks else 1.5) and now > _overtake_until:
		var o_lat := _overtake_offset()
		if _first_obstacle(o_lat, 16.0, false).is_empty():
			_lat_target = o_lat
			_overtake_until = now + 5.0
	if now > _overtake_until and _lat_target > _lane_room() + 0.01 and not _stop_pull:
		if _first_obstacle(0.0, 8.0, true).is_empty():
			_lat_target = 0.0

	# Deadlock breaker: vehicles waiting for each other take turns pushing through.
	if blocked and _blocker.ai and blocked_time > 3.0:
		var other_id: int = _blocker.node.id
		if other_id > id or blocked_time > 6.0:
			_ignore_ai_until = now + 2.5
	if stuck_time > 12.0:
		_ignore_ai_until = now + 3.0

	if near_turn and not _stop_pull and now > _overtake_until:
		_lat_target = 0.0
	elif not _stop_pull and now > _overtake_until:
		# Weaving within the lane.
		_weave_timer -= 0.1
		if _weave_timer <= 0.0 and _cfg.weave > 0.0:
			_weave_timer = _rng.randf_range(2.0, 5.0) / _cfg.weave
			var room := _lane_room() * minf(_cfg.weave, 1.0)
			_lat_target = _rng.randf_range(-room, room)
		# CNGs and motorbikes love to squeeze in front of a slow rickshaw.
		_cut_in_timer -= 0.1
		if (vehicle_type == "cng" or vehicle_type == "motorcycle") and _cut_in_timer <= 0.0:
			_cut_in_timer = 4.0
			var local: Vector3 = global_transform.affine_inverse() * _controller.player_position()
			if local.z > 1.0 and local.z < 9.0 and absf(local.x) > 0.8 and absf(local.x) < 3.5 \
					and speed > _controller.player_speed() + 1.0 and _rng.randf() < 0.5:
				_lat_target = clampf(lat + local.x, -_lane_room(), _overtake_offset())
		# Sudden, pointless braking.
		if speed > 3.0 and _rng.randf() < 0.004:
			_slow_until = now + 1.5

	# Whatever was decided, never swing sideways into something alongside.
	if absf(_lat_target - lat) > 0.05 and not _side_clear(_lat_target):
		_lat_target = lat


## True if nothing is beside the vehicle's whole length at `offset`. A big
## swing across the road (e.g. from overtaking straight to the kerb) must also
## be clear halfway, alongside the body, or it would sweep through whatever
## it just passed.
func _side_clear(offset: float) -> bool:
	var big_swing := absf(offset - lat) > 2.0
	for o: Dictionary in _controller.obstacles:
		if o.node == self or (o.pos as Vector3).distance_squared_to(global_position) > 64.0:
			continue
		var d := -half.z - 0.5
		while d <= half.z + 1.0:
			var local: Vector3 = o.inv * _path_point(d, offset)
			if absf(local.x) < o.half.x + half.x + 0.15 and absf(local.z) < o.half.z + 0.3:
				return false
			if big_swing and d <= half.z - 0.3:
				local = o.inv * _path_point(d, (lat + offset) * 0.5)
				if absf(local.x) < o.half.x + half.x + 0.15 and absf(local.z) < o.half.z + 0.3:
					return false
			d += 1.0
	return true


func honk(force := false) -> void:
	if _horn.stream == null or dist_to_player > 70.0:
		return
	if not force and _horn_cooldown > 0.0:
		return
	# The global horn limit keeps the background din bearable; an angry
	# honk after being hit always sounds.
	if not _controller.request_horn() and not force:
		return
	_horn_cooldown = _rng.randf_range(2.5, 6.0)
	_horn.pitch_scale = _rng.randf_range(0.95, 1.05)
	_horn.play()
	honked.emit(self)


## Called by the player's rickshaw when it crashes into this vehicle.
func on_player_impact(impact: float) -> void:
	if vehicle_type == "motorcycle":
		if not bike_down:
			_bike_crash()
		return
	_stopped_until = _controller.time + _rng.randf_range(1.5, 3.0)
	speed = 0.0
	_jolt = clampf(impact * 0.025, 0.03, 0.12)
	honk(true)
	say(ANGRY_LINES[_rng.randi() % ANGRY_LINES.size()])


# --- Motorcycle crash ---------------------------------------------------------------
# Hit a motorbike and it tips over; the rider (and the passenger, if any) fall
# off, lie dazed with stars, shout, then get up, lift the bike and ride on.

func _bike_crash() -> void:
	bike_down = true
	speed = 0.0
	_stopped_until = _controller.time + 60.0  # released by _remount()
	_mesh.mesh = VehicleModels.build("motorcycle_empty", _variant).mesh
	var away: Vector3 = global_position - _controller.player_position()
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else global_transform.basis.x
	var side := signf(global_transform.basis.x.dot(away))
	side = side if side != 0.0 else 1.0
	_bike_tween = create_tween()
	_bike_tween.tween_property(_model, "rotation:z", -1.35 * side, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var riders := 1 + _variant % 2
	for i in riders:
		var p := PersonModel.new()
		# The rider in shirt and trousers; a passenger in salwar kameez or saree.
		p.variant = (1 + 8 * (_variant % 2)) if i == 0 else [5, 4, 13][_variant % 3]
		_controller.add_child(p)
		var seat := global_transform * Vector3(0, 0.15, 0.2 + i * 0.32)
		var land: Vector3 = seat + away * (1.6 + i * 0.9) + global_transform.basis.z * (i * 0.6 - 0.3)
		land.y = PedestrianNetworkGround.ground_y(land.x, land.z)
		p.global_position = seat
		p.basis = Basis.looking_at(-away)  # facing the bike, falling backwards
		p.set_pose(PersonModel.Pose.FALLEN)
		p.animate = true
		var line: String = Pedestrian.random_hit_shout(_rng) if i == 0 else BIKER_LINES[_rng.randi() % BIKER_LINES.size()]
		_person_say(p, line, i)
		var fly := p.create_tween()
		fly.tween_method(_fly_person.bind(p, seat, land), 0.0, 1.0, 0.45)
		_fallen.append(p)
	# Lie there for a bit, then get up, walk back and pick up the bike.
	_bike_tween.tween_interval(4.0)
	_bike_tween.tween_callback(_riders_get_up)
	_bike_tween.tween_interval(1.3)
	_bike_tween.tween_property(_model, "rotation:z", 0.0, 0.6)
	_bike_tween.tween_callback(_remount)


func _fly_person(f: float, p: Node3D, from: Vector3, to: Vector3) -> void:
	if is_instance_valid(p):
		p.global_position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 0.7, 0)


func _person_say(p: Node3D, text: String, index := 0) -> void:
	var l := Label3D.new()
	if ResourceLoader.exists(FONT_PATH):
		l.font = load(FONT_PATH)
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.009
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 12
	l.outline_modulate = Color(0.1, 0.02, 0.02)
	l.position = Vector3(0, 1.4 + index * 0.55, 0)  # stacked, so two shouts don't overlap
	p.add_child(l)


func _riders_get_up() -> void:
	for p in _fallen:
		if not is_instance_valid(p):
			continue
		p.set_pose(PersonModel.Pose.WALK)
		p.speed = 1.4
		var to := global_position + (p.global_position - global_position).normalized() * 0.7
		to.y = p.global_position.y
		var walk := p.create_tween()
		walk.tween_property(p, "global_position", to, 1.2)


## Riders back on the bike; it rides on.
func _remount() -> void:
	if _bike_tween and _bike_tween.is_valid():
		_bike_tween.kill()
	for p in _fallen:
		if is_instance_valid(p):
			p.queue_free()
	_fallen.clear()
	_model.rotation.z = 0.0
	_mesh.mesh = VehicleModels.build("motorcycle", _variant).mesh
	bike_down = false
	_stopped_until = _controller.time + 0.5


## A bump with another AI vehicle in a jam. The one that got bumped pauses;
## the one pushing through keeps going (or the deadlock would never clear).
func bump_reaction(got_bumped: bool) -> void:
	_jolt = maxf(_jolt, 0.05)
	if got_bumped:
		_stopped_until = maxf(_stopped_until, _controller.time + 0.6)
	honk()
	if _rng.randf() < 0.5:
		say(BUMP_LINES[_rng.randi() % BUMP_LINES.size()])


## True while it ignores other vehicles to break a deadlock.
func is_pushing_through() -> bool:
	return _controller.time < _ignore_ai_until


## The driver shouts something (Bangla speech bubble above the vehicle).
func say(text: String, seconds := 2.2) -> void:
	if dist_to_player > 45.0:
		return
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.name = "Speech"
		if ResourceLoader.exists(FONT_PATH):
			_bubble.font = load(FONT_PATH)
		_bubble.font_size = 40
		_bubble.pixel_size = 0.009
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.outline_size = 12
		_bubble.outline_modulate = Color(0.1, 0.02, 0.02)
		_bubble.modulate = Color(1, 0.9, 0.7)
		_bubble.position = Vector3(0, half.y * 2.0 + 0.6, center_z)
		add_child(_bubble)
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = seconds


## Called by the pedestrian manager after knocking someone over.
func on_pedestrian_hit() -> void:
	_stopped_until = _controller.time + _rng.randf_range(2.0, 3.5)
	speed = 0.0
	honk(true)


func _animate(delta: float) -> void:
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_bubble.visible = false
	if _engine:
		if dist_to_player < 35.0 and not _engine.playing:
			_engine.play()
		elif dist_to_player > 40.0 and _engine.playing:
			_engine.stop()
		_engine.pitch_scale = 0.8 + clampf(speed / _max_speed, 0.0, 1.0) * 0.6
	if _rickshaw:
		_rickshaw.set_far(dist_to_player > _detail_distance)
	if _rickshaw and dist_to_player < _detail_distance:
		var steer := clampf(-_lat_vel * 0.1, -0.4, 0.4)
		_rickshaw.update_motion(speed, steer, speed > 0.3, delta)
	if bike_down:
		pass  # lying on its side; the crash animation owns the rotation
	elif _jolt > 0.001:
		_jolt = move_toward(_jolt, 0.0, delta * 0.12)
		_model.rotation.z = sin(_controller.time * 35.0) * _jolt
	elif _model.rotation.z != 0.0:
		_model.rotation.z = 0.0

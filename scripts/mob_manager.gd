## The angry crowd (গণপিটুনি, cartoon style).
##
## Knock someone over with the rickshaw (or knock a motorbike over) and the
## people nearby come running for the rickshaw-wala, shouting "ধর শালারে!"
## and "তুই আজকে শেষ!". If they catch you standing still they gather round
## and thump the rickshaw (a bit of damage each time) until they have made
## their point. Pedal away faster than they can run and they give up.
extends Node3D

const Pedestrian := preload("res://scripts/pedestrian.gd")
const PersonModel := preload("res://scripts/person_model.gd")
const PedestrianNetworkGround := preload("res://scripts/pedestrian_network.gd")

enum Phase { NONE, CHASE }

const CHASE_LINES := ["ধর শালারে!", "তুই আজকে শেষ!", "ধর! ধর! পালাইতে দিস না!", "ওই রিকশা থাম!"]
const BEAT_LINES := ["তুই আজকে শেষ!", "ধর শালারে!", "মার! মার!", "চোখে দেখস না?"]
const GAVE_UP_LINES := ["পালাইলি কই!", "ধুর! পালাইছে!", "আবার দেখা হবে!"]
const DONE_LINES := ["যা, আর কোনোদিন এমন করবি না!", "এইবার ছাইড়া দিলাম!", "দেখে চালাবি, বুঝলি?"]
const THUMP_WORDS := ["ধুম!", "ঠাস!", "দুম!"]
## People who join in per hit (the closest ones), and at most in one crowd.
const JOIN_PER_HIT := 3
const MAX_MOB := 5
## Only people this close to the accident come running.
const JOIN_RADIUS := 30.0
## Running speed (m/s): the rickshaw's top speed is about 7.2 m/s.
const RUN_SPEED := 4.4
## The crowd gives up when everyone is this far behind, or after this long.
const ESCAPE_DISTANCE := 22.0
const MAX_CHASE_TIME := 25.0
## Damage (%) per thump, seconds between thumps and thumps per crowd.
const THUMP_DAMAGE := 1.5
const THUMP_INTERVAL := 0.75
const MAX_THUMPS := 8
## Where the crowd stands round the rickshaw (local x, z; -Z is the front).
const SLOTS := [Vector2(-1.35, -0.6), Vector2(1.35, -0.6), Vector2(-1.35, 0.8),
	Vector2(1.35, 0.8), Vector2(0.0, -2.5)]

@export var player_path: NodePath
@export var pedestrians_path: NodePath
@export var passengers_path: NodePath
@export var collisions_path: NodePath
@export var camera_path: NodePath
@export var enabled := true

var phase: Phase = Phase.NONE
## The people in the crowd right now.
var members: Array[Node3D] = []
var thumps := 0
var mobs_started := 0
var escapes := 0

var _player: Node3D
var _peds: Node
var _passengers: Node
var _collisions: Node
var _camera: Node
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _thump_timer := 0.0
var _shout_timer := 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_peds = get_node_or_null(pedestrians_path)
	_passengers = get_node_or_null(passengers_path)
	_collisions = get_node_or_null(collisions_path)
	_camera = get_node_or_null(camera_path)
	_rng.randomize()
	if _peds:
		_peds.pedestrian_hit_by_player.connect(_on_pedestrian_hit)
	if _player and _player.has_signal("crashed"):
		_player.crashed.connect(_on_player_crashed)


func _on_pedestrian_hit(victim: Node3D, _speed: float, _accident: bool) -> void:
	if enabled:
		start_mob(victim.global_position, victim)


## Knocking a motorbike over (its riders fly off) angers the street too.
func _on_player_crashed(_severity: int, _impact: float, other: Object) -> void:
	if enabled and other is Node3D and "vehicle_type" in other and other.vehicle_type == "motorcycle" \
			and other.bike_down:
		start_mob((other as Node3D).global_position)


## Gathers the closest bystanders around `where` into a crowd that chases
## the player. Returns how many joined.
func start_mob(where: Vector3, exclude: Node3D = null) -> int:
	if _player == null or _peds == null:
		return 0
	var picks: Array = []
	for ped in _peds.pedestrians:
		if ped == exclude or not ped.is_free_walker() or ped in members:
			continue
		var d := _flat(ped.global_position, where)
		if d < JOIN_RADIUS:
			picks.append([d, ped])
	picks.sort_custom(func(a, b): return a[0] < b[0])
	var joined := 0
	for pick in picks:
		if joined >= JOIN_PER_HIT or members.size() >= MAX_MOB:
			break
		var ped: Node3D = pick[1]
		ped.state = Pedestrian.State.VICTIM  # moved by this manager
		ped.targeted = true
		ped.on_road = false
		ped.model.set_far(false)
		ped.model.animate = true
		ped.model.set_pose(PersonModel.Pose.WALK)
		ped.model.speed = RUN_SPEED
		# Not everyone at once, so the shouts can be read.
		# The first two always shout the classics.
		var line: String = CHASE_LINES[joined] if joined < 2 else CHASE_LINES[_rng.randi() % CHASE_LINES.size()]
		get_tree().create_timer(0.3 + joined * 0.5, false).timeout.connect(func():
			if is_instance_valid(ped) and ped in members:
				ped.say(line, 2.5))
		members.append(ped)
		joined += 1
	if joined == 0:
		return 0
	if phase == Phase.NONE:
		mobs_started += 1
		thumps = 0
		_thump_timer = 0.0
		GameManager.post_message("লোকজন খেপে গেছে! পালান!", GameManager.MSG_WARN)
		if _passengers and _passengers.passenger and _passengers.trip_state == 2:
			_passengers.passenger.say("ভাই, জোরে চালান!", 3.0)
	phase = Phase.CHASE
	_time = 0.0
	_shout_timer = _rng.randf_range(2.5, 4.0)
	return joined


func _physics_process(delta: float) -> void:
	if phase == Phase.NONE:
		return
	for i in range(members.size() - 1, -1, -1):
		if not is_instance_valid(members[i]) or members[i].state != Pedestrian.State.VICTIM:
			members.remove_at(i)  # taken over by someone else (e.g. a mugging)
	if members.is_empty() or _player == null:
		_end()
		return
	_time += delta
	var spd := absf(_player.speed)
	var pxf: Transform3D = _player.global_transform
	var nearest := 1e9
	var at_rickshaw := 0
	for i in members.size():
		var ped: Node3D = members[i]
		var slot: Vector2 = SLOTS[i % SLOTS.size()]
		var target := pxf * Vector3(slot.x, 0, slot.y)
		var d := _flat(ped.global_position, _player.global_position)
		nearest = minf(nearest, d)
		if _run_to(ped, target, delta) and spd < 2.5:
			at_rickshaw += 1
			ped.model.set_pose(PersonModel.Pose.WAVE)  # fist in the air
			_face(ped, _player.global_position)
		else:
			ped.model.set_pose(PersonModel.Pose.WALK)
			ped.model.speed = RUN_SPEED

	if _collisions and _collisions.wrecked:
		_disperse(DONE_LINES, "")
		return
	if at_rickshaw > 0:
		_thump_timer -= delta
		if _thump_timer <= 0.0:
			_thump_timer = THUMP_INTERVAL
			_thump()
			if thumps >= MAX_THUMPS:
				_disperse(DONE_LINES, "লোকজন শান্ত হয়েছে।")
				return
	_shout_timer -= delta
	if _shout_timer <= 0.0:
		_shout_timer = _rng.randf_range(2.0, 3.5)
		var lines := BEAT_LINES if at_rickshaw > 0 else CHASE_LINES
		members[_rng.randi() % members.size()].say(lines[_rng.randi() % lines.size()], 2.2)
	if nearest > ESCAPE_DISTANCE or _time > MAX_CHASE_TIME:
		escapes += 1
		_disperse(GAVE_UP_LINES, "বেঁচে গেলেন! লোকজন পিছু ছেড়েছে।")


## Runs towards `target`. Returns true once there.
func _run_to(ped: Node3D, target: Vector3, delta: float) -> bool:
	var to := target - ped.global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.35:
		return true
	var next := ped.global_position + to / d * minf(RUN_SPEED * delta, d)
	# Walls and buildings are in the way: wait there, shaking a fist.
	if not _peds.is_clear_line(ped.global_position, next):
		return false
	next.y = PedestrianNetworkGround.ground_y(next.x, next.z)
	ped.global_position = next
	ped.on_road = next.y < 0.01
	_face(ped, target)
	ped._speed_now = RUN_SPEED
	ped._update_obstacle()
	return false


func _thump() -> void:
	thumps += 1
	GameManager.add_damage(THUMP_DAMAGE)
	var pos := _player.global_position + Vector3.UP * 0.6
	if _collisions:
		_collisions.spawn_impact_effect(pos, 0, false, THUMP_WORDS[_rng.randi() % THUMP_WORDS.size()])
		_collisions.play_sound("bump", -4.0, _rng.randf_range(0.85, 1.15))
	if _camera and _camera.has_method("add_shake"):
		_camera.add_shake(0.25)
	if thumps == 1:
		GameManager.post_message("মাইর খাচ্ছেন! পালান!", GameManager.MSG_BAD)


## The crowd breaks up: each one says something and walks back to the footpath.
func _disperse(lines: Array, message: String) -> void:
	for ped in members:
		ped.targeted = false
		ped._speed_now = 0.0
		ped.walk_back_to_footpath(_player.global_position)
		ped.say(lines[_rng.randi() % lines.size()], 2.5)
	if message != "":
		GameManager.post_message(message, GameManager.MSG_GOOD if lines == GAVE_UP_LINES else GameManager.MSG_INFO)
	_end()


func _end() -> void:
	for ped in members:
		if is_instance_valid(ped):
			ped.targeted = false
	members.clear()
	phase = Phase.NONE


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _face(n: Node3D, target: Vector3) -> void:
	var d := target - n.global_position
	if Vector2(d.x, d.z).length_squared() > 0.0001:
		n.rotation = Vector3(0, atan2(-d.x, -d.z), 0)

## Muggers (ছিনতাইকারী) in Mohammadpur.
##
## While the player is in or near Mohammadpur, muggers with knives are a
## common sight: every few seconds one appears, and up to MAX_EVENTS
## muggings can be going on around you at once. A mugger either sneaks up on
## a pedestrian, threatens them and runs off with their bag, or comes for the
## player's earnings when the rickshaw is stopped (only one at a time does
## that). Ride into him and he is caught: the victim rewards you, or you get
## your money back. Pedal away fast enough and he gives up. Cartoon style:
## he only threatens; nobody gets hurt.
extends Node3D

const CityLayout := preload("res://scripts/city_layout.gd")
const Pedestrian := preload("res://scripts/pedestrian.gd")
const PedestrianScene := preload("res://scenes/pedestrians/pedestrian.tscn")
const PersonModel := preload("res://scripts/person_model.gd")
const PedestrianNetworkGround := preload("res://scripts/pedestrian_network.gd")
const PLAYER_HALF := Vector3(0.65, 0.95, 1.2)
const PLAYER_CENTER_Z := -0.24

enum Phase { NONE, APPROACH, THREATEN, FLEE, CAUGHT, GAVE_UP }

const MUGGER_LINES := ["চুপ! ব্যাগটা দে!", "টাকা-পয়সা যা আছে দে!", "মোবাইলটা দে, জলদি!"]
const PLAYER_THREATS := ["টাকা দে!", "এই রিকশা, টাকা দে!", "চুপচাপ টাকা দে!"]
const VICTIM_CRIES := ["বাঁচাও! ছিনতাই!", "ও মাগো! ছিনতাই!", "কে আছেন, বাঁচান!"]
const CAUGHT_LINES := ["ও মাগো! মাফ করে দেন!", "আর করব না!", "ছেড়ে দেন ভাই!"]
## A pedestrian rewards you this much for catching their mugger.
const RESCUE_REWARD := 50
## Bonus on top of your own money back.
const CATCH_BONUS := 20
## Share of your earnings a mugger takes (at most MAX_STOLEN).
const STOLEN_SHARE := 0.4
const MAX_STOLEN := 200
## Muggings that can be going on at the same time.
const MAX_EVENTS := 3


## One mugging: the mugger, who he is after, and how far it has got.
class Mugging:
	var phase := 0  # Phase
	var mugger: Node3D = null
	## The pedestrian being mugged, or null when the player is the target.
	var victim: Node3D = null
	var targets_player := false
	var stolen := 0
	var phase_time := 0.0


@export var player_path: NodePath
@export var pedestrians_path: NodePath
@export var passengers_path: NodePath
@export var collisions_path: NodePath
@export var camera_path: NodePath
## Seconds between new muggings while the player is around Mohammadpur.
@export var interval := Vector2(6.0, 14.0)

## All muggings going on right now.
var events: Array[Mugging] = []
var muggings := 0
var caught_count := 0
var warned := false

## The mugging the properties below describe: the one after the player's
## money if there is one, otherwise the newest.
var phase: Phase:
	get: return _focus().phase if _focus() else Phase.NONE
var mugger: Node3D:
	get: return _focus().mugger if _focus() else null
var victim: Node3D:
	get: return _focus().victim if _focus() else null
var targets_player: bool:
	get: return _focus().targets_player if _focus() else false
var stolen: int:
	get: return _focus().stolen if _focus() else 0

var _player: Node3D
var _peds: Node
var _passengers: Node
var _collisions: Node
var _camera: Node
var _rng := RandomNumberGenerator.new()
var _timer := 4.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_peds = get_node_or_null(pedestrians_path)
	_passengers = get_node_or_null(passengers_path)
	_collisions = get_node_or_null(collisions_path)
	_camera = get_node_or_null(camera_path)
	_rng.randomize()


func _focus() -> Mugging:
	for e in events:
		if e.targets_player:
			return e
	return events[-1] if not events.is_empty() else null


func _physics_process(delta: float) -> void:
	if _player == null or _peds == null:
		return
	var near := _near_mohammadpur(_player.global_position)
	if near and CityLayout.in_mohammadpur(_player.global_position) and not warned:
		warned = true
		GameManager.post_message("সাবধান! মোহাম্মদপুরে ছিনতাই হয়", GameManager.MSG_WARN)
	if near and events.size() < MAX_EVENTS:
		_timer -= delta
		if _timer <= 0.0:
			_timer = _rng.randf_range(interval.x, interval.y)
			_start_random_event()
	for e in events.duplicate():
		e.phase_time += delta
		_update_event(e, delta)


func _near_mohammadpur(p: Vector3) -> bool:
	return CityLayout.MOHAMMADPUR.grow(15.0).has_point(Vector2(p.x, p.z))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _player_targeted() -> bool:
	for e in events:
		if e.targets_player:
			return true
	return false


func _start_random_event() -> void:
	var can_rob_player := absf(_player.speed) < 1.0 and CityLayout.in_mohammadpur(_player.global_position) \
		and not _player_targeted()
	if can_rob_player and _rng.randf() < 0.4:
		start_player_mugging()
		return
	var candidates: Array[Node3D] = []
	for ped in _peds.pedestrians:
		if not ped.is_free_walker() or not CityLayout.in_mohammadpur(ped.global_position):
			continue
		var d := _flat(ped.global_position, _player.global_position)
		if d > 12.0 and d < 50.0:
			candidates.append(ped)
	if not candidates.is_empty():
		start_pedestrian_mugging(candidates[_rng.randi() % candidates.size()])
	elif can_rob_player:
		start_player_mugging()


# --- Starting events --------------------------------------------------------------------

func _spawn_mugger() -> Node3D:
	var m: Node3D = PedestrianScene.instantiate()
	add_child(m)
	m.setup(_peds, _peds.network, PersonModel.MUGGER_VARIANT, _rng.randi())
	m.name = "Mugger"
	m.add_to_group("muggers")
	m.model.add_knife()
	m.allow_crossing = false
	m._bubble.position.y = 2.75  # above the victim's bubble, so they don't overlap
	return m


func _new_event(m: Node3D, v: Node3D, on_player: bool) -> Mugging:
	var e := Mugging.new()
	e.mugger = m
	e.victim = v
	e.targets_player = on_player
	e.phase = Phase.APPROACH
	events.append(e)
	muggings += 1
	return e


## A mugger sneaks up behind `ped` along the footpath. Returns false if not possible.
func start_pedestrian_mugging(ped: Node3D) -> bool:
	if events.size() >= MAX_EVENTS or ped == null or not ped.is_free_walker():
		return false
	var edge: int = ped.current_edge()
	var e: Dictionary = _peds.network.edges[edge]
	var t: float = ped._t
	var m := _spawn_mugger()
	# Start 12 m away on the same footpath, walking towards the victim.
	if t >= 12.0:
		m.place_on_edge(edge, t - 12.0, 1)
	else:
		m.place_on_edge(edge, minf(t + 12.0, e.length), -1)
	m.walk_speed = 2.0
	ped.targeted = true
	_new_event(m, ped, false)
	return true


## A mugger comes for the player's money. Returns false if not possible.
func start_player_mugging() -> bool:
	if events.size() >= MAX_EVENTS or _player_targeted():
		return false
	var hit: Array = _peds.network.nearest_walk_point(_player.global_position)
	if hit[0] < 0:
		return false
	var e: Dictionary = _peds.network.edges[hit[0]]
	var t: float = clampf(hit[1] + (8.0 if _rng.randf() < 0.5 else -8.0), 0.0, e.length)
	var m := _spawn_mugger()
	m.place_on_edge(hit[0], t, 1)
	m.state = Pedestrian.State.VICTIM  # moved by this manager, not by walking
	m.model.set_pose(PersonModel.Pose.WALK)
	m.model.speed = 2.4
	_new_event(m, null, true)
	m.say(PLAYER_THREATS[_rng.randi() % PLAYER_THREATS.size()], 3.0)
	if _passengers and _passengers.passenger and _passengers.trip_state == 2:
		_passengers.passenger.say("জোরে চালান! ছিনতাইকারী!", 3.0)
	return true


func _set_phase(e: Mugging, p: Phase) -> void:
	e.phase = p
	e.phase_time = 0.0


# --- Running events --------------------------------------------------------------------

func _update_event(e: Mugging, delta: float) -> void:
	if not is_instance_valid(e.mugger):
		_end_event(e)
		return
	if e.phase in [Phase.APPROACH, Phase.THREATEN, Phase.FLEE] and _player_rams(e.mugger):
		_catch(e)
		return
	match e.phase:
		Phase.APPROACH:
			if e.targets_player:
				_approach_player(e, delta)
			else:
				_approach_victim(e, delta)
		Phase.THREATEN:
			_threaten(e)
		Phase.FLEE, Phase.GAVE_UP:
			e.mugger.step(delta)
			var far := _flat(e.mugger.global_position, _player.global_position) > 60.0
			if e.phase_time > 20.0 or (far and not _visible(e.mugger)):
				_end_event(e)
		Phase.CAUGHT:
			e.mugger.step(delta)  # lies dazed (knocked state), then gets up
			if e.phase_time > 5.0:
				_end_event(e)


func _approach_victim(e: Mugging, delta: float) -> void:
	var v := e.victim
	if not is_instance_valid(v) or v.state not in [Pedestrian.State.WALKING, Pedestrian.State.VICTIM]:
		_flee(e)
		return
	e.mugger.step(delta)
	if _flat(e.mugger.global_position, v.global_position) < 1.3 or e.phase_time > 15.0:
		# Caught up: the victim freezes with hands up.
		v.state = Pedestrian.State.VICTIM
		v.model.set_pose(PersonModel.Pose.WAVE)
		v.say(VICTIM_CRIES[_rng.randi() % VICTIM_CRIES.size()], 3.0)
		e.mugger.state = Pedestrian.State.VICTIM  # held still while threatening
		e.mugger.model.set_pose(PersonModel.Pose.WAVE)
		e.mugger.say(MUGGER_LINES[_rng.randi() % MUGGER_LINES.size()], 2.5)
		_face(e.mugger, v.global_position)
		_face(v, e.mugger.global_position)
		_set_phase(e, Phase.THREATEN)


func _approach_player(e: Mugging, delta: float) -> void:
	var m := e.mugger
	var to := _player.global_position - m.global_position
	to.y = 0.0
	var d := to.length()
	if absf(_player.speed) > 2.0 and (d > 12.0 or e.phase_time > 8.0):
		_give_up(e)
		return
	if d < 2.0:
		m.model.set_pose(PersonModel.Pose.WAVE)  # knife raised
		m.say(PLAYER_THREATS[_rng.randi() % PLAYER_THREATS.size()], 2.0)
		_set_phase(e, Phase.THREATEN)
		return
	var step := to.normalized() * minf(2.6 * delta, d)
	var p := m.global_position + step
	p.y = PedestrianNetworkGround.ground_y(p.x, p.z)
	m.global_position = p
	_face(m, _player.global_position)
	if e.phase_time > 25.0:
		_give_up(e)


func _threaten(e: Mugging) -> void:
	if e.targets_player:
		_face(e.mugger, _player.global_position)
		if absf(_player.speed) > 2.0 and _flat(e.mugger.global_position, _player.global_position) > 2.5:
			_give_up(e)  # pedalled away in time
		elif e.phase_time > 1.6:
			_rob_player(e)
	elif e.phase_time > 2.5:
		# Grabs the bag and runs; the victim calls for help.
		e.victim.say("ধরুন ওকে! ছিনতাইকারী!", 3.5)
		_release_victim_later(e.victim)
		_flee(e)


func _rob_player(e: Mugging) -> void:
	e.stolen = mini(MAX_STOLEN, roundi(GameManager.earnings * STOLEN_SHARE))
	if e.stolen > 0:
		GameManager.add_earnings(-e.stolen)
		GameManager.post_message("ছিনতাই হয়ে গেল! −" + GameManager.format_taka(e.stolen), GameManager.MSG_BAD)
		e.mugger.say("হা হা! পালা!", 2.0)
	else:
		e.mugger.say("কিছুই নাই? যা ভাগ!", 2.5)
	_flee(e)


func _flee(e: Mugging) -> void:
	var m := e.mugger
	m.state = Pedestrian.State.WALKING
	var hit: Array = _peds.network.nearest_walk_point(m.global_position)
	var edge: Dictionary = _peds.network.edges[hit[0]]
	# Run along the footpath, away from the player.
	var along: Vector3 = ((edge.pb as Vector3) - edge.pa).normalized()
	var away := m.global_position - _player.global_position
	m.place_on_edge(hit[0], hit[1], 1 if along.dot(away) >= 0.0 else -1)
	m.walk_speed = 3.8
	m.allow_crossing = true
	_set_phase(e, Phase.FLEE)


func _give_up(e: Mugging) -> void:
	GameManager.post_message("ছিনতাইকারী থেকে বেঁচে গেলেন!", GameManager.MSG_GOOD)
	e.mugger.say("ধুর!", 1.5)
	_flee(e)
	_set_phase(e, Phase.GAVE_UP)


func _release_victim_later(v: Node3D) -> void:
	get_tree().create_timer(4.0, false).timeout.connect(func():
		if is_instance_valid(v) and v.state == Pedestrian.State.VICTIM:
			v.targeted = false
			v.finish_trip())


# --- Catching the mugger -----------------------------------------------------------------

func _player_rams(m: Node3D) -> bool:
	if absf(_player.speed) < 1.2:
		return false
	var pxf := _player.global_transform.translated_local(Vector3(0, 0, PLAYER_CENTER_Z))
	var local: Vector3 = pxf.affine_inverse() * m.global_position
	return absf(local.x) < PLAYER_HALF.x + 0.35 and absf(local.z) < PLAYER_HALF.z + 0.35


func _catch(e: Mugging) -> void:
	caught_count += 1
	var m := e.mugger
	m.knock(_player.global_position, absf(_player.speed), false)
	m.say(CAUGHT_LINES[_rng.randi() % CAUGHT_LINES.size()], 3.5)
	if _collisions:
		_collisions.spawn_impact_effect(m.global_position, 1, false, "ধরা!")
		_collisions.play_sound("bump", -2.0, 1.1)
	_player.speed *= 0.7
	var reward := 0
	var text := ""
	if e.targets_player and e.stolen > 0:
		reward = e.stolen + CATCH_BONUS
		text = "ছিনতাইকারী ধরা পড়েছে!\nটাকা ফেরত পেলেন: +" + GameManager.format_taka(reward)
	elif e.targets_player:
		reward = CATCH_BONUS
		text = "ছিনতাইকারী ধরা পড়েছে!\nপুরস্কার: +" + GameManager.format_taka(reward)
	else:
		reward = RESCUE_REWARD
		text = "ছিনতাইকারী ধরা পড়েছে!\nধন্যবাদ ভাই! বখশিশ: +" + GameManager.format_taka(reward)
		if is_instance_valid(e.victim):
			e.victim.say("ধন্যবাদ ভাই! আল্লাহ আপনার ভালো করুক!", 3.5)
			_release_victim_later(e.victim)
	e.stolen = 0
	GameManager.add_earnings(reward)
	GameManager.post_message(text, GameManager.MSG_GOOD)
	_set_phase(e, Phase.CAUGHT)


## Ends one mugging (or, with no argument, all of them).
func _end_event(e: Mugging = null) -> void:
	if e == null:
		for each in events.duplicate():
			_end_event(each)
		return
	var v := e.victim
	if is_instance_valid(v):
		v.targeted = false
		if v.state == Pedestrian.State.VICTIM:
			v.finish_trip()
	if is_instance_valid(e.mugger):
		e.mugger.queue_free()
	events.erase(e)


# --- Helpers ---------------------------------------------------------------------------

func _face(n: Node3D, target: Vector3) -> void:
	var d := target - n.global_position
	if Vector2(d.x, d.z).length_squared() > 0.0001:
		n.rotation = Vector3(0, atan2(-d.x, -d.z), 0)


func _visible(n: Node3D) -> bool:
	return _camera != null and _camera.is_position_in_frustum(n.global_position + Vector3.UP)

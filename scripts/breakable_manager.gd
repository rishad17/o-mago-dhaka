## Breakable street props: vegetable stalls, tea stalls, benches and bins.
##
## The rickshaw can ride on the footpath; riding into a prop smashes it.
## Vegetables, planks and bits fly off as cheap hand-animated debris, the
## shopkeeper shouts, the rickshaw slows and takes a little damage. Broken
## props are repaired after a while, when the player is far away.
extends Node3D

const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"
const PLAYER_HALF := Vector3(0.65, 0.95, 1.2)
const PLAYER_CENTER_Z := -0.24
const MIN_SPEED := 0.8          # m/s needed to knock something over
const REPAIR_AFTER := 45.0      # seconds
const REPAIR_DISTANCE := 45.0   # metres away from the player
const MAX_DEBRIS := 90
const CityLayoutRef := preload("res://scripts/city_layout.gd")
const SHOUTS := {
	"stall": ["হায় হায়! আমার দোকান!", "আমার সবজি!", "টাকা দিয়ে যান!", "ও মাগো!", "চোখে দেখেন না?"],
	"tea": ["আমার চায়ের দোকান!", "কেটলিটা গেল!", "ও মাগো!", "এইটা কী করলেন ভাই?"],
	"bench": ["আরে, বেঞ্চটা ভাঙলো!", "সরকারি জিনিস!", "আস্তে চালান!"],
}
const WORDS := {"stall": "চুরমার!", "tea": "ঝনঝন!", "bench": "মড়মড়!"}

@export var player_path: NodePath
@export var city_path: NodePath
@export var collisions_path: NodePath
@export var camera_path: NodePath
## Turned off by tests that need a clear footpath.
@export var enabled := true

var broken_count := 0

var _player: Node3D
var _city: Node
var _collisions: Node
var _camera: Node
var _font: Font
var _rng := RandomNumberGenerator.new()
var _debris: Array[Dictionary] = []
var _box_mesh: BoxMesh
var _ball_mesh: SphereMesh
var _materials := {}
var _broken_at := {}  # prop id -> time it broke
var _time := 0.0
var _check_timer := 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_city = get_node_or_null(city_path)
	_collisions = get_node_or_null(collisions_path)
	_camera = get_node_or_null(camera_path)
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	_rng.randomize()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(0.3, 0.06, 0.18)
	_ball_mesh = SphereMesh.new()
	_ball_mesh.radius = 0.12
	_ball_mesh.height = 0.24
	_ball_mesh.radial_segments = 6
	_ball_mesh.rings = 3


func _physics_process(delta: float) -> void:
	_time += delta
	_update_debris(delta)
	if _player == null or _city == null:
		return
	if enabled and absf(_player.speed) >= MIN_SPEED:
		_check_hits()
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 2.0
		_repair_props()


func _check_hits() -> void:
	var pxf := _player.global_transform.translated_local(Vector3(0, 0, PLAYER_CENTER_Z))
	var inv := pxf.affine_inverse()
	for rec in _city.props:
		if rec.broken:
			continue
		var c: Vector3 = rec.center
		if Vector2(c.x - pxf.origin.x, c.z - pxf.origin.z).length_squared() > 12.0:
			continue
		var local: Vector3 = inv * c
		var r: float = (rec.half.x + rec.half.z) * 0.5
		if absf(local.x) < PLAYER_HALF.x + r and absf(local.z) < PLAYER_HALF.z + r:
			break_prop(rec)


## Smashes a prop. Safe to call more than once (already broken = ignored).
func break_prop(rec: Dictionary) -> void:
	if rec.broken:
		return
	rec.broken = true
	_broken_at[rec.id] = _time
	broken_count += 1
	_city.rebuild_block_props(rec.block)
	var spd: float = absf(_player.speed) if _player else 3.0
	var pos: Vector3 = rec.center
	var push: Vector3 = (-_player.global_transform.basis.z) * signf(_player.speed if _player.speed != 0.0 else 1.0) if _player else Vector3.FORWARD
	_spawn_debris(rec, pos, push, spd)
	var kind: String = rec.kind
	_shout(pos, SHOUTS[kind][_rng.randi() % SHOUTS[kind].size()])
	if _collisions:
		_collisions.spawn_impact_effect(pos, 1 if spd > 3.0 else 0, false, WORDS[kind])
		_collisions.play_sound("crash" if kind != "bench" else "bump", -4.0 if kind != "bench" else -2.0, _rng.randf_range(0.9, 1.15))
	if _camera and _camera.has_method("add_shake"):
		_camera.add_shake(0.25)
	if _player:
		_player.speed *= 0.7  # it slows you down, but it doesn't stop you
		_player.react_to_crash(0)
	GameManager.on_prop_broken(kind, spd >= 2.0)


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_materials[key] = m
	return _materials[key]


func _spawn_debris(rec: Dictionary, pos: Vector3, push: Vector3, spd: float) -> void:
	var colors: Array = rec.colors if not rec.colors.is_empty() else [Color(0.5, 0.32, 0.16)]
	var count := 12 if rec.kind != "bench" else 7
	for i in count:
		if _debris.size() >= MAX_DEBRIS:
			var old: Dictionary = _debris.pop_front()
			old.node.queue_free()
		var mi := MeshInstance3D.new()
		var col: Color = colors[i % colors.size()]
		# Round bits for vegetables and cups, flat bits for planks and tin.
		mi.mesh = _ball_mesh if (rec.kind == "stall" and i % 3 != 0) else _box_mesh
		mi.material_override = _material(col)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = pos + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.0, 0.8), _rng.randf_range(-0.6, 0.6))
		var vel := push * spd * _rng.randf_range(0.4, 0.9) + Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(2.5, 5.0), _rng.randf_range(-2.0, 2.0))
		_debris.append({"node": mi, "vel": vel, "spin": Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9)), "life": _rng.randf_range(4.0, 6.0)})


func _update_debris(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		var node: Node3D = d.node
		d.life -= delta
		if d.life <= 0.0:
			node.queue_free()
			_debris.remove_at(i)
			continue
		if d.life < 0.6:
			node.scale = Vector3.ONE * maxf(d.life / 0.6, 0.01)
		var vel: Vector3 = d.vel
		if vel.length_squared() < 0.0001:
			continue
		vel.y -= 14.0 * delta
		var p := node.global_position + vel * delta
		var ground := 0.0 if CityLayoutRef.is_road(p.x, p.z) else 0.15
		if p.y < ground + 0.05:
			p.y = ground + 0.05
			vel = Vector3(vel.x * 0.55, -vel.y * 0.3, vel.z * 0.55)
			if vel.length() < 0.4:
				vel = Vector3.ZERO
			d.spin *= 0.5
		node.global_position = p
		node.rotation += d.spin * delta
		d.vel = vel


## The shopkeeper's shout, floating above the wreck for a few seconds.
func _shout(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	if _font:
		l.font = _font
	l.text = text
	l.font_size = 44
	l.pixel_size = 0.009
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 12
	l.outline_modulate = Color(0.1, 0.02, 0.02)
	l.modulate = Color(1, 0.9, 0.6)
	add_child(l)
	l.global_position = pos + Vector3(0, 2.4, 0)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


## Broken props come back after a while, when nobody is watching.
func _repair_props() -> void:
	if _player == null:
		return
	var dirty := {}
	for rec in _city.props:
		if not rec.broken or _time - _broken_at.get(rec.id, 0.0) < REPAIR_AFTER:
			continue
		var c: Vector3 = rec.center
		if Vector2(c.x - _player.global_position.x, c.z - _player.global_position.z).length() < REPAIR_DISTANCE:
			continue
		rec.broken = false
		dirty[rec.block] = true
	for b in dirty:
		_city.rebuild_block_props(b)

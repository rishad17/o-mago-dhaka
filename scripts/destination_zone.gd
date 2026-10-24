## One passenger drop-off zone on the road in front of a landmark.
##
## It is an Area3D that notices the player's rickshaw. The marker (a glowing
## ring, a light beam, a bobbing arrow and the Bangla name) is only shown while
## the zone is the active destination.
extends Area3D

const MeshKit := preload("res://scripts/mesh_kit.gd")
const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"
const PLAYER_LAYER := 2

signal player_entered(zone: Area3D)
signal player_exited(zone: Area3D)

## Bangla destination name, e.g. "নিউ মার্কেট".
var zone_name := ""
var radius := 5.0
## Spot on the sidewalk where passengers get off.
var sidewalk_point := Vector3.ZERO
var active := false
var player_inside := false

var _marker: Node3D
var _arrow: Node3D
var _time := 0.0


func setup(display_name: String, world_position: Vector3, zone_radius := 5.0) -> void:
	zone_name = display_name
	radius = zone_radius
	name = "Zone_" + display_name.replace(" ", "_")
	position = world_position
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 2.0, 0)
	add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_marker()
	set_active(false)


func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "Marker"
	add_child(_marker)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.no_depth_test = false

	var ring := MeshKit.new()
	ring.add_torus(Transform3D(Basis(), Vector3(0, 0.05, 0)), radius - 0.15, 0.15, Color(1.0, 0.85, 0.1, 0.95), 32, 4)
	var ring_mi := ring.build_instance("Ring")
	ring_mi.material_override = glow
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(ring_mi)

	var beam := MeshKit.new()
	beam.add_cylinder(Transform3D(Basis(), Vector3(0, 6.0, 0)), 0.6, 12.0, Color(1.0, 0.85, 0.2, 0.25), 12, false)
	var beam_mi := beam.build_instance("Beam")
	beam_mi.material_override = glow
	beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(beam_mi)

	_arrow = Node3D.new()
	_arrow.name = "Arrow"
	_arrow.position = Vector3(0, 4.0, 0)
	_marker.add_child(_arrow)
	var arrow := MeshKit.new()
	var col := Color(1.0, 0.3, 0.2, 1.0)
	# A downward-pointing four-sided arrow head plus a short shaft.
	var tip := Vector3(0, -0.9, 0)
	var corners := [Vector3(-0.6, 0, -0.6), Vector3(0.6, 0, -0.6), Vector3(0.6, 0, 0.6), Vector3(-0.6, 0, 0.6)]
	for i in 4:
		arrow.add_tri(tip, corners[(i + 1) % 4], corners[i], col)
	arrow.add_quad(corners[0], corners[1], corners[2], corners[3], col.darkened(0.2))
	arrow.add_box_at(Vector3(0, 0.5, 0), Vector3(0.45, 1.0, 0.45), col)
	var arrow_mi := arrow.build_instance("ArrowMesh")
	arrow_mi.material_override = glow
	_arrow.add_child(arrow_mi)

	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = zone_name
	if ResourceLoader.exists(FONT_PATH):
		label.font = load(FONT_PATH)
	label.font_size = 64
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 0.95, 0.5)
	label.outline_size = 14
	label.outline_modulate = Color(0.1, 0.05, 0.05)
	label.position = Vector3(0, 6.2, 0)
	_marker.add_child(label)


func set_active(on: bool) -> void:
	active = on
	if _marker:
		_marker.visible = on


func _process(delta: float) -> void:
	if not active:
		return
	_time += delta
	_arrow.position.y = 4.0 + sin(_time * 3.0) * 0.35
	_arrow.rotation.y += delta * 1.5


func _on_body_entered(_body: Node3D) -> void:
	player_inside = true
	player_entered.emit(self)


func _on_body_exited(_body: Node3D) -> void:
	player_inside = false
	player_exited.emit(self)

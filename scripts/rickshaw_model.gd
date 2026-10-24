## Procedurally built Bangladeshi pedal (cycle) rickshaw.
##
## Layout (local space, -Z is forward, Y is up, origin on the ground):
##   * one bicycle-style front wheel with fork + handlebar (steers)
##   * a bicycle front section: saddle, crank, pedals and chain
##   * two large rear wheels on an axle with decorated mudguards
##   * passenger footboard, seat box, cushion and painted backrest
##   * the curved, colourful hood (canopy) with fringe
##   * the painted tin backboard at the rear
##   * a simple driver whose legs follow the pedals and hands follow the bars
##
## Moving parts are separate nodes; everything else is merged into a single
## mesh with MeshKit to keep draw calls low.
extends Node3D

const MeshKit := preload("res://scripts/mesh_kit.gd")

const TEX_BACKBOARD := "res://assets/textures/rickshaw_backboard.png"
const TEX_CANOPY := "res://assets/textures/rickshaw_canopy.png"
const TEX_SEAT := "res://assets/textures/rickshaw_seat_back.png"
const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"

# Geometry (metres).
const REAR_Z := 0.55
const REAR_R := 0.36
const REAR_X := 0.57
const FRONT_Z := -1.05
const FRONT_R := 0.33
const CRANK_POS := Vector3(0, 0.36, -0.42)
const CRANK_ARM := 0.16
const PEDAL_X := 0.15
const HIP := Vector3(0.1, 1.1, -0.5)
const SHOULDER := Vector3(0.19, 1.58, -0.6)
const GRIP_IN_FORK := Vector3(0.35, 1.125, 0.24)
const THIGH_LEN := 0.46
const SHIN_LEN := 0.48
const UPPER_ARM_LEN := 0.31
const FOREARM_LEN := 0.3
const HOOD_CENTER := Vector2(0.06, 0.93)  # (z, y) of the hood ellipse centre
const HOOD_RADII := Vector2(0.78, 1.02)   # (z, y) radii
const HOOD_MAX_ANGLE := 1.9

# Palette.
const TIRE := Color(0.07, 0.07, 0.08)
const METAL := Color(0.72, 0.74, 0.78)
const DARK_METAL := Color(0.25, 0.26, 0.28)
const FRAME := Color(0.05, 0.42, 0.28)
const RED := Color(0.86, 0.1, 0.14)
const YELLOW := Color(1.0, 0.8, 0.08)
const GREEN := Color(0.1, 0.62, 0.25)
const BLUE := Color(0.12, 0.35, 0.88)
const ORANGE := Color(1.0, 0.5, 0.08)
const PINK := Color(0.96, 0.3, 0.6)
const WHITE := Color(0.95, 0.95, 0.92)
const WOOD := Color(0.5, 0.32, 0.16)
const SKIN := Color(0.5, 0.31, 0.2)
const HAIR := Color(0.05, 0.04, 0.04)
const SHIRT := Color(0.93, 0.93, 0.88)
const LUNGI := Color(0.16, 0.36, 0.7)
const GAMCHHA := Color(0.9, 0.25, 0.15)

## Show the rickshaw puller.
@export var driver_visible := true
## Animate legs (pedalling) and arms (steering). Turn off for distant AI rickshaws.
@export var animate_driver := true
## Main paint colour of the seat box and mudguards.
@export var body_paint := Color(0.1, 0.62, 0.25)
## Accent colour of the mudguards.
@export var guard_paint := Color(0.12, 0.35, 0.88)
## Text painted under the backboard.
@export var backboard_text := "মায়ের দোয়া"

var _rear_wheels: Node3D
var _fork: Node3D
var _front_wheel: Node3D
var _crank: Node3D
var _limbs := {}  # name -> MeshInstance3D
var _crank_angle := 0.0
var _lod: MeshInstance3D
var _detail: Array[Node3D] = []
var _detail_parents: Array[Node] = []
var _far := false
var _dizzy: Node3D
var _dizzy_time := 0.0
var _wobble_phase := 0.0

## Front wheel wobble (radians) for a battered rickshaw; set by the player.
var damage_wobble := 0.0

## Where a passenger sits (used by the passenger system).
var passenger_seat: Marker3D


func _ready() -> void:
	_build()
	update_motion(0.0, 0.0, false, 0.0)


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("Rickshaw texture missing: %s (using plain colour)" % path)
	return null


## Meshes are cached per paint scheme, so many AI rickshaws share them.
static var _mesh_cache := {}


func _build_meshes() -> Dictionary:
	var key := "%s|%s|%s" % [body_paint.to_html(), guard_paint.to_html(), driver_visible]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var meshes := {}
	var body := MeshKit.new()
	_build_frame(body)
	_build_passenger_section(body)
	_build_hood(body)
	_build_rear(body)
	if driver_visible:
		_build_driver_static(body)
	meshes.body = body.build()
	var rw := MeshKit.new()
	for side: float in [-1.0, 1.0]:
		_build_wheel(rw, Vector3(side * REAR_X, 0, 0), REAR_R, 0.08, true)
	rw.add_rod(Vector3(-REAR_X, 0, 0), Vector3(REAR_X, 0, 0), 0.02, DARK_METAL)
	meshes.rear = rw.build()
	var fk := MeshKit.new()
	_build_fork(fk)
	meshes.fork = fk.build()
	var fw := MeshKit.new()
	_build_wheel(fw, Vector3.ZERO, FRONT_R, 0.1, false)
	meshes.front = fw.build()
	var ck := MeshKit.new()
	_build_crank(ck)
	meshes.crank = ck.build()
	if driver_visible:
		meshes.limbs = _build_limb_meshes()
	meshes.lod = _build_lod_mesh(meshes)
	_mesh_cache[key] = meshes
	return meshes


## One merged mesh of the whole rickshaw in a resting pose, used far away
## (a handful of draw calls instead of about seventeen).
func _build_lod_mesh(meshes: Dictionary) -> ArrayMesh:
	var lod := MeshKit.new()
	lod.add_mesh(meshes.body, Transform3D())
	lod.add_mesh(meshes.rear, Transform3D(Basis(), Vector3(0, REAR_R, REAR_Z)))
	lod.add_mesh(meshes.fork, Transform3D(Basis(), Vector3(0, 0, FRONT_Z)))
	lod.add_mesh(meshes.front, Transform3D(Basis(), Vector3(0, FRONT_R, FRONT_Z)))
	lod.add_mesh(meshes.crank, Transform3D(Basis(), CRANK_POS))
	if driver_visible:
		var limbs: Dictionary = meshes.limbs
		for side: float in [-1.0, 1.0]:
			var pedal := CRANK_POS + Vector3(side * PEDAL_X, 0, 0) + Vector3(0, CRANK_ARM, 0) * side
			var hip := Vector3(HIP.x * side, HIP.y, HIP.z)
			var foot := pedal + Vector3(0, 0.04, 0)
			var knee := _solve_joint(hip, foot, THIGH_LEN, SHIN_LEN, Vector3(0, 0.4, -1))
			lod.add_mesh(limbs.Thigh, _limb_transform(hip, knee))
			lod.add_mesh(limbs.Shin, _limb_transform(knee, foot))
			var grip := Vector3(GRIP_IN_FORK.x * side, GRIP_IN_FORK.y, GRIP_IN_FORK.z + FRONT_Z)
			var shoulder := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
			var elbow := _solve_joint(shoulder, grip, UPPER_ARM_LEN, FOREARM_LEN, Vector3(side, -0.3, 0.7))
			lod.add_mesh(limbs.UpperArm, _limb_transform(shoulder, elbow))
			lod.add_mesh(limbs.Forearm, _limb_transform(elbow, grip))
	return lod.build()


func _mesh_node(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	return mi


func _build() -> void:
	var meshes := _build_meshes()
	add_child(_mesh_node("Body", meshes.body))

	_rear_wheels = Node3D.new()
	_rear_wheels.name = "RearWheels"
	_rear_wheels.position = Vector3(0, REAR_R, REAR_Z)
	add_child(_rear_wheels)
	_rear_wheels.add_child(_mesh_node("Mesh", meshes.rear))

	_fork = Node3D.new()
	_fork.name = "Fork"
	_fork.position = Vector3(0, 0, FRONT_Z)
	add_child(_fork)
	_fork.add_child(_mesh_node("Mesh", meshes.fork))

	_front_wheel = Node3D.new()
	_front_wheel.name = "FrontWheel"
	_front_wheel.position = Vector3(0, FRONT_R, 0)
	_fork.add_child(_front_wheel)
	_front_wheel.add_child(_mesh_node("Mesh", meshes.front))

	_crank = Node3D.new()
	_crank.name = "Crank"
	_crank.position = CRANK_POS
	add_child(_crank)
	_crank.add_child(_mesh_node("Mesh", meshes.crank))

	if driver_visible:
		_build_limbs(meshes.limbs)
	_lod = _mesh_node("LOD", meshes.lod)
	_lod.visible = false
	add_child(_lod)
	_detail = [get_node("Body"), _rear_wheels, _fork, _crank]
	for limb in _limbs.values():
		_detail.append(limb)
	for n in _detail:
		_detail_parents.append(n.get_parent())

	if driver_visible:
		# Cartoon stars that circle the puller's head after a heavy crash.
		_dizzy = Node3D.new()
		_dizzy.name = "Dizzy"
		_dizzy.position = Vector3(0, 2.08, -0.62)
		_dizzy.visible = false
		var stars := MeshKit.new()
		for k in 5:
			var a := TAU * k / 5.0
			var c := Vector3(cos(a) * 0.28, 0.0, sin(a) * 0.28)
			stars.add_box(Transform3D(Basis(Vector3.UP, a), c), Vector3(0.11, 0.11, 0.03), YELLOW)
			stars.add_box(Transform3D(Basis(Vector3.BACK, PI * 0.25) * Basis(Vector3.UP, a), c), Vector3(0.11, 0.11, 0.03), YELLOW)
		_dizzy.add_child(stars.build_instance("Stars"))
		add_child(_dizzy)

	passenger_seat = Marker3D.new()
	passenger_seat.name = "PassengerSeat"
	passenger_seat.position = Vector3(0, 0.91, 0.42)
	add_child(passenger_seat)

	_add_backboard_label()


# --- Parts -----------------------------------------------------------------

func _build_wheel(kit, center: Vector3, radius: float, hub_width: float, beads: bool) -> void:
	var axis := Basis(Vector3.BACK, PI * 0.5)  # local Y -> X, so the wheel spins about X
	kit.add_torus(Transform3D(axis, center), radius - 0.035, 0.035, TIRE, 18, 5)
	kit.add_torus(Transform3D(axis, center), radius - 0.075, 0.012, METAL, 18, 3)
	kit.add_cylinder(Transform3D(axis, center), 0.045, hub_width, METAL, 8)
	var spokes := 14
	var rim := radius - 0.075
	for i in spokes:
		var a := TAU * i / spokes
		var side := 1.0 if i % 2 == 0 else -1.0
		var hub := center + Vector3(side * hub_width * 0.4, 0, 0)
		var tip := center + Vector3(0, cos(a) * rim, sin(a) * rim)
		kit.add_bar(hub, tip, 0.008, METAL)
		if beads:
			# Colourful plastic spoke beads, a common rickshaw decoration.
			var bead_col: Color = [RED, YELLOW, GREEN, PINK][i % 4]
			kit.add_box_at(hub.lerp(tip, 0.6), Vector3(0.025, 0.025, 0.025), bead_col)


func _arc_band(kit, center: Vector3, radius: float, width: float,
		from_angle: float, to_angle: float, color: Color, segments := 9) -> void:
	# A curved strip around the X axis; angle 0 is straight up, positive goes backwards.
	var step := (to_angle - from_angle) / segments
	var seg_len := radius * absf(step) * 1.08
	for i in segments:
		var a := from_angle + step * (i + 0.5)
		var basis := Basis(Vector3.RIGHT, a)
		var pos := center + basis * Vector3(0, radius, 0)
		kit.add_box(Transform3D(basis, pos), Vector3(width, 0.014, seg_len), color)


func _build_fork(kit) -> void:
	for side: float in [-1.0, 1.0]:
		kit.add_rod(Vector3(side * 0.06, FRONT_R, 0), Vector3(side * 0.045, 0.8, 0.045), 0.017, FRAME)
	kit.add_box_at(Vector3(0, 0.81, 0.045), Vector3(0.16, 0.05, 0.06), FRAME)
	kit.add_rod(Vector3(0, 0.8, 0.045), Vector3(0, 1.06, 0.08), 0.022, FRAME)
	kit.add_rod(Vector3(0, 1.06, 0.08), Vector3(0, 1.1, 0.12), 0.02, METAL)
	kit.add_rod(Vector3(-0.3, 1.1, 0.12), Vector3(0.3, 1.1, 0.12), 0.016, METAL)
	for side: float in [-1.0, 1.0]:
		kit.add_rod(Vector3(side * 0.3, 1.1, 0.12), Vector3(side * 0.34, 1.12, 0.19), 0.016, METAL)
		kit.add_rod(Vector3(side * 0.34, 1.12, 0.19), Vector3(side * 0.36, 1.13, 0.3), 0.024, HAIR)
		# Plastic tassels hanging from the bars.
		kit.add_box_at(Vector3(side * 0.27, 1.02, 0.12), Vector3(0.03, 0.16, 0.03), PINK)
		kit.add_box_at(Vector3(side * 0.23, 1.03, 0.12), Vector3(0.03, 0.13, 0.03), YELLOW)
	# The famous thumb bell.
	kit.add_cylinder(Transform3D(Basis(), Vector3(0.17, 1.14, 0.12)), 0.035, 0.03, Color(0.9, 0.85, 0.5), 10)
	# Decorative plastic flower in the middle of the bar.
	kit.add_sphere(Transform3D(Basis().scaled(Vector3(1, 1, 0.5)), Vector3(0, 1.16, 0.1)), 0.05, RED, 3, 8)
	kit.add_sphere(Transform3D(Basis(), Vector3(0, 1.16, 0.08)), 0.025, YELLOW, 3, 6)
	# Front mudguard.
	_arc_band(kit, Vector3(0, FRONT_R, 0), FRONT_R + 0.05, 0.09, -0.6, 1.5, RED, 8)


func _build_crank(kit) -> void:
	var axis := Basis(Vector3.BACK, PI * 0.5)
	kit.add_cylinder(Transform3D(axis, Vector3(0.07, 0, 0)), 0.1, 0.012, METAL, 14)
	kit.add_rod(Vector3(-0.1, 0, 0), Vector3(0.1, 0, 0), 0.015, DARK_METAL)
	kit.add_bar(Vector3(0.1, 0, 0), Vector3(0.1, CRANK_ARM, 0), 0.025, DARK_METAL)
	kit.add_bar(Vector3(-0.1, 0, 0), Vector3(-0.1, -CRANK_ARM, 0), 0.025, DARK_METAL)
	kit.add_box_at(Vector3(PEDAL_X, CRANK_ARM, 0), Vector3(0.09, 0.025, 0.06), HAIR)
	kit.add_box_at(Vector3(-PEDAL_X, -CRANK_ARM, 0), Vector3(0.09, 0.025, 0.06), HAIR)


func _build_frame(kit) -> void:
	# Bicycle-like front section.
	kit.add_rod(Vector3(0, 0.78, -1.01), Vector3(0, 1.05, -0.97), 0.03, FRAME)
	kit.add_rod(Vector3(0, 0.98, -0.98), Vector3(0, 0.95, -0.55), 0.022, FRAME)
	kit.add_rod(Vector3(0, 0.82, -1.0), CRANK_POS + Vector3(0, 0.02, 0), 0.025, FRAME)
	kit.add_rod(CRANK_POS, Vector3(0, 1.0, -0.52), 0.022, FRAME)
	# Saddle with springs.
	kit.add_box_at(Vector3(0, 1.05, -0.5), Vector3(0.2, 0.07, 0.28), Color(0.25, 0.13, 0.07))
	for side: float in [-1.0, 1.0]:
		kit.add_rod(Vector3(side * 0.05, 1.0, -0.42), Vector3(side * 0.05, 1.03, -0.42), 0.02, METAL)
	# Bottom bracket shell.
	kit.add_cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), CRANK_POS), 0.035, 0.08, FRAME, 8)
	# Beam to the passenger section and footboard supports.
	kit.add_rod(CRANK_POS, Vector3(0, 0.45, -0.28), 0.025, FRAME)
	for side: float in [-1.0, 1.0]:
		kit.add_rod(Vector3(0, 0.42, -0.34), Vector3(side * 0.38, 0.45, -0.25), 0.018, FRAME)
		kit.add_rod(Vector3(side * 0.38, 0.45, -0.25), Vector3(side * 0.45, 0.5, 0.2), 0.018, FRAME)
	# Chain from the crank to the rear axle sprocket (on the right side).
	var front_top := CRANK_POS + Vector3(0.07, 0.1, 0)
	var front_bot := CRANK_POS + Vector3(0.07, -0.1, 0)
	var rear_c := Vector3(0.07, REAR_R, REAR_Z)
	kit.add_bar(front_top, rear_c + Vector3(0, 0.06, 0), 0.018, DARK_METAL)
	kit.add_bar(front_bot, rear_c + Vector3(0, -0.06, 0), 0.018, DARK_METAL)
	kit.add_cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), rear_c), 0.065, 0.012, METAL, 10)


func _build_passenger_section(kit) -> void:
	# Wooden footboard with a painted front lip.
	kit.add_box_at(Vector3(0, 0.47, -0.06), Vector3(0.8, 0.04, 0.46), WOOD)
	kit.add_box_at(Vector3(0, 0.5, -0.3), Vector3(0.82, 0.08, 0.02), YELLOW)
	for i in 6:
		var col: Color = [RED, GREEN, BLUE][i % 3]
		kit.add_box_at(Vector3(-0.33 + i * 0.132, 0.5, -0.312), Vector3(0.05, 0.05, 0.01), col)
	# Seat box, painted, with a yellow trim and decorative squares.
	kit.add_box_at(Vector3(0, 0.66, 0.42), Vector3(1.0, 0.32, 0.54), body_paint)
	kit.add_box_at(Vector3(0, 0.81, 0.42), Vector3(1.02, 0.025, 0.56), YELLOW)
	kit.add_box_at(Vector3(0, 0.51, 0.42), Vector3(1.02, 0.025, 0.56), YELLOW)
	for i in 7:
		var col: Color = [RED, YELLOW, PINK, ORANGE][i % 4]
		kit.add_box_at(Vector3(-0.42 + i * 0.14, 0.66, 0.148), Vector3(0.08, 0.08, 0.01), col)
		kit.add_box_at(Vector3(-0.42 + i * 0.14, 0.66, 0.148), Vector3(0.03, 0.03, 0.02), WHITE)
	for side: float in [-1.0, 1.0]:
		kit.add_box_at(Vector3(side * 0.505, 0.66, 0.42), Vector3(0.012, 0.2, 0.4), [RED, ORANGE][int(side > 0)])
	# Cushion with white piping.
	kit.add_box_at(Vector3(0, 0.865, 0.4), Vector3(1.04, 0.1, 0.5), RED)
	kit.add_box_at(Vector3(0, 0.865, 0.148), Vector3(1.05, 0.02, 0.012), WHITE)
	kit.add_box_at(Vector3(0, 0.915, 0.4), Vector3(1.05, 0.012, 0.02), WHITE)
	# Backrest: painted art panel facing the passenger.
	# Kept inside the hood: the hood's back is at z~0.75 at this height.
	var bl := Vector3(0, 0.91, 0.62)
	var tl := Vector3(0, 1.42, 0.68)
	kit.add_beam(bl + Vector3(0, 0, 0.03), tl + Vector3(0, 0, 0.03), 1.06, 0.03, body_paint)
	var seat_tex := _load_texture(TEX_SEAT)
	var w := 0.5
	kit.add_quad_uv(
		Vector3(w, bl.y, bl.z), Vector3(-w, bl.y, bl.z), Vector3(-w, tl.y, tl.z), Vector3(w, tl.y, tl.z),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), seat_tex)
	for side: float in [-1.0, 1.0]:
		kit.add_bar(Vector3(side * 0.52, bl.y, bl.z + 0.01), Vector3(side * 0.52, tl.y, tl.z + 0.01), 0.035, YELLOW)
		# Side rails / armrests.
		kit.add_rod(Vector3(side * 0.53, 0.98, 0.2), Vector3(side * 0.53, 0.98, 0.66), 0.014, METAL)
		kit.add_rod(Vector3(side * 0.53, 0.9, 0.2), Vector3(side * 0.53, 0.98, 0.2), 0.014, METAL)
	kit.add_bar(Vector3(-0.52, tl.y + 0.01, tl.z + 0.01), Vector3(0.52, tl.y + 0.01, tl.z + 0.01), 0.035, YELLOW)


func _hood_point(theta: float, side: float) -> Vector3:
	var half_w := 0.63 + 0.05 * cos(theta)
	return Vector3(side * half_w,
		HOOD_CENTER.y + HOOD_RADII.y * sin(theta),
		HOOD_CENTER.x + HOOD_RADII.x * cos(theta))


func _build_hood(kit) -> void:
	var tex := _load_texture(TEX_CANOPY)
	var segs := 12
	var inner_col := Color(0.14, 0.06, 0.1)
	for i in segs:
		var t0 := HOOD_MAX_ANGLE * i / segs
		var t1 := HOOD_MAX_ANGLE * (i + 1) / segs
		var v0 := float(i) / segs
		var v1 := float(i + 1) / segs
		var p0 := _hood_point(t0, -1)
		var p1 := _hood_point(t0, 1)
		var p2 := _hood_point(t1, 1)
		var p3 := _hood_point(t1, -1)
		kit.add_quad_uv(p0, p1, p2, p3, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), tex)
		# Inside of the hood (reverse winding, slightly smaller).
		var c := Vector3(0, HOOD_CENTER.y, HOOD_CENTER.x)
		kit.add_quad(c + (p0 - c) * 0.985, c + (p3 - c) * 0.985, c + (p2 - c) * 0.985, c + (p1 - c) * 0.985, inner_col)
		# Ribs along both edges.
		for side: float in [-1.0, 1.0]:
			kit.add_bar(_hood_point(t0, side), _hood_point(t1, side), 0.03, Color(0.15, 0.1, 0.1))
	# Side flaps at the back part of the hood.
	var flap_segs := 6
	var flap_max := 1.3
	for side: float in [-1.0, 1.0]:
		for i in flap_segs:
			var t0 := flap_max * i / flap_segs
			var t1 := flap_max * (i + 1) / flap_segs
			var a := _hood_point(t0, side)
			var b := _hood_point(t1, side)
			var hub := Vector3(a.x, HOOD_CENTER.y + 0.08, HOOD_CENTER.x + 0.28)
			var col := Color(0.62, 0.05, 0.12) if i % 2 == 0 else Color(0.75, 0.1, 0.18)
			kit.add_tri(hub, a, b, col)
			kit.add_tri(hub, b, a, col)
		# Folding struts down to the seat.
		kit.add_rod(_hood_point(0.95, side), Vector3(side * 0.53, 0.98, 0.32), 0.013, METAL)
		kit.add_rod(_hood_point(0.0, side), Vector3(side * 0.52, 0.84, 0.66), 0.016, METAL)
	# Front edge trim and the colourful fringe.
	var fl := _hood_point(HOOD_MAX_ANGLE, -1)
	var fr := _hood_point(HOOD_MAX_ANGLE, 1)
	kit.add_rod(fl, fr, 0.022, YELLOW)
	var tassels := 15
	for i in tassels:
		var p := fl.lerp(fr, (i + 0.5) / tassels)
		var col: Color = [RED, YELLOW, GREEN, BLUE, PINK][i % 5]
		kit.add_box_at(p + Vector3(0, -0.07, 0), Vector3(0.035, 0.12, 0.012), col)
		kit.add_box_at(p + Vector3(0, -0.14, 0), Vector3(0.03, 0.03, 0.03), WHITE)


func _build_rear(kit) -> void:
	# Painted tin backboard between the rear wheels.
	var tex := _load_texture(TEX_BACKBOARD)
	var z := 0.72
	kit.add_box_at(Vector3(0, 0.49, z - 0.015), Vector3(0.98, 0.44, 0.02), RED)
	kit.add_quad_uv(
		Vector3(-0.46, 0.3, z), Vector3(0.46, 0.3, z), Vector3(0.46, 0.68, z), Vector3(-0.46, 0.68, z),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), tex)
	# Strip for the painted slogan, reflectors and hanging supports.
	kit.add_box_at(Vector3(0, 0.215, z - 0.005), Vector3(0.92, 0.11, 0.02), YELLOW)
	for side: float in [-1.0, 1.0]:
		kit.add_box_at(Vector3(side * 0.44, 0.215, z + 0.008), Vector3(0.05, 0.05, 0.01), RED)
		kit.add_rod(Vector3(side * 0.45, 0.7, z - 0.02), Vector3(side * 0.45, 0.82, 0.66), 0.012, METAL)
		kit.add_rod(Vector3(side * 0.47, 0.16, z - 0.02), Vector3(side * 0.47, 0.71, z - 0.02), 0.012, METAL)
	# Decorated mudguards and mudflaps over the rear wheels.
	for side: float in [-1.0, 1.0]:
		var c := Vector3(side * REAR_X, REAR_R, REAR_Z)
		_arc_band(kit, c, REAR_R + 0.05, 0.14, -0.5, 2.2, guard_paint, 10)
		_arc_band(kit, c + Vector3(side * 0.071, 0, 0), REAR_R + 0.05, 0.012, -0.5, 2.2, RED, 10)
		var flap := Vector3(side * REAR_X, 0.2, REAR_Z + REAR_R + 0.05)
		kit.add_box_at(flap, Vector3(0.14, 0.22, 0.012), RED)
		for k in 3:
			kit.add_box_at(flap + Vector3(-0.04 + k * 0.04, 0.02, 0.008), Vector3(0.022, 0.022, 0.01), WHITE)
			kit.add_box_at(flap + Vector3(-0.045 + k * 0.045, -0.14, 0), Vector3(0.02, 0.06, 0.02), YELLOW)
		# Struts from the seat box to the axle.
		kit.add_rod(Vector3(side * 0.42, 0.52, 0.5), Vector3(side * 0.42, REAR_R, REAR_Z), 0.02, FRAME)


func _build_driver_static(kit) -> void:
	# Lungi folded up around the hips.
	kit.add_box_at(Vector3(0, 1.12, -0.5), Vector3(0.34, 0.18, 0.3), LUNGI)
	kit.add_box_at(Vector3(0, 1.12, -0.5), Vector3(0.35, 0.03, 0.31), Color(0.85, 0.85, 0.9))
	# Torso in a white vest, leaning slightly forward.
	kit.add_beam(Vector3(0, 1.16, -0.5), Vector3(0, 1.6, -0.6), 0.36, 0.2, SHIRT)
	# Gamchha (checked towel) around the neck.
	kit.add_box_at(Vector3(0, 1.6, -0.58), Vector3(0.3, 0.06, 0.24), GAMCHHA)
	kit.add_beam(Vector3(0.1, 1.6, -0.48), Vector3(0.12, 1.36, -0.46), 0.08, 0.02, GAMCHHA)
	kit.add_rod(Vector3(0, 1.6, -0.6), Vector3(0, 1.7, -0.63), 0.05, SKIN)
	kit.add_sphere(Transform3D(Basis().scaled(Vector3(1, 1.1, 1)), Vector3(0, 1.79, -0.64)), 0.115, SKIN, 5, 8)
	kit.add_sphere(Transform3D(Basis().scaled(Vector3(1.04, 0.75, 1.06)), Vector3(0, 1.84, -0.625)), 0.12, HAIR, 4, 8)


func _make_limb_mesh(width: float, depth: float, color: Color) -> ArrayMesh:
	var kit := MeshKit.new()
	kit.add_box_at(Vector3(0, 0.5, 0), Vector3(width, 1.0, depth), color)
	return kit.build()


func _build_limb_meshes() -> Dictionary:
	var foot_kit := MeshKit.new()
	foot_kit.add_box_at(Vector3(0, 0.02, -0.03), Vector3(0.09, 0.04, 0.2), Color(0.3, 0.18, 0.1))
	var hand_kit := MeshKit.new()
	hand_kit.add_box_at(Vector3.ZERO, Vector3(0.07, 0.07, 0.09), SKIN)
	var arm := _make_limb_mesh(0.075, 0.075, SKIN)
	return {
		"Thigh": _make_limb_mesh(0.13, 0.13, LUNGI),
		"Shin": _make_limb_mesh(0.085, 0.085, SKIN),
		"UpperArm": arm,
		"Forearm": arm,
		"Foot": foot_kit.build(),
		"Hand": hand_kit.build(),
	}


func _build_limbs(limb_meshes: Dictionary) -> void:
	for side_name in ["L", "R"]:
		for part in limb_meshes:
			var mi := _mesh_node(part + side_name, limb_meshes[part])
			add_child(mi)
			_limbs[mi.name] = mi


## Shows dizzy stars over the puller's head for a while.
func show_dizzy(seconds: float) -> void:
	_dizzy_time = seconds


## Switches between the detailed, animated model and the single merged
## low-detail mesh (for rickshaws far from the camera).
func set_far(far: bool) -> void:
	if far == _far or _lod == null:
		return
	_far = far
	_lod.visible = far
	# Detached rather than hidden while far: hidden nodes would still be
	# updated every physics tick as the rickshaw moves.
	for i in _detail.size():
		var n: Node3D = _detail[i]
		if far:
			_detail_parents[i].remove_child(n)
		else:
			_detail_parents[i].add_child(n)
			n.reset_physics_interpolation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in _detail:
			if is_instance_valid(n) and n.get_parent() == null:
				n.free()


# --- Animation ---------------------------------------------------------------

## Called every frame by the vehicle controller.
## speed: forward speed in m/s (negative when reversing)
## steer: front fork angle in radians (positive = left)
## pedaling: whether the puller is pushing the pedals
func update_motion(speed: float, steer: float, pedaling: bool, delta: float) -> void:
	if _rear_wheels == null:
		return
	_rear_wheels.rotate_x(-speed / REAR_R * delta)
	_front_wheel.rotate_x(-speed / FRONT_R * delta)
	_wobble_phase += speed / FRONT_R * delta
	_fork.rotation.y = steer + sin(_wobble_phase) * damage_wobble * clampf(absf(speed), 0.0, 1.0)
	if _dizzy:
		_dizzy_time = maxf(_dizzy_time - delta, 0.0)
		_dizzy.visible = _dizzy_time > 0.0
		if _dizzy.visible:
			_dizzy.rotation.y += delta * 5.0
	if pedaling:
		_crank_angle = wrapf(_crank_angle - speed / REAR_R * 0.55 * delta, -PI, PI)
	_crank.rotation.x = _crank_angle
	if driver_visible and animate_driver:
		_update_driver()


func _update_driver() -> void:
	for side: float in [-1.0, 1.0]:
		var s := "R" if side > 0 else "L"
		# Legs follow the pedals.
		var arm_dir := Vector3(0, cos(_crank_angle), sin(_crank_angle)) * CRANK_ARM * side
		var pedal := CRANK_POS + Vector3(side * PEDAL_X, 0, 0) + arm_dir
		var hip := Vector3(HIP.x * side, HIP.y, HIP.z)
		var foot_target := pedal + Vector3(0, 0.04, 0)
		var knee := _solve_joint(hip, foot_target, THIGH_LEN, SHIN_LEN, Vector3(0, 0.4, -1))
		_place_limb(_limbs["Thigh" + s], hip, knee)
		_place_limb(_limbs["Shin" + s], knee, foot_target)
		_limbs["Foot" + s].position = foot_target - Vector3(0, 0.03, 0)
		# Hands stay on the handlebar grips while steering.
		var grip := _fork.transform * Vector3(GRIP_IN_FORK.x * side, GRIP_IN_FORK.y, GRIP_IN_FORK.z)
		var shoulder := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
		var elbow := _solve_joint(shoulder, grip, UPPER_ARM_LEN, FOREARM_LEN, Vector3(side, -0.3, 0.7))
		_place_limb(_limbs["UpperArm" + s], shoulder, elbow)
		_place_limb(_limbs["Forearm" + s], elbow, grip)
		_limbs["Hand" + s].position = grip


## Two-bone IK: returns the middle joint (knee/elbow) position.
func _solve_joint(root: Vector3, target: Vector3, len_a: float, len_b: float, pole: Vector3) -> Vector3:
	var to_target := target - root
	var dist := clampf(to_target.length(), 0.01, len_a + len_b - 0.001)
	var dir := to_target.normalized()
	var a := (len_a * len_a - len_b * len_b + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(len_a * len_a - a * a, 0.0))
	var bend := (pole - dir * pole.dot(dir)).normalized()
	return root + dir * a + bend * h


func _place_limb(limb: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) >= 0.001:
		limb.transform = _limb_transform(from, to)


## Transform that stretches a unit-length limb mesh from `from` to `to`.
func _limb_transform(from: Vector3, to: Vector3) -> Transform3D:
	var v := to - from
	var b := MeshKit.basis_along(v)
	return Transform3D(Basis(b.x, b.y * maxf(v.length(), 0.001), b.z), from)


func _add_backboard_label() -> void:
	if backboard_text == "":
		return
	var label := Label3D.new()
	label.name = "BackboardText"
	label.text = backboard_text
	if ResourceLoader.exists(FONT_PATH):
		label.font = load(FONT_PATH)
	label.font_size = 40
	label.pixel_size = 0.0022
	label.modulate = Color(0.75, 0.05, 0.1)
	label.outline_size = 0
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = Vector3(0, 0.215, 0.735)
	label.visibility_range_end = 25.0
	add_child(label)

## Low-poly Bangladeshi pedestrian with simple procedural animation.
##
## Styles: man in lungi, man in shirt and trousers, man in panjabi and tupi,
## student with backpack, woman in saree, woman in salwar kameez with orna,
## woman in borka, and an old man with a white beard. Meshes are cached per
## variant. Local space: feet on the ground at y = 0, facing -Z.
##
## Poses: WALK (legs and arms swing with `speed`), STAND, WAVE (calling a
## rickshaw), SIT (on the rickshaw seat) and FALLEN (knocked down, with
## cartoon stars).
extends Node3D

const MeshKit := preload("res://scripts/mesh_kit.gd")

enum Pose { WALK, STAND, WAVE, SIT, FALLEN }

const HIP_Y := 0.86
const SHOULDER_Y := 1.4
const THIGH := 0.43
const SHIN := 0.43
const ARM := 0.58
const STYLE_COUNT := 8
## Special look for a mugger (ছিনতাইকারী): dark shirt and trousers, black cap.
const MUGGER_VARIANT := 64
const SKIN_TONES := [Color(0.55, 0.36, 0.24), Color(0.45, 0.29, 0.19), Color(0.62, 0.42, 0.3)]
const BRIGHT := [Color(0.85, 0.15, 0.2), Color(0.1, 0.5, 0.3), Color(0.15, 0.35, 0.8), Color(0.95, 0.6, 0.1),
	Color(0.6, 0.15, 0.55), Color(0.95, 0.85, 0.2), Color(0.1, 0.6, 0.65), Color(0.9, 0.4, 0.55)]
const MUTED := [Color(0.92, 0.92, 0.88), Color(0.55, 0.62, 0.75), Color(0.6, 0.55, 0.45), Color(0.3, 0.35, 0.45)]
const HAIR := Color(0.05, 0.04, 0.04)

static var _cache := {}
## Frames in the low-detail walk cycle.
const WALK_FRAMES := 8

## Appearance variant (style = variant % 8).
@export var variant := 0
var pose: Pose = Pose.STAND
## Walking speed in m/s; drives the leg cycle.
var speed := 0.0
## Turn limb animation off for far-away people.
var animate := true

var _hips: Node3D
var _thigh := [null, null]
var _shin := [null, null]
var _arm := [null, null]
var _stars: Node3D
var _phase := 0.0
var _time := 0.0
var _fall := 0.0
var _lod: MeshInstance3D
var _far := false
var _lod_frame := -1


func _ready() -> void:
	var m := _meshes(variant)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	_hips.add_child(_mi(m.body))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var thigh := Node3D.new()
		thigh.position = Vector3(side * 0.09, 0, 0)
		_hips.add_child(thigh)
		thigh.add_child(_mi(m.thigh))
		var shin := Node3D.new()
		shin.position = Vector3(0, -THIGH, 0)
		thigh.add_child(shin)
		shin.add_child(_mi(m.shin))
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.21, SHOULDER_Y - HIP_Y - 0.02, 0)
		_hips.add_child(arm)
		arm.add_child(_mi(m.arm))
		_thigh[i] = thigh
		_shin[i] = shin
		_arm[i] = arm
	_stars = Node3D.new()
	_stars.name = "Stars"
	_stars.visible = false
	# Spun every frame in _process, not by physics.
	_stars.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_hips.add_child(_stars)
	_stars.add_child(_mi(m.stars))
	_lod = _mi(m.lod)
	_lod.visible = false
	add_child(_lod)
	_apply_pose(0.0)


## Far away: show one merged standing mesh instead of the jointed body.
func set_far(far: bool) -> void:
	if far == _far:
		return
	_far = far
	_lod.visible = far
	# Take the jointed body out of the scene while far away, so moving the
	# person doesn't update its dozen hidden nodes every physics tick.
	if far:
		remove_child(_hips)
	else:
		add_child(_hips)
		_hips.reset_physics_interpolation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _hips and _hips.get_parent() == null:
		_hips.free()


func _mi(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = 70.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Puts a knife in the right hand (for muggers). Raised in the WAVE pose.
func add_knife() -> void:
	var kit := MeshKit.new()
	var hand := Vector3(0, -ARM - 0.04, 0)
	kit.add_box_at(hand + Vector3(0, 0, -0.04), Vector3(0.035, 0.035, 0.11), Color(0.2, 0.12, 0.06))
	kit.add_box_at(hand + Vector3(0, 0, -0.2), Vector3(0.012, 0.04, 0.22), Color(0.85, 0.87, 0.9))
	var mi := kit.build_instance("Knife")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arm[1].add_child(mi)


func set_pose(p: Pose) -> void:
	pose = p


func _process(delta: float) -> void:
	if not animate and pose != Pose.FALLEN:
		return
	if _far:
		_flip_book(delta)
		return
	_apply_pose(delta)


## Far away: step through the baked walk frames instead of moving joints.
func _flip_book(delta: float) -> void:
	var frame := -1
	if pose == Pose.WALK and speed > 0.1:
		_phase += delta * speed * 4.2
		frame = int(fposmod(_phase, TAU) / TAU * WALK_FRAMES) % WALK_FRAMES
	if frame != _lod_frame:
		_lod_frame = frame
		var m := _meshes(variant)
		_lod.mesh = m.lod if frame < 0 else m.walk[frame]


func _apply_pose(delta: float) -> void:
	_time += delta
	var fall_target := 1.0 if pose == Pose.FALLEN else 0.0
	_fall = move_toward(_fall, fall_target, delta * (4.0 if fall_target > 0.0 else 2.0))
	var th := [0.0, 0.0]
	var sh := [0.0, 0.0]
	var ar_x := [0.0, 0.0]
	var ar_z := [0.08, -0.08]
	var bob := 0.0
	match pose:
		Pose.WALK:
			_phase += delta * speed * 4.2
			for i in 2:
				var ph := _phase + (PI if i == 1 else 0.0)
				th[i] = sin(ph) * 0.5
				sh[i] = -maxf(0.0, sin(ph + 1.3)) * 0.75
				ar_x[i] = -sin(ph) * 0.45
			bob = absf(sin(_phase)) * 0.03
		Pose.WAVE:
			ar_z[1] = -2.5 + sin(_time * 7.0) * 0.35
			ar_x[0] = 0.1
		Pose.SIT:
			th = [1.45, 1.45]
			sh = [-1.45, -1.45]
			ar_x = [0.55, 0.55]
		Pose.FALLEN:
			th = [0.35, -0.15]
			sh = [-0.4, -0.1]
			ar_z = [1.1, -1.3]
		_:
			ar_x = [sin(_time * 1.3) * 0.04, -sin(_time * 1.3) * 0.04]
	for i in 2:
		_thigh[i].rotation = Vector3(th[i], 0, 0)
		_shin[i].rotation = Vector3(sh[i], 0, 0)
		_arm[i].rotation = Vector3(ar_x[i], 0, ar_z[i])
	# Falling over backwards (+Z is behind): tip the body onto its back.
	_hips.position = Vector3(0, HIP_Y + bob - _fall * (HIP_Y - 0.18), _fall * 0.5)
	_hips.rotation = Vector3(_fall * 1.45, 0, 0)
	_stars.visible = _fall > 0.9
	if _stars.visible:
		_stars.rotation.y = _time * 5.0


# --- Mesh building -------------------------------------------------------------------

static func _meshes(v: int) -> Dictionary:
	if _cache.has(v):
		return _cache[v]
	var mugger := v == MUGGER_VARIANT
	var style := 1 if mugger else v % STYLE_COUNT
	var shade := v / STYLE_COUNT
	var skin: Color = SKIN_TONES[v % SKIN_TONES.size()]
	var top: Color = BRIGHT[(v * 3 + 1) % BRIGHT.size()]
	var bottom: Color = MUTED[(v + shade) % MUTED.size()]
	var accent: Color = BRIGHT[(v * 5 + 4) % BRIGHT.size()]
	var sleeve := top
	var leg_color := bottom
	var skirt := Color(0, 0, 0, 0)   # alpha 0 = no skirt
	var skirt_bottom := 0.12         # height above the feet where the skirt ends
	var sandal := Color(0.3, 0.18, 0.1)

	var body := MeshKit.new()
	# Hips are the local origin of the body mesh.
	var shoulder := Vector3(0, SHOULDER_Y - HIP_Y, 0)
	var head := shoulder + Vector3(0, 0.22, 0)
	match style:
		0:  # man in a checked lungi and short-sleeved shirt
			skirt = Color(0.15, 0.35, 0.6).lerp(accent, 0.3)
		1:  # man in shirt and trousers
			leg_color = MUTED[3] if shade == 0 else Color(0.25, 0.22, 0.2)
		2:  # man in a long panjabi with a white tupi cap
			top = Color(0.95, 0.95, 0.92) if shade == 0 else Color(0.85, 0.8, 0.65)
			sleeve = top
			leg_color = Color(0.95, 0.95, 0.92)
		3:  # student with a backpack
			top = Color(0.92, 0.92, 0.95) if shade == 0 else Color(0.5, 0.7, 0.9)
			sleeve = top
			leg_color = Color(0.15, 0.2, 0.35)
		4:  # woman in a saree
			skirt = accent
			sleeve = top
		5:  # woman in salwar kameez with an orna
			leg_color = top.lightened(0.4)
			skirt = top
			skirt_bottom = 0.45
		6:  # woman in a borka
			top = Color(0.1, 0.1, 0.12) if shade == 0 else Color(0.2, 0.15, 0.3)
			sleeve = top
			skirt = top
			leg_color = top
		7:  # old man: panjabi, lungi, white beard
			top = Color(0.95, 0.95, 0.9)
			sleeve = top
			skirt = Color(0.35, 0.5, 0.35)
	if mugger:
		top = Color(0.13, 0.13, 0.15)
		sleeve = top
		leg_color = Color(0.1, 0.12, 0.2)
		skirt = Color(0, 0, 0, 0)
	# Torso.
	body.add_box_at(Vector3(0, 0.02, 0), Vector3(0.3, 0.18, 0.2), skirt if skirt.a > 0.0 else leg_color)
	body.add_beam(Vector3(0, -0.02, 0), shoulder, 0.34, 0.2, top)
	body.add_rod(shoulder, shoulder + Vector3(0, 0.1, 0), 0.05, skin)
	if style == 2 or style == 7:
		# Panjabi hangs to the knees.
		body.add_box_at(Vector3(0, -0.22, 0), Vector3(0.36, 0.42, 0.23), top)
	if skirt.a > 0.0:
		var length := HIP_Y - skirt_bottom
		body.add_box_at(Vector3(0, -length * 0.5 + 0.05, 0), Vector3(0.4, length, 0.27), skirt)
		if style == 0:
			for k in 3:  # checks on the lungi
				body.add_panel(Transform3D(Basis(), Vector3(0, -0.15 - k * 0.22, 0.136)), Vector2(0.4, 0.05), skirt.lightened(0.35))
	# Head, hair or head covering.
	body.add_sphere(Transform3D(Basis().scaled(Vector3(1, 1.12, 1)), head), 0.105, skin, 4, 8)
	match style:
		2, 7:
			body.add_cylinder(Transform3D(Basis(), head + Vector3(0, 0.08, 0)), 0.1, 0.07, Color(0.97, 0.97, 0.95), 8)
		4:
			body.add_sphere(Transform3D(Basis().scaled(Vector3(1.05, 0.7, 1.05)), head + Vector3(0, 0.04, 0.01)), 0.11, HAIR, 3, 8)
			body.add_sphere(Transform3D(Basis(), head + Vector3(0, 0.02, 0.12)), 0.06, HAIR, 3, 6)
		5:
			body.add_sphere(Transform3D(Basis().scaled(Vector3(1.05, 0.7, 1.05)), head + Vector3(0, 0.04, 0.01)), 0.11, HAIR, 3, 8)
		6:
			body.add_sphere(Transform3D(Basis().scaled(Vector3(1.15, 1.2, 1.15)), head + Vector3(0, 0.0, 0.02)), 0.115, top, 4, 8)
		_:
			body.add_sphere(Transform3D(Basis().scaled(Vector3(1.04, 0.62, 1.06)), head + Vector3(0, 0.05, 0.01)), 0.108, HAIR, 3, 8)
	match style:
		3:  # backpack
			body.add_box_at(shoulder + Vector3(0, -0.22, 0.17), Vector3(0.28, 0.34, 0.14), accent)
		4:  # saree drape (anchal) over the left shoulder
			body.add_beam(Vector3(0.12, 0.0, -0.11), shoulder + Vector3(-0.12, 0.0, -0.11), 0.12, 0.02, accent.lightened(0.15))
			body.add_beam(shoulder + Vector3(-0.13, 0.0, 0.0), Vector3(-0.15, -0.3, 0.12), 0.12, 0.03, accent.lightened(0.15))
		5:  # orna (scarf) round the neck, ends hanging behind
			body.add_box_at(shoulder + Vector3(0, 0.01, 0), Vector3(0.38, 0.06, 0.24), accent)
			body.add_box_at(shoulder + Vector3(0, -0.25, 0.12), Vector3(0.3, 0.5, 0.03), accent)
		7:
			body.add_box_at(head + Vector3(0, -0.11, -0.07), Vector3(0.12, 0.14, 0.06), Color(0.95, 0.95, 0.95))
	if mugger:
		# Black cap with a peak, pulled low.
		body.add_sphere(Transform3D(Basis().scaled(Vector3(1.08, 0.6, 1.08)), head + Vector3(0, 0.06, 0)), 0.11, Color(0.06, 0.06, 0.07), 3, 8)
		body.add_box_at(head + Vector3(0, 0.04, -0.12), Vector3(0.18, 0.02, 0.1), Color(0.06, 0.06, 0.07))
	# Limbs (pivots at hip / knee / shoulder, extending downwards).
	var thigh := MeshKit.new()
	thigh.add_box_at(Vector3(0, -THIGH * 0.5, 0), Vector3(0.12, THIGH, 0.13), leg_color)
	var shin := MeshKit.new()
	shin.add_box_at(Vector3(0, -SHIN * 0.5 + 0.02, 0), Vector3(0.1, SHIN - 0.04, 0.11), leg_color if style != 0 and style != 7 else skin)
	shin.add_box_at(Vector3(0, -SHIN + 0.02, -0.04), Vector3(0.1, 0.04, 0.22), sandal)
	var arm := MeshKit.new()
	var sleeve_len := 0.5 if style in [2, 4, 5, 6, 7] else 0.22
	arm.add_box_at(Vector3(0, -sleeve_len * 0.5, 0), Vector3(0.09, sleeve_len, 0.09), sleeve)
	arm.add_box_at(Vector3(0, -(sleeve_len + ARM) * 0.5, 0), Vector3(0.075, ARM - sleeve_len, 0.075), skin)
	arm.add_box_at(Vector3(0, -ARM - 0.03, 0), Vector3(0.07, 0.08, 0.08), skin)
	# Cartoon stars for when someone gets knocked over.
	var stars := MeshKit.new()
	for k in 4:
		var a := TAU * k / 4.0
		var c := head + Vector3(cos(a) * 0.25, 0.2, sin(a) * 0.25)
		stars.add_box(Transform3D(Basis(Vector3.UP, a), c), Vector3(0.1, 0.1, 0.03), Color(1, 0.9, 0.1))
		stars.add_box(Transform3D(Basis(Vector3.BACK, PI * 0.25) * Basis(Vector3.UP, a), c), Vector3(0.1, 0.1, 0.03), Color(1, 0.9, 0.1))
	var result := {"body": body.build(), "thigh": thigh.build(), "shin": shin.build(), "arm": arm.build(), "stars": stars.build()}
	# Low-detail versions: everything merged into one mesh (one draw call),
	# standing, plus a flip-book of the walk cycle.
	result.lod = _bake(result, [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], 0.0)
	var walk: Array[ArrayMesh] = []
	for f in WALK_FRAMES:
		var ph := TAU * f / WALK_FRAMES
		var th := [0.0, 0.0]
		var sh := [0.0, 0.0]
		var ar := [0.0, 0.0]
		for i in 2:
			var q := ph + (PI if i == 1 else 0.0)
			th[i] = sin(q) * 0.5
			sh[i] = -maxf(0.0, sin(q + 1.3)) * 0.75
			ar[i] = -sin(q) * 0.45
		walk.append(_bake(result, th, sh, ar, absf(sin(ph)) * 0.03))
	result.walk = walk
	_cache[v] = result
	return result


## Merges the body parts in one pose into a single mesh (same joint layout
## as the node tree built in _ready).
static func _bake(parts: Dictionary, th: Array, sh: Array, ar_x: Array, bob: float) -> ArrayMesh:
	var kit := MeshKit.new()
	var hips := Transform3D(Basis(), Vector3(0, HIP_Y + bob, 0))
	kit.add_mesh(parts.body, hips)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var thigh := hips * Transform3D(Basis.from_euler(Vector3(th[i], 0, 0)), Vector3(side * 0.09, 0, 0))
		kit.add_mesh(parts.thigh, thigh)
		kit.add_mesh(parts.shin, thigh * Transform3D(Basis.from_euler(Vector3(sh[i], 0, 0)), Vector3(0, -THIGH, 0)))
		var arm_rot := Basis.from_euler(Vector3(ar_x[i], 0, 0.08 * -side))
		kit.add_mesh(parts.arm, hips * Transform3D(arm_rot, Vector3(side * 0.21, SHOULDER_Y - HIP_Y - 0.02, 0)))
	return kit.build()

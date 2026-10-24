## Builds the Dhaka neighbourhood procedurally at startup from CityLayout.
##
## Roads are simply the asphalt ground plane. Every area between roads is a
## raised sidewalk slab ("block") with buildings along each edge that faces a
## road. Each district has its own style, and landmarks (New Market, the
## Farmgate footbridge, the university gate and so on) are placed from the layout
## data. Everything static in a block is merged into one mesh and one
## StaticBody3D to keep draw calls and physics cheap.
extends Node3D

const MeshKit := preload("res://scripts/mesh_kit.gd")
const CityLayout := preload("res://scripts/city_layout.gd")
const FONT_PATH := "res://assets/fonts/NotoSansBengali.ttf"

const SLAB_HEIGHT := 0.15
const SIDEWALK := 3.5
const GROUND_FLOOR := 3.4
const FLOOR_HEIGHT := 3.0
const WORLD_LAYER := 1

const ASPHALT := Color(0.27, 0.27, 0.29)
const CONCRETE := Color(0.62, 0.6, 0.55)
const BRICK := Color(0.66, 0.3, 0.2)
const WOOD := Color(0.48, 0.3, 0.15)
const TIN := Color(0.6, 0.62, 0.65)
const LEAF := Color(0.18, 0.5, 0.18)
const WALL_COLORS := [
	Color(0.95, 0.85, 0.65), Color(0.96, 0.7, 0.62), Color(0.7, 0.85, 0.95),
	Color(0.72, 0.9, 0.75), Color(0.98, 0.9, 0.5), Color(0.92, 0.75, 0.85),
	Color(0.88, 0.88, 0.82), Color(0.98, 0.78, 0.5), Color(0.8, 0.78, 0.95),
]
const SIGN_COLORS := [
	Color(0.85, 0.1, 0.12), Color(0.05, 0.5, 0.25), Color(0.1, 0.3, 0.75),
	Color(0.98, 0.8, 0.1), Color(0.95, 0.95, 0.92), Color(0.55, 0.1, 0.5),
]
const AWNING_COLORS := [
	Color(0.15, 0.45, 0.85), Color(0.95, 0.5, 0.1), Color(0.1, 0.6, 0.3), Color(0.85, 0.15, 0.2),
]
const PRODUCE_COLORS := [
	Color(0.2, 0.65, 0.2), Color(0.9, 0.15, 0.1), Color(1.0, 0.55, 0.1),
	Color(0.45, 0.15, 0.5), Color(0.98, 0.85, 0.2), Color(0.55, 0.8, 0.3),
]
const SHOP_NAMES := [
	"মায়ের দোয়া মোবাইল শপ", "বিসমিল্লাহ ফার্মেসি", "ভাই ভাই হোটেল", "রহমান স্টোর",
	"চা ও নাস্তা", "বিকাশ ও নগদ", "মুদির দোকান", "সেলুন", "ফটোস্ট্যাট",
	"বিরিয়ানি হাউস", "কাপড়ের দোকান", "মোবাইল সার্ভিসিং", "মা ফার্মেসি",
	"নিউ স্টার টেইলার্স", "আল্লাহর দান স্টোর", "লাইব্রেরি ও স্টেশনারি",
	"মিষ্টিমুখ", "জুতার দোকান", "ইলেকট্রনিক্স", "কম্পিউটার কম্পোজ",
]
const MARKET_SHOP_NAMES := [
	"শাড়ি ঘর", "কাপড়ের দোকান", "জুতার দোকান", "চুড়ি ও কসমেটিক্স", "থান কাপড়",
	"ব্যাগ হাউস", "বই ঘর", "মুদির দোকান", "চাল ডাল আড়ত", "মাছ বাজার",
	"ফলের দোকান", "সবজি আড়ত", "হাঁড়ি পাতিল", "ঘড়ি মেরামত",
]

## Change to get a different arrangement of buildings and shops.
@export var layout_seed := 1971

var _rng := RandomNumberGenerator.new()
var _font: Font
var _shop_index := 0
var _market_index := 0
## One entry per block: {rect, kit, body, style, footprints, walkway}.
var _blocks: Array[Dictionary] = []

## Breakable street props (vegetable stalls, tea stalls, benches):
## {id, kind, xf, seed, block, broken, center, half, labels, colors}.
var props: Array[Dictionary] = []
var _prop_meshes := {}  # block index -> MeshInstance3D

## Number of buildings and labels created (for tests and tuning).
var building_count := 0
var label_count := 0

## A finished city handed from one scene to the next (menu -> ride -> menu,
## restarts), so the slow build happens only once per session.
static var _spare: Node3D = null


func _ready() -> void:
	if _spare != null and is_instance_valid(_spare) and _spare.layout_seed == layout_seed:
		_adopt(_spare)
	else:
		build()


## Keeps this (already built) city for the next scene instead of letting it
## be freed with this one. Broken stalls and benches are put back first.
func keep_for_next_scene() -> void:
	var dirty := {}
	for rec in props:
		if rec.broken:
			rec.broken = false
			dirty[rec.block] = true
	for b in dirty:
		rebuild_block_props(b)
	if _spare != null and _spare != self and is_instance_valid(_spare):
		_spare.free()
	get_parent().remove_child(self)
	_spare = self


## Frees a kept city that no scene took (when the game closes).
static func free_spare() -> void:
	if _spare != null and is_instance_valid(_spare) and not _spare.is_inside_tree():
		_spare.free()
	_spare = null


## Takes over everything a kept city built: its nodes and its records.
func _adopt(other: Node3D) -> void:
	Settings.log_time("city: reusing the one already built")
	_spare = null
	for child in other.get_children():
		other.remove_child(child)
		add_child(child)
	_rng = other._rng
	_font = other._font
	_shop_index = other._shop_index
	_market_index = other._market_index
	_blocks = other._blocks
	props = other.props
	_prop_meshes = other._prop_meshes
	building_count = other.building_count
	label_count = other.label_count
	other.free()
	Settings.log_time("city: reused")


func build() -> void:
	_rng.seed = layout_seed
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	Settings.log_time("city: start")
	_build_ground()
	for r in CityLayout.block_rects():
		_blocks.append(_new_block(r))
	Settings.log_time("city: ground and blocks")
	for lm in CityLayout.LANDMARKS:
		_build_landmark(lm)
	Settings.log_time("city: landmarks")
	for b in _blocks:
		_build_block_contents(b)
	Settings.log_time("city: buildings, signs, props")
	var shared := MeshKit.new()
	_build_road_markings(shared)
	_build_intersections(shared)
	_build_caution_signs(shared)
	_build_boundary(shared)
	_build_welcome_arch(shared)
	add_child(shared.build_instance("StreetDetails"))
	Settings.log_time("city: street details")
	for i in _blocks.size():
		rebuild_block_props(i)
	Settings.log_time("city: prop meshes")
	for i in _blocks.size():
		var mi: MeshInstance3D = _blocks[i].kit.build_instance("Block%dMesh" % i)
		if mi:
			add_child(mi)
	Settings.log_time("city: block meshes (done, %d labels)" % label_count)


# --- Helpers -------------------------------------------------------------------

static func _t(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(), pos)


static func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func _new_static_body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	return body


func _add_box_collider(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


## Adds Bangla text. The text is scaled to fit `max_size` (metres).
func _add_label(text: String, xf: Transform3D, max_size: Vector2, color: Color,
		view_distance := 70.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	if _font:
		label.font = _font
		var px := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64)
		label.pixel_size = minf(max_size.x / maxf(px.x, 1.0), max_size.y / maxf(px.y, 1.0))
	else:
		label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	# Phones stop drawing shop signs sooner (there are a couple of thousand).
	label.visibility_range_end = view_distance * (0.45 if Settings.touch_mode else 1.0)
	label.transform = xf
	add_child(label)
	label_count += 1
	return label


## A sign readable from both sides: board + the same text front and back.
func _add_board(kit, xf: Transform3D, size: Vector2, board: Color, text: String,
		text_color := Color(1, 1, 1), view_distance := 70.0) -> void:
	kit.add_box(xf, Vector3(size.x, size.y, 0.08), board)
	kit.add_box(xf, Vector3(size.x + 0.12, size.y + 0.12, 0.05), Color(0.95, 0.95, 0.92))
	var fit := Vector2(size.x * 0.9, size.y * 0.7)
	_add_label(text, xf * _t(Vector3(0, 0, 0.045)), fit, text_color, view_distance)
	var back := Transform3D(xf.basis * Basis(Vector3.UP, PI), xf.origin)
	_add_label(text, back * _t(Vector3(0, 0, 0.045)), fit, text_color, view_distance)


func _block_at(p: Vector2) -> Dictionary:
	for b in _blocks:
		if b.rect.grow(0.05).has_point(p):
			return b
	return {}


## Reserves a local rectangle (in landmark space) so buildings/props avoid it.
func _reserve(block: Dictionary, xf: Transform3D, a: Vector3, b: Vector3, key := "footprints") -> void:
	if block.is_empty():
		return
	var pts := [xf * a, xf * b, xf * Vector3(a.x, 0, b.z), xf * Vector3(b.x, 0, a.z)]
	var r := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for p in pts:
		r = r.expand(Vector2(p.x, p.z))
	block[key].append(r)


func _is_free(list: Array, r: Rect2) -> bool:
	for other in list:
		if other.grow(-0.05).intersects(r):
			return false
	return true


# --- Ground ----------------------------------------------------------------------

func _build_ground() -> void:
	var kit := MeshKit.new()
	var m := CityLayout.MAP.grow(20.0)
	var x0 := m.position.x
	var x1 := m.end.x
	var z0 := m.position.y
	var z1 := m.end.y
	kit.add_quad(Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0), ASPHALT)
	# Patches and potholes give the asphalt some character.
	var roads := CityLayout.road_rects()
	for i in 160:
		var r := roads[_rng.randi() % roads.size()]
		var x := _rng.randf_range(r.position.x + 1.0, r.end.x - 1.0)
		var z := _rng.randf_range(r.position.y + 1.0, r.end.y - 1.0)
		var s := _rng.randf_range(0.6, 2.2)
		var col := ASPHALT.darkened(_rng.randf_range(0.08, 0.25))
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		var c := Vector3(x, 0.006, z)
		kit.add_quad(c + b * Vector3(-s, 0, s * 0.6), c + b * Vector3(s, 0, s * 0.6),
			c + b * Vector3(s, 0, -s * 0.6), c + b * Vector3(-s, 0, -s * 0.6), col)
	add_child(kit.build_instance("Ground"))
	var body := _new_static_body("GroundBody")
	_add_box_collider(body, _t(Vector3(m.get_center().x, -0.5, m.get_center().y)), Vector3(m.size.x, 1.0, m.size.y))


# --- Blocks ----------------------------------------------------------------------

func _new_block(rect: Rect2) -> Dictionary:
	var block := {
		"rect": rect,
		"kit": MeshKit.new(),
		"body": _new_static_body("Block%d" % _blocks.size()),
		"style": CityLayout.district_for(rect.get_center()),
		"footprints": [] as Array[Rect2],
		"walkway": [] as Array[Rect2],
		"index": _blocks.size(),
	}
	if block.style == "lake":
		return block  # water and promenade, built in _build_lake_block
	var center := Vector3(rect.get_center().x, SLAB_HEIGHT * 0.5, rect.get_center().y)
	block.kit.add_box(_t(center), Vector3(rect.size.x, SLAB_HEIGHT, rect.size.y), CONCRETE)
	# No collider for the footpath slab: the rickshaw can ride up onto it.
	return block


## Each edge: [start point, direction along edge, inward normal, length].
func _block_edges(r: Rect2) -> Array:
	return [
		[Vector3(r.position.x, 0, r.position.y), Vector3.RIGHT, Vector3.BACK, r.size.x],
		[Vector3(r.position.x, 0, r.end.y), Vector3.RIGHT, Vector3.FORWARD, r.size.x],
		[Vector3(r.position.x, 0, r.position.y), Vector3.BACK, Vector3.RIGHT, r.size.y],
		[Vector3(r.end.x, 0, r.position.y), Vector3.BACK, Vector3.LEFT, r.size.y],
	]


func _build_block_contents(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var kit = block.kit
	var style: String = block.style
	if style == "lake":
		_build_lake_block(block)
		return
	if style == "park":
		_build_park_block(block)
		return
	for edge in _block_edges(rect):
		var start: Vector3 = edge[0]
		var dir: Vector3 = edge[1]
		var inward: Vector3 = edge[2]
		var length: float = edge[3]
		var mid := start + dir * length * 0.5 - inward
		if not CityLayout.is_road(mid.x, mid.z):
			continue
		var depth_room := (rect.size.y if absf(dir.x) > 0.5 else rect.size.x) - SIDEWALK - 0.5
		_build_curb(kit, start, dir, inward, length)
		_build_poles_and_wires(kit, start, dir, inward, length, block.body)
		if style == "campus":
			_build_campus_wall(block, start, dir, inward, length)
		else:
			_build_edge_buildings(block, start, dir, inward, length, minf(depth_room, 12.0))
		_build_sidewalk_props(block, start, dir, inward, length)
	if style == "campus":
		_build_campus_interior(block)


func _build_curb(kit, start: Vector3, dir: Vector3, inward: Vector3, length: float) -> void:
	# Dhaka curbs are often painted in black and yellow stripes: one long dark
	# curb with yellow panels painted on its face and top.
	# The curb sticks out 3 cm past the footpath slab and stands 2 cm above
	# it, and the paint sits 8-10 mm off its faces: surfaces that share a
	# plane (or nearly) flicker against each other in the distance.
	var h := SLAB_HEIGHT + 0.02
	var y := h * 0.5
	var out := 0.03
	var depth := 0.14 + out
	var size := Vector3(length, h, depth) if absf(dir.x) > 0.5 else Vector3(depth, h, length)
	kit.add_box_at(start + dir * length * 0.5 + inward * (0.14 - depth * 0.5) + Vector3(0, y, 0), size, Color(0.1, 0.1, 0.1))
	var face := Basis.looking_at(inward)  # local +Z faces the road
	var top := Basis(Vector3.RIGHT, -PI * 0.5)
	var count := int(length)
	for i in range(0, count, 2):
		var p := start + dir * (i + 0.5) + Vector3(0, y, 0)
		var yellow := Color(0.95, 0.8, 0.1)
		kit.add_panel(Transform3D(face, p - inward * (out + 0.01)), Vector2(1.0, h), yellow)
		kit.add_panel(Transform3D(face * top, p + inward * (0.14 - depth * 0.5) + Vector3(0, h * 0.5 + 0.008, 0)), Vector2(1.0, depth), yellow)


func _build_poles_and_wires(kit, start: Vector3, dir: Vector3, inward: Vector3, length: float, body: StaticBody3D) -> void:
	var concrete := Color(0.55, 0.55, 0.52)
	var wire_col := Color(0.06, 0.06, 0.06)
	var spacing := 18.0
	var tops: Array[Vector3] = []
	var t := 6.0
	while t < length - 4.0:
		var base := start + dir * t + inward * 0.6 + Vector3(0, SLAB_HEIGHT, 0)
		var h := 8.0
		kit.add_beam(base, base + Vector3(0, h, 0), 0.22, 0.22, concrete)
		_add_box_collider(body, _t(base + Vector3(0, 1.5, 0)), Vector3(0.24, 3.0, 0.24))
		var arm := inward.cross(Vector3.UP)
		kit.add_box(Transform3D(Basis.looking_at(arm), base + Vector3(0, h - 0.3, 0)), Vector3(1.6, 0.1, 0.1), concrete)
		if _rng.randf() < 0.3:
			# Small transformer box hanging on the pole.
			kit.add_box_at(base + Vector3(0, h - 2.0, 0) + inward * 0.3, Vector3(0.5, 0.7, 0.4), Color(0.45, 0.47, 0.45))
		tops.append(base + Vector3(0, h - 0.25, 0))
		t += spacing
	# Sagging wires between neighbouring poles.
	for i in tops.size() - 1:
		var wires := 3 + _rng.randi() % 3
		for w in wires:
			var side := dir.cross(Vector3.UP) * (-0.7 + w * 0.35)
			var drop := Vector3(0, -w * 0.12, 0)
			_add_wire(kit, tops[i] + side + drop, tops[i + 1] + side + drop, _rng.randf_range(0.4, 1.4), wire_col)


func _add_wire(kit, a: Vector3, b: Vector3, sag: float, color: Color) -> void:
	var segments := 6
	var prev := a
	for i in range(1, segments + 1):
		var f := float(i) / segments
		var p := a.lerp(b, f) + Vector3(0, -sag * 4.0 * f * (1.0 - f), 0)
		kit.add_bar(prev, p, 0.025, color)
		prev = p


# --- Buildings -------------------------------------------------------------------

func _build_edge_buildings(block: Dictionary, start: Vector3, dir: Vector3,
		inward: Vector3, length: float, max_depth: float) -> void:
	if max_depth < 5.0:
		return
	var style: String = block.style
	# Start and end where the perpendicular sidewalks are, so corners stay walkable.
	var t := SIDEWALK
	while t < length - SIDEWALK - 4.0:
		var w := minf(_rng.randf_range(6.0, 10.0), length - SIDEWALK - t)
		if w < 4.0:
			break
		var depth := minf(_rng.randf_range(8.0, 12.0), max_depth)
		var a := start + dir * t + inward * SIDEWALK
		var b := start + dir * (t + w) + inward * (SIDEWALK + depth)
		var fp := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z)))
		if not _is_free(block.footprints, fp):
			t += 2.0
			continue
		block.footprints.append(fp)
		var center := start + dir * (t + w * 0.5) + inward * (SIDEWALK + depth * 0.5) + Vector3(0, SLAB_HEIGHT, 0)
		var floors := _rng.randi_range(2, 6)
		var ground := "shop"
		match style:
			"market":
				floors = _rng.randi_range(1, 3)
			"residential":
				floors = _rng.randi_range(4, 7)
				if _rng.randf() < 0.65:
					ground = "gate"
		_add_building(block, Transform3D(Basis.looking_at(inward), center), w, depth, floors, ground)
		t += w + _rng.randf_range(0.0, 0.6)


func _next_shop_name(style: String) -> String:
	if style == "market" and _rng.randf() < 0.7:
		_market_index += 1
		return MARKET_SHOP_NAMES[_market_index % MARKET_SHOP_NAMES.size()]
	_shop_index += 1
	return SHOP_NAMES[_shop_index % SHOP_NAMES.size()]


## Building in local space: front face at +Z (towards the road), origin at the
## centre of the footprint on top of the sidewalk.
func _add_building(block: Dictionary, xf: Transform3D, w: float, depth: float, floors: int, ground: String) -> void:
	var kit = block.kit
	building_count += 1
	var height := GROUND_FLOOR + floors * FLOOR_HEIGHT
	var wall: Color = WALL_COLORS[_rng.randi() % WALL_COLORS.size()]
	var trim := wall.lightened(0.35)
	var front := depth * 0.5
	kit.add_box(xf * _t(Vector3(0, height * 0.5, 0)), Vector3(w, height, depth), wall)
	_add_box_collider(block.body, xf * _t(Vector3(0, height * 0.5, 0)), Vector3(w, height, depth))

	if ground == "shop":
		_add_shop_front(kit, xf, w, front, _next_shop_name(block.style))
	else:
		_add_gate_front(kit, xf, w, front, wall)

	# Upper floors: windows with grills and sunshades, some balconies with laundry.
	var windows := maxi(1, int(w / 2.6))
	var grill := Color(0.85, 0.9, 0.85)
	for f in floors:
		var base_y := GROUND_FLOOR + f * FLOOR_HEIGHT
		kit.add_panel(xf * _t(Vector3(0, base_y, front + 0.01)), Vector2(w, 0.18), trim)
		for i in windows:
			var wx := -w * 0.5 + (i + 0.5) * w / windows
			var wy := base_y + 1.5
			kit.add_panel(xf * _t(Vector3(wx, wy, front + 0.02)), Vector2(1.2, 1.3), Color(0.18, 0.25, 0.32))
			for g in 3:
				kit.add_panel(xf * _t(Vector3(wx - 0.4 + g * 0.4, wy, front + 0.04)), Vector2(0.05, 1.3), grill)
			kit.add_panel(xf * _t(Vector3(wx, wy, front + 0.04)), Vector2(1.2, 0.05), grill)
			kit.add_box(xf * _t(Vector3(wx, wy + 0.78, front + 0.22)), Vector3(1.6, 0.08, 0.45), trim)
			if _rng.randf() < 0.25:
				kit.add_box(xf * _t(Vector3(wx + 0.95, wy - 0.3, front + 0.2)), Vector3(0.55, 0.4, 0.35), Color(0.92, 0.92, 0.9))
		# No balcony on the first floor: it would hide the shop signboard.
		if f > 0 and w > 6.5 and _rng.randf() < 0.35:
			var bw := w * 0.5
			var bx := _rng.randf_range(-w * 0.2, w * 0.2)
			kit.add_box(xf * _t(Vector3(bx, base_y + 0.06, front + 0.55)), Vector3(bw, 0.12, 1.0), trim)
			kit.add_box(xf * _t(Vector3(bx, base_y + 0.55, front + 1.0)), Vector3(bw, 0.9, 0.08), wall.darkened(0.1))
			for c in 4:
				var cloth: Color = AWNING_COLORS[(c + f) % AWNING_COLORS.size()].lightened(0.2)
				kit.add_panel(xf * _t(Vector3(bx - bw * 0.35 + c * bw * 0.22, base_y + 1.2, front + 1.06)),
					Vector2(0.45, 0.6), cloth)

	# Roof: parapet, black water tank, sometimes a stair room.
	var p := 0.15
	kit.add_box(xf * _t(Vector3(0, height + 0.4, front - p * 0.5)), Vector3(w, 0.8, p), trim)
	kit.add_box(xf * _t(Vector3(0, height + 0.4, -front + p * 0.5)), Vector3(w, 0.8, p), trim)
	kit.add_box(xf * _t(Vector3(-w * 0.5 + p * 0.5, height + 0.4, 0)), Vector3(p, 0.8, depth), trim)
	kit.add_box(xf * _t(Vector3(w * 0.5 - p * 0.5, height + 0.4, 0)), Vector3(p, 0.8, depth), trim)
	var tank_pos := Vector3(_rng.randf_range(-w * 0.3, w * 0.3), height + 0.6, _rng.randf_range(-depth * 0.3, 0))
	kit.add_cylinder(xf * _t(tank_pos), 0.65, 1.2, Color(0.1, 0.1, 0.11), 8)
	if _rng.randf() < 0.5:
		kit.add_box(xf * _t(Vector3(w * 0.2, height + 1.25, -depth * 0.25)), Vector3(2.4, 2.5, 2.4), wall.darkened(0.08))


## Ground floor shop: dark opening, rolled-up shutter, goods, awning, signboard.
func _add_shop_front(kit, xf: Transform3D, w: float, front: float, shop_name: String) -> void:
	var shop_w := w - 0.8
	kit.add_panel(xf * _t(Vector3(0, 1.3, front + 0.01)), Vector2(shop_w, 2.6), Color(0.16, 0.12, 0.1))
	kit.add_box(xf * _t(Vector3(0, 2.75, front + 0.05)), Vector3(shop_w, 0.35, 0.12), Color(0.55, 0.57, 0.6))
	for i in 5:
		var goods: Color = SIGN_COLORS[_rng.randi() % SIGN_COLORS.size()]
		var gx := -shop_w * 0.4 + i * shop_w * 0.2
		kit.add_box(xf * _t(Vector3(gx, 0.5, front + 0.12)), Vector3(shop_w * 0.16, 0.9 + _rng.randf() * 0.6, 0.25), goods)
	var awning_col: Color = AWNING_COLORS[_rng.randi() % AWNING_COLORS.size()]
	var stripes := 6
	for i in stripes:
		var sx := -shop_w * 0.5 + (i + 0.5) * shop_w / stripes
		var col := awning_col if i % 2 == 0 else Color(0.95, 0.95, 0.9)
		kit.add_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(sx, 2.75, front + 0.65)), Vector3(shop_w / stripes, 0.05, 1.3), col)
	var sign_col: Color = SIGN_COLORS[_rng.randi() % SIGN_COLORS.size()]
	var sign_w := w - 0.5
	kit.add_box(xf * _t(Vector3(0, 3.45, front + 0.06)), Vector3(sign_w, 0.95, 0.1), sign_col)
	kit.add_box(xf * _t(Vector3(0, 3.45, front + 0.04)), Vector3(sign_w + 0.12, 1.07, 0.06), Color(0.95, 0.85, 0.2))
	var text_col := Color(0.1, 0.08, 0.1) if sign_col.get_luminance() > 0.6 else Color(1, 1, 0.95)
	_add_label(shop_name, xf * _t(Vector3(0, 3.45, front + 0.115)), Vector2(sign_w - 0.4, 0.62), text_col)


## Residential ground floor: painted metal gate and a garage shutter.
func _add_gate_front(kit, xf: Transform3D, w: float, front: float, wall: Color) -> void:
	var gate_col: Color = [Color(0.1, 0.45, 0.3), Color(0.15, 0.3, 0.6), Color(0.5, 0.15, 0.15)][_rng.randi() % 3]
	kit.add_box(xf * _t(Vector3(-w * 0.2, 1.2, front + 0.05)), Vector3(2.6, 2.4, 0.1), gate_col)
	for i in 6:
		kit.add_panel(xf * _t(Vector3(-w * 0.2 - 1.1 + i * 0.44, 1.2, front + 0.11)), Vector2(0.05, 2.3), gate_col.lightened(0.3))
	kit.add_panel(xf * _t(Vector3(w * 0.22, 1.25, front + 0.01)), Vector2(minf(3.0, w * 0.4), 2.5), Color(0.5, 0.52, 0.55))
	kit.add_box(xf * _t(Vector3(0, 3.1, front + 0.2)), Vector3(w, 0.15, 0.4), wall.lightened(0.3))
	# Small house name plate.
	kit.add_panel(xf * _t(Vector3(-w * 0.2, 2.65, front + 0.11)), Vector2(1.2, 0.3), Color(0.95, 0.95, 0.9))


# --- Hatirjheel lake (হাতিরঝিল) ------------------------------------------------------

const LAKE_WATER := Color(0.2, 0.45, 0.55)
const PROMENADE := Color(0.78, 0.72, 0.62)
const PROMENADE_WIDTH := 5.0

## A lake block: a raised paved promenade along every side that faces a road
## (you can ride on it), a railing between promenade and water, and the water.
func _build_lake_block(block: Dictionary) -> void:
	var kit = block.kit
	var r: Rect2 = block.rect
	var water := r
	for edge in _block_edges(r):
		var start: Vector3 = edge[0]
		var dir: Vector3 = edge[1]
		var inward: Vector3 = edge[2]
		var length: float = edge[3]
		var mid := start + dir * length * 0.5 - inward
		if not CityLayout.is_road(mid.x, mid.z):
			continue
		# Shrink the water away from this side.
		if inward.x > 0.5:
			water.position.x += PROMENADE_WIDTH
			water.size.x -= PROMENADE_WIDTH
		elif inward.x < -0.5:
			water.size.x -= PROMENADE_WIDTH
		elif inward.z > 0.5:
			water.position.y += PROMENADE_WIDTH
			water.size.y -= PROMENADE_WIDTH
		else:
			water.size.y -= PROMENADE_WIDTH
		var walk := start + dir * length * 0.5 + inward * PROMENADE_WIDTH * 0.5 + Vector3(0, SLAB_HEIGHT * 0.5, 0)
		var walk_size := Vector3(length, SLAB_HEIGHT, PROMENADE_WIDTH) if absf(dir.x) > 0.5 else Vector3(PROMENADE_WIDTH, SLAB_HEIGHT, length)
		kit.add_box_at(walk, walk_size, PROMENADE)
		_build_curb(kit, start, dir, inward, length)
		# Railing along the water's edge (solid: no riding into the lake).
		var rail := start + dir * length * 0.5 + inward * (PROMENADE_WIDTH - 0.15) + Vector3(0, SLAB_HEIGHT + 0.5, 0)
		var rail_size := Vector3(length, 1.0, 0.12) if absf(dir.x) > 0.5 else Vector3(0.12, 1.0, length)
		kit.add_box_at(rail, rail_size * Vector3(1, 0.08, 1) + Vector3(0, 0, 0), Color(0.85, 0.85, 0.82))
		for k in int(length / 2.0):
			kit.add_box_at(start + dir * (k * 2.0 + 1.0) + inward * (PROMENADE_WIDTH - 0.15) + Vector3(0, SLAB_HEIGHT + 0.5, 0), Vector3(0.08, 1.0, 0.08), Color(0.3, 0.32, 0.35))
		kit.add_box_at(rail + Vector3(0, 0.5, 0), rail_size * Vector3(1, 0.08, 1), Color(0.3, 0.32, 0.35))
		_add_box_collider(block.body, _t(rail + Vector3(0, 0.2, 0)), rail_size + Vector3(0, 0.6, 0))
		# Lamp posts along the promenade.
		var t := 6.0
		while t < length - 3.0:
			var lp := start + dir * t + inward * (PROMENADE_WIDTH - 0.6) + Vector3(0, SLAB_HEIGHT, 0)
			kit.add_cylinder(_t(lp + Vector3(0, 1.8, 0)), 0.06, 3.6, Color(0.25, 0.27, 0.3), 6)
			kit.add_sphere(_t(lp + Vector3(0, 3.7, 0)), 0.22, Color(1.0, 0.95, 0.75), 3, 6)
			t += 15.0
	var y := 0.02
	kit.add_quad(Vector3(water.position.x, y, water.end.y), Vector3(water.end.x, y, water.end.y),
		Vector3(water.end.x, y, water.position.y), Vector3(water.position.x, y, water.position.y), LAKE_WATER)
	# Water taxis (ওয়াটার ট্যাক্সি) and the odd boat.
	if water.size.y > 30.0 and water.size.x > 20.0:
		var bz := water.position.y + water.size.y * _rng.randf_range(0.3, 0.7)
		var bx := water.position.x + water.size.x * _rng.randf_range(0.3, 0.7)
		if _rng.randf() < 0.5:
			_add_water_taxi(kit, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)), Vector3(bx, y, bz)))
		else:
			_add_boat(kit, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)), Vector3(bx, y, bz)))
	# The famous fountain in the middle of the lake.
	if water.has_point(Vector2(CityLayout.HATIRJHEEL.get_center().x, 90.0)):
		var f := Vector3(CityLayout.HATIRJHEEL.get_center().x, 0, 90.0)
		kit.add_cylinder(_t(f + Vector3(0, 0.2, 0)), 3.0, 0.4, Color(0.85, 0.85, 0.82), 16)
		for k in 6:
			var a := TAU * k / 6.0
			kit.add_cylinder(_t(f + Vector3(cos(a) * 1.8, 1.4, sin(a) * 1.8)), 0.15, 2.4, Color(0.75, 0.9, 1.0), 6)
		kit.add_cylinder(_t(f + Vector3(0, 2.8, 0)), 0.3, 5.2, Color(0.8, 0.93, 1.0), 8)


func _add_boat(kit, xf: Transform3D) -> void:
	var wood := Color(0.42, 0.26, 0.13)
	kit.add_box(xf * _t(Vector3(0, 0.25, 0)), Vector3(1.4, 0.5, 5.0), wood)
	kit.add_box(xf * _t(Vector3(0, 0.5, 0)), Vector3(1.0, 0.04, 4.6), wood.lightened(0.15))
	for z: float in [-2.7, 2.7]:
		kit.add_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.5 * signf(z)), Vector3(0, 0.45, z)), Vector3(0.8, 0.3, 0.9), wood)
	# Curved bamboo canopy (ছই) in the middle.
	kit.add_box(xf * _t(Vector3(0, 1.05, 0)), Vector3(1.3, 0.08, 1.8), Color(0.62, 0.5, 0.3))
	for x: float in [-0.62, 0.62]:
		kit.add_box(xf * _t(Vector3(x, 0.78, 0)), Vector3(0.06, 0.55, 1.8), Color(0.62, 0.5, 0.3))


## Hatirjheel's white-and-blue water taxi.
func _add_water_taxi(kit, xf: Transform3D) -> void:
	kit.add_box(xf * _t(Vector3(0, 0.35, 0)), Vector3(2.4, 0.7, 8.0), Color(0.95, 0.95, 0.95))
	kit.add_box(xf * _t(Vector3(0, 0.72, 0)), Vector3(2.45, 0.06, 8.05), Color(0.1, 0.35, 0.75))
	kit.add_box(xf * _t(Vector3(0, 1.4, 0.5)), Vector3(2.0, 1.3, 5.0), Color(0.92, 0.92, 0.95))
	for side: float in [-1.0, 1.0]:
		kit.add_panel(Transform3D(xf.basis * Basis(Vector3.UP, PI * 0.5 * side), xf * Vector3(side * 1.01, 1.5, 0.5)), Vector2(4.6, 0.6), Color(0.2, 0.3, 0.4))
	kit.add_box(xf * _t(Vector3(0, 2.1, 0.5)), Vector3(2.3, 0.1, 5.4), Color(0.1, 0.35, 0.75))


## Water taxi jetty (ঘাট) on the promenade, with a ticket booth.
func _build_ghat(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	# Local +Z faces the road; the lake is behind (-Z).
	kit.add_box(xf * _t(Vector3(0, 0.1, -PROMENADE_WIDTH - 4.0)), Vector3(4.0, 0.2, 8.0), WOOD)
	for z: float in [-PROMENADE_WIDTH - 1.0, -PROMENADE_WIDTH - 7.5]:
		for x: float in [-1.8, 1.8]:
			kit.add_cylinder(xf * _t(Vector3(x, 0.4, z)), 0.12, 0.8, WOOD.darkened(0.2), 6)
	var booth := Vector3(w * 0.5 - 1.2, 1.2, -2.6)
	kit.add_box(xf * _t(booth), Vector3(1.8, 2.4, 1.6), Color(0.15, 0.4, 0.75))
	kit.add_panel(xf * _t(booth + Vector3(0, 0.3, 0.81)), Vector2(1.2, 0.7), Color(0.85, 0.92, 1.0))
	_add_water_taxi(kit, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.02, -PROMENADE_WIDTH - 10.0)))
	_add_board(kit, xf * _t(Vector3(-1.5, 3.0, -1.0)), Vector2(5.5, 0.8), Color(0.1, 0.35, 0.75), title, Color(1, 1, 1), 120.0)


# --- Gulshan Lake Park (গুলশান লেক পার্ক) ---------------------------------------------

const GRASS := Color(0.34, 0.6, 0.25)
const PARK_PATH := Color(0.82, 0.76, 0.62)
const FENCE := Color(0.12, 0.38, 0.2)

func _build_park_block(block: Dictionary) -> void:
	var kit = block.kit
	var r: Rect2 = block.rect
	var inner := r
	# Footpath, kerb, poles and a low green fence along the sides facing roads.
	for edge in _block_edges(r):
		var start: Vector3 = edge[0]
		var dir: Vector3 = edge[1]
		var inward: Vector3 = edge[2]
		var length: float = edge[3]
		var mid := start + dir * length * 0.5 - inward
		if not CityLayout.is_road(mid.x, mid.z):
			continue
		_build_curb(kit, start, dir, inward, length)
		_build_poles_and_wires(kit, start, dir, inward, length, block.body)
		_build_park_fence(block, start, dir, inward, length)
		if inward.x > 0.5:
			inner.position.x += SIDEWALK + 0.6
			inner.size.x -= SIDEWALK + 0.6
		elif inward.x < -0.5:
			inner.size.x -= SIDEWALK + 0.6
		elif inward.z > 0.5:
			inner.position.y += SIDEWALK + 0.6
			inner.size.y -= SIDEWALK + 0.6
		else:
			inner.size.y -= SIDEWALK + 0.6
	if inner.size.x < 2.0 or inner.size.y < 2.0:
		return
	var y := SLAB_HEIGHT + 0.01
	kit.add_quad(Vector3(inner.position.x, y, inner.end.y), Vector3(inner.end.x, y, inner.end.y),
		Vector3(inner.end.x, y, inner.position.y), Vector3(inner.position.x, y, inner.position.y), GRASS)
	var keep_clear: Array[Rect2] = []
	# Paved paths crossing the block.
	var c := inner.get_center()
	if inner.size.x > 20.0 and inner.size.y > 12.0:
		var py := y + 0.01  # not too close to the grass, or it flickers
		kit.add_quad(Vector3(inner.position.x, py, c.y + 1.3), Vector3(inner.end.x, py, c.y + 1.3),
			Vector3(inner.end.x, py, c.y - 1.3), Vector3(inner.position.x, py, c.y - 1.3), PARK_PATH)
		kit.add_quad(Vector3(c.x - 1.3, py, inner.end.y), Vector3(c.x + 1.3, py, inner.end.y),
			Vector3(c.x + 1.3, py, inner.position.y), Vector3(c.x - 1.3, py, inner.position.y), PARK_PATH)
		keep_clear.append(Rect2(inner.position.x, c.y - 2.5, inner.size.x, 5.0))
		keep_clear.append(Rect2(c.x - 2.5, inner.position.y, 5.0, inner.size.y))
		# Benches along the paths.
		for k in 4:
			var bx := c.x + (k - 1.5) * 10.0
			if absf(bx - c.x) > 4.0 and bx > inner.position.x + 2.0 and bx < inner.end.x - 2.0:
				# Breakable, like the benches on the footpaths.
				_add_prop(block, "bench", Transform3D(Basis(), Vector3(bx, SLAB_HEIGHT, c.y - 2.6)))
	# The pond.
	var pond := CityLayout.PARK_POND.intersection(inner)
	if pond.size.x > 4.0 and pond.size.y > 4.0:
		kit.add_box_at(Vector3(pond.get_center().x, SLAB_HEIGHT + 0.06, pond.get_center().y), Vector3(pond.size.x + 1.0, 0.12, pond.size.y + 1.0), Color(0.62, 0.6, 0.55))
		var wy := SLAB_HEIGHT + 0.13
		kit.add_quad(Vector3(pond.position.x, wy, pond.end.y), Vector3(pond.end.x, wy, pond.end.y),
			Vector3(pond.end.x, wy, pond.position.y), Vector3(pond.position.x, wy, pond.position.y), LAKE_WATER)
		for k in 3:
			_add_boat(kit, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(pond.position.x + pond.size.x * (k + 1) / 4.0, wy, pond.get_center().y + _rng.randf_range(-5, 5))))
		keep_clear.append(pond.grow(2.0))
	# Lots of trees (solid trunks).
	var count := clampi(int(inner.get_area() / 160.0), 0, 60)
	for i in count:
		var tp := Vector2(_rng.randf_range(inner.position.x + 1.5, inner.end.x - 1.5), _rng.randf_range(inner.position.y + 1.5, inner.end.y - 1.5))
		var blocked := false
		for k in keep_clear:
			if k.has_point(tp):
				blocked = true
				break
		if not blocked:
			_add_tree(kit, Vector3(tp.x, SLAB_HEIGHT, tp.y), block.body)


func _build_park_fence(block: Dictionary, start: Vector3, dir: Vector3, inward: Vector3, length: float) -> void:
	var kit = block.kit
	var seg := 4.0
	var t := SIDEWALK
	while t < length - SIDEWALK - 0.1:
		var l := minf(seg, length - SIDEWALK - t)
		var c := start + dir * (t + l * 0.5) + inward * (SIDEWALK + 0.3) + Vector3(0, SLAB_HEIGHT, 0)
		var along := Vector2(absf(dir.x), absf(dir.z)) * l
		var r := Rect2(Vector2(c.x, c.z) - along * 0.5 - Vector2(0.3, 0.3), along + Vector2(0.6, 0.6))
		if _is_free(block.walkway, r):  # the gate leaves a gap
			var size := Vector3(l, 0.08, 0.08) if absf(dir.x) > 0.5 else Vector3(0.08, 0.08, l)
			kit.add_box_at(c + Vector3(0, 1.1, 0), size, FENCE)
			kit.add_box_at(c + Vector3(0, 0.4, 0), size, FENCE)
			for k in int(l / 0.5):
				kit.add_box_at(start + dir * (t + k * 0.5 + 0.25) + inward * (SIDEWALK + 0.3) + Vector3(0, SLAB_HEIGHT + 0.6, 0), Vector3(0.04, 1.2, 0.04), FENCE)
			_add_box_collider(block.body, _t(c + Vector3(0, 0.6, 0)), size + Vector3(0, 1.2, 0) + Vector3(absf(inward.x), 0, absf(inward.z)) * 0.2)
		t += seg


func _build_park_gate(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	# Opening in the fence (and no props on the footpath in front of it).
	_reserve(block, xf, Vector3(-w * 0.5 - 1.0, 0, 0), Vector3(w * 0.5 + 1.0, 0, -SIDEWALK - 2.0), "walkway")
	var z := -SIDEWALK - 0.3
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * (w * 0.5 + 0.4), 2.0, z)
		kit.add_box(xf * _t(p), Vector3(0.7, 4.0, 0.7), Color(0.85, 0.82, 0.75))
		kit.add_sphere(xf * _t(p + Vector3(0, 2.2, 0)), 0.45, FENCE, 3, 8)
		_add_box_collider(block.body, xf * _t(p), Vector3(0.7, 4.0, 0.7))
	kit.add_box(xf * _t(Vector3(0, 4.3, z)), Vector3(w + 1.6, 0.6, 0.5), FENCE)
	_add_board(kit, xf * _t(Vector3(0, 4.3, z + 0.3)), Vector2(w * 0.9, 0.55), FENCE, title, Color(1, 1, 0.85), 120.0)


## "মোহাম্মদপুরে স্বাগতম" arch over আসাদ এভিনিউ, where Mohammadpur begins.
func _build_welcome_arch(kit) -> void:
	var x := -202.0
	var col := Color(0.1, 0.45, 0.3)
	for z: float in [-8.5, 8.5]:
		kit.add_box_at(Vector3(x, 3.0 + SLAB_HEIGHT, z), Vector3(0.7, 6.0, 0.7), col)
	kit.add_box_at(Vector3(x, 6.3, 0), Vector3(0.8, 0.7, 18.0), col)
	var board := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x + 0.45, 5.3, 0))
	kit.add_box(board, Vector3(13.0, 1.2, 0.08), Color(0.95, 0.85, 0.2))
	_add_label("মোহাম্মদপুরে স্বাগতম", board * _t(Vector3(0, 0, 0.05)), Vector2(12.0, 0.85), Color(0.6, 0.05, 0.1), 160.0)
	var back := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x - 0.45, 5.3, 0))
	kit.add_box(back, Vector3(13.0, 1.2, 0.08), Color(0.95, 0.85, 0.2))
	_add_label("আবার আসবেন", back * _t(Vector3(0, 0, 0.05)), Vector2(12.0, 0.85), Color(0.6, 0.05, 0.1), 160.0)


# --- Breakable props -----------------------------------------------------------------
# Stalls, tea stalls and benches are drawn into one mesh per block (few draw
# calls). Breaking one marks it broken and redraws that block's mesh without it;
# BreakableManager handles the hit, the flying debris and the repair later.

const PROP_SHAPES := {
	# kind: [footprint centre (local), half extents]
	"stall": [Vector3(0, 0.9, 0), Vector3(0.95, 0.9, 0.6)],
	"bench": [Vector3(0.3, 0.45, 0), Vector3(1.4, 0.45, 0.35)],
	"tea": [Vector3(0, 1.0, 0.1), Vector3(1.25, 1.0, 1.0)],
}


func _add_prop(block: Dictionary, kind: String, xf: Transform3D) -> Dictionary:
	var shape: Array = PROP_SHAPES[kind]
	var rec := {
		"id": props.size(), "kind": kind, "xf": xf, "seed": _rng.randi(),
		"block": block.index, "broken": false, "center": xf * shape[0], "half": shape[1],
		"labels": [], "colors": [] as Array[Color],
	}
	props.append(rec)
	return rec


func _draw_prop(kit, rec: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rec.seed
	match rec.kind:
		"stall":
			rec.colors = _add_vendor_stall(kit, rec.xf, rng)
		"bench":
			_add_bench_and_bin(kit, rec.xf)
			rec.colors = [WOOD, Color(0.3, 0.3, 0.32), Color(0.1, 0.5, 0.25)] as Array[Color]
		"tea":
			_add_tea_stall(kit, rec.xf)
			rec.colors = [WOOD, TIN, Color(0.85, 0.95, 1.0), Color(0.85, 0.1, 0.12), Color(0.95, 0.7, 0.3)] as Array[Color]


## Redraws one block's props, leaving out the broken ones.
func rebuild_block_props(block_index: int) -> void:
	var kit := MeshKit.new()
	for rec in props:
		if rec.block == block_index and not rec.broken:
			_draw_prop(kit, rec)
		if rec.block == block_index:
			for l in rec.labels:
				l.visible = not rec.broken
	var mesh := kit.build()
	var mi: MeshInstance3D = _prop_meshes.get(block_index)
	if mi == null:
		if mesh == null:
			return
		mi = MeshInstance3D.new()
		mi.name = "Block%dProps" % block_index
		mi.visibility_range_end = 110.0
		add_child(mi)
		_prop_meshes[block_index] = mi
	mi.mesh = mesh


# --- Sidewalk props --------------------------------------------------------------

func _build_sidewalk_props(block: Dictionary, start: Vector3, dir: Vector3, inward: Vector3, length: float) -> void:
	var kit = block.kit
	var style: String = block.style
	var face := Basis.looking_at(inward)
	var t := 9.0 + _rng.randf_range(0.0, 4.0)
	while t < length - 6.0:
		var p := start + dir * t + Vector3(0, SLAB_HEIGHT, 0)
		var probe := Rect2(Vector2(p.x, p.z) - Vector2(1.5, 1.5), Vector2(3, 3))
		probe = probe.merge(Rect2(Vector2(p.x, p.z) + Vector2(inward.x, inward.z) * 3.0 - Vector2(1.5, 1.5), Vector2(3, 3)))
		if _is_free(block.walkway, probe):
			match style:
				"market":
					_add_prop(block, "stall", Transform3D(face, p + inward * 2.4))
				"residential", "campus":
					_add_tree(kit, p + inward * 1.0, block.body)
				_:
					if _rng.randf() < 0.5:
						_add_tree(kit, p + inward * 1.0, block.body)
					else:
						_add_prop(block, "bench", Transform3D(face, p + inward * 2.3))
		t += (8.0 if style == "market" else 11.0) + _rng.randf_range(0.0, 4.0)


func _add_tree(kit, base: Vector3, body: StaticBody3D = null) -> void:
	var h := _rng.randf_range(2.6, 3.6)
	if body:
		_add_box_collider(body, _t(base + Vector3(0, 1.2, 0)), Vector3(0.28, 2.4, 0.28))
	kit.add_cylinder(_t(base + Vector3(0, h * 0.5, 0)), 0.13, h, Color(0.4, 0.28, 0.15), 6)
	var leaf := LEAF.lightened(_rng.randf_range(0.0, 0.2))
	kit.add_sphere(Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), base + Vector3(0, h + 0.6, 0)), 1.5, leaf, 3, 7)
	kit.add_sphere(_t(base + Vector3(0.5, h + 1.4, 0.3)), 1.0, leaf.lightened(0.1), 3, 6)
	# Painted trunk base (white band), common on Dhaka roadside trees.
	kit.add_cylinder(_t(base + Vector3(0, 0.4, 0)), 0.15, 0.8, Color(0.95, 0.95, 0.92), 6)


func _add_vendor_stall(kit, xf: Transform3D, rng: RandomNumberGenerator) -> Array[Color]:
	# Small table with produce or goods under a colourful umbrella.
	var used: Array[Color] = [WOOD]
	kit.add_box(xf * _t(Vector3(0, 0.75, 0)), Vector3(1.6, 0.08, 0.9), WOOD)
	for x: float in [-0.7, 0.7]:
		kit.add_box(xf * _t(Vector3(x, 0.37, 0)), Vector3(0.08, 0.74, 0.8), WOOD)
	for i in 6:
		var col: Color = PRODUCE_COLORS[rng.randi() % PRODUCE_COLORS.size()]
		kit.add_sphere(xf * _t(Vector3(-0.6 + (i % 3) * 0.6, 0.88, -0.2 + (i / 3) * 0.4)), 0.17, col, 3, 6)
		used.append(col)
	kit.add_cylinder(xf * _t(Vector3(0, 1.3, 0)), 0.03, 1.2, Color(0.3, 0.3, 0.3), 4)
	var umb: Color = AWNING_COLORS[rng.randi() % AWNING_COLORS.size()]
	used.append(umb)
	var apex := xf * Vector3(0, 2.25, 0)
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := xf * Vector3(cos(a0) * 1.3, 1.85, sin(a0) * 1.3)
		var p1 := xf * Vector3(cos(a1) * 1.3, 1.85, sin(a1) * 1.3)
		var col := umb if i % 2 == 0 else Color(0.95, 0.95, 0.9)
		kit.add_tri(apex, p1, p0, col)
		kit.add_tri(apex, p0, p1, col.darkened(0.3))
	return used


func _add_bench_and_bin(kit, xf: Transform3D) -> void:
	kit.add_box(xf * _t(Vector3(0, 0.45, 0)), Vector3(1.6, 0.07, 0.42), WOOD)
	kit.add_box(xf * _t(Vector3(0, 0.75, -0.2)), Vector3(1.6, 0.35, 0.05), WOOD)
	for x: float in [-0.7, 0.7]:
		kit.add_box(xf * _t(Vector3(x, 0.22, 0)), Vector3(0.07, 0.45, 0.38), Color(0.3, 0.3, 0.32))
	kit.add_cylinder(xf * _t(Vector3(1.3, 0.4, 0)), 0.25, 0.8, Color(0.1, 0.5, 0.25), 8)


# --- Campus: BRAC University (ব্র্যাক বিশ্ববিদ্যালয়), Merul Badda ----------------------
#
# Loosely modelled on WOHA's real campus: a "club sandwich" with a public
# Campus Park on pilotis at ground level, nine academic floors floating above
# it in a deep grid of dark ash concrete with ash, glass and slatted
# bays, garden terraces and sky-garden voids, a green wall, a curved outdoor
# staircase, a reflecting pond, and a roof "umbrella" of solar panels around a
# green courtyard.

## Dark ash: the concrete grid, and slightly lighter ash panels in between.
const ASH_DARK := Color(0.29, 0.3, 0.31)
const ASH_PANEL := Color(0.41, 0.42, 0.43)
const GLASS_DARK := Color(0.17, 0.22, 0.27)
const SOLAR := Color(0.12, 0.18, 0.36)
const WATER := Color(0.26, 0.5, 0.58)
const HEDGE := Color(0.2, 0.48, 0.22)

## Low planters with hedges along the campus edge: the park is public, so
## there is no high wall, but you still can't ride through it.
func _build_campus_wall(block: Dictionary, start: Vector3, dir: Vector3, inward: Vector3, length: float) -> void:
	var kit = block.kit
	var seg := 4.0
	var t := SIDEWALK  # leave the corner sidewalks open
	while t < length - SIDEWALK - 0.1:
		var l := minf(seg, length - SIDEWALK - t)
		var c := start + dir * (t + l * 0.5) + inward * (SIDEWALK + 0.4) + Vector3(0, SLAB_HEIGHT, 0)
		var along := Vector2(absf(dir.x), absf(dir.z)) * l
		var r := Rect2(Vector2(c.x, c.z) - along * 0.5 - Vector2(0.4, 0.4), along + Vector2(0.8, 0.8))
		if _is_free(block.footprints, r):
			var size := Vector3(l, 0.6, 0.7) if absf(dir.x) > 0.5 else Vector3(0.7, 0.6, l)
			kit.add_box_at(c + Vector3(0, 0.3, 0), size, ASH_DARK)
			kit.add_box_at(c + Vector3(0, 0.95, 0), size * Vector3(0.95, 1.2, 0.85), HEDGE.lightened(_rng.randf_range(0.0, 0.12)))
			_add_box_collider(block.body, _t(c + Vector3(0, 0.65, 0)), size * Vector3(1, 2.2, 1))
		t += seg


func _build_campus_interior(block: Dictionary) -> void:
	var kit = block.kit
	var rect: Rect2 = block.rect
	var front: Vector3 = block.get("campus_front", Vector3.RIGHT)
	var c := rect.get_center()
	# Local space: origin at the block centre, +Z towards the entrance road.
	var xf := Transform3D(Basis.looking_at(-front), _v3(c, SLAB_HEIGHT))
	var half := minf(rect.size.x, rect.size.y) * 0.5 - SIDEWALK - 0.8
	var y := 0.012
	# Lawn of the Campus Park.
	kit.add_quad(xf * Vector3(-half, y, half), xf * Vector3(half, y, half), xf * Vector3(half, y, -half), xf * Vector3(-half, y, -half), Color(0.36, 0.62, 0.27))
	# Promenade from the entrance to the building, and the reflecting pond.
	var paving := Color(0.86, 0.83, 0.76)
	kit.add_quad(xf * Vector3(-2.6, y + 0.004, half), xf * Vector3(2.6, y + 0.004, half), xf * Vector3(2.6, y + 0.004, 4.0), xf * Vector3(-2.6, y + 0.004, 4.0), paving)
	for side: float in [-1.0, 1.0]:
		var px := side * 8.6
		kit.add_box(xf * _t(Vector3(px, 0.15, 11.0)), Vector3(11.6, 0.3, 6.6), ASH_DARK)
		kit.add_panel(xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(px, 0.31, 11.0)), Vector2(10.8, 5.8), WATER)
		for k in 3:  # lily pads
			kit.add_cylinder(xf * _t(Vector3(px - 3.0 + k * 3.0, 0.33, 10.0 + (k % 2) * 1.6)), 0.45, 0.02, Color(0.3, 0.6, 0.3), 8)
	_reserve(block, xf, Vector3(-half, 0, half), Vector3(half, 0, -half + 1.0))
	_build_brac_building(block, xf)
	_add_box_collider(block.body, xf * _t(Vector3(0, 0.5, 11.0)), Vector3(28.0, 1.0, 6.6))


func _build_brac_building(block: Dictionary, xf: Transform3D) -> void:
	var kit = block.kit
	var w := 30.0         # along local X
	var d := 18.0         # along local Z
	var cz := -4.0        # building centre (set back behind the pond)
	var park := 6.0       # height of the open Campus Park level
	var floors := 9
	var fh := 3.4
	var top := park + floors * fh
	var fz := cz + d * 0.5  # front face
	_add_box_collider(block.body, xf * _t(Vector3(0, top * 0.5, cz)), Vector3(w + 1.0, top, d + 1.0))

	# Campus Park: pilotis, planters and food kiosks under the building.
	for i in 7:
		for j in 3:
			var p := Vector3(-w * 0.5 + 1.0 + i * (w - 2.0) / 6.0, park * 0.5, cz - d * 0.5 + 1.5 + j * (d - 3.0) / 2.0)
			kit.add_cylinder(xf * _t(p), 0.45, park, ASH_DARK, 10)
	kit.add_box(xf * _t(Vector3(0, park - 0.3, cz)), Vector3(w, 0.6, d), ASH_DARK.darkened(0.1))
	for k in 4:
		var pp := Vector3(-10.0 + k * 6.6, 0.35, cz - 1.0 + (k % 2) * 3.0)
		kit.add_box(xf * _t(pp), Vector3(3.2, 0.7, 2.2), ASH_DARK)
		kit.add_sphere(xf * Transform3D(Basis().scaled(Vector3(1.4, 0.6, 1.0)), pp + Vector3(0, 0.75, 0)), 1.1, HEDGE.lightened(0.1), 3, 7)
	for k in 3:
		var kp := Vector3(-8.0 + k * 8.0, 1.2, cz - d * 0.5 + 3.0)
		kit.add_box(xf * _t(kp), Vector3(2.6, 2.4, 1.8), [ASH_PANEL, Color(0.95, 0.75, 0.2), Color(0.2, 0.55, 0.45)][k])
		kit.add_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.3), kp + Vector3(0, 1.35, 1.1)), Vector3(2.9, 0.06, 1.0), Color(0.95, 0.95, 0.9))

	# Curved concrete staircase wrapping up to the first academic level.
	var sc := Vector3(w * 0.5 + 3.0, 0, fz - 2.5)
	kit.add_cylinder(xf * _t(sc + Vector3(0, park * 0.5, 0)), 0.6, park, ASH_DARK, 10)
	var steps := 24
	for i in steps:
		var a := PI * 1.5 * i / steps
		var basis := Basis(Vector3.UP, -a)
		var pos := sc + basis * Vector3(2.0, 0, 0) + Vector3(0, park * (i + 0.5) / steps, 0)
		kit.add_box(xf * Transform3D(basis, pos), Vector3(2.4, 0.18, 0.8), ASH_DARK.lightened(0.05))
	kit.add_box(xf * _t(Vector3(w * 0.5 + 1.0, park - 0.1, fz - 2.5)), Vector3(3.0, 0.2, 2.6), ASH_DARK)

	# Academic floors: glass core inside a deep concrete grid.
	kit.add_box(xf * _t(Vector3(0, park + floors * fh * 0.5, cz)), Vector3(w - 0.8, floors * fh, d - 0.8), GLASS_DARK)
	for f in floors + 1:
		var sy := park + f * fh
		kit.add_box(xf * _t(Vector3(0, sy, cz)), Vector3(w + 0.9, 0.35, d + 0.9), ASH_DARK)
	var bays := 12
	var bay_w := w / bays
	# Sky-garden voids: [first bay, last bay, first floor, last floor].
	var voids := [[1, 4, 2, 4], [7, 10, 5, 7]]
	for side: float in [1.0, -1.0]:
		var zf := cz + side * (d * 0.5 + 0.02)
		var face := Basis() if side > 0.0 else Basis(Vector3.UP, PI)
		for b in bays + 1:
			var fx := -w * 0.5 + b * bay_w
			kit.add_box(xf * _t(Vector3(fx, park + floors * fh * 0.5, zf + side * 0.35)), Vector3(0.32, floors * fh, 0.8), ASH_DARK)
		for f in floors:
			for b in bays:
				var bx := -w * 0.5 + (b + 0.5) * bay_w
				var by := park + (f + 0.5) * fh
				var in_void := false
				if side > 0.0:
					for v in voids:
						if b >= v[0] and b <= v[1] and f >= v[2] and f <= v[3]:
							in_void = true
				var pxf := xf * Transform3D(face, Vector3(bx, by, zf))
				if in_void:
					kit.add_panel(pxf, Vector2(bay_w - 0.3, fh - 0.35), Color(0.12, 0.2, 0.14))
					continue
				match (b * 7 + f * 3) % 5:
					0, 3:
						kit.add_panel(pxf, Vector2(bay_w - 0.3, fh - 0.35), ASH_PANEL.darkened(((b + f) % 3) * 0.06))
					1:
						for k in 4:  # horizontal slats
							kit.add_panel(xf * Transform3D(face, Vector3(bx, by - 1.1 + k * 0.7, zf + side * 0.01)), Vector2(bay_w - 0.3, 0.16), ASH_DARK.lightened(0.1))
					_:
						pass  # clear glass
		# Garden terraces every third floor.
		for f: int in [3, 6, 9]:
			var ty := park + f * fh + 0.45
			kit.add_box(xf * _t(Vector3(0, ty, cz + side * (d * 0.5 + 0.55))), Vector3(w + 0.6, 0.6, 0.7), HEDGE)
			for k in 10:
				kit.add_panel(xf * Transform3D(face, Vector3(-w * 0.5 + 1.5 + k * 3.0, ty - 0.9, zf + side * 0.92)), Vector2(1.6, 1.2), HEDGE.lightened(0.05 * (k % 3)))
	# Trees growing in the sky-garden voids.
	for v in voids:
		for f in range(v[2], v[3] + 1):
			for b in range(v[0], v[1] + 1, 2):
				var tp := Vector3(-w * 0.5 + (b + 1.0) * bay_w, park + f * fh + 1.2, fz + 0.4)
				kit.add_sphere(xf * Transform3D(Basis().scaled(Vector3(1.3, 0.8, 0.8)), tp), 1.0, LEAF.lightened(_rng.randf_range(0.0, 0.2)), 3, 7)
	# Side walls: concrete fins, terracotta on one side and a green wall on the other.
	for side: float in [-1.0, 1.0]:
		var sx := side * (w * 0.5 + 0.02)
		var face := Basis(Vector3.UP, PI * 0.5 * side)
		for k in 7:
			var fzk := cz - d * 0.5 + k * d / 6.0
			kit.add_box(xf * _t(Vector3(sx + side * 0.35, park + floors * fh * 0.5, fzk)), Vector3(0.8, floors * fh, 0.32), ASH_DARK)
		for f in floors:
			for k in 6:
				var col := ASH_PANEL if side > 0.0 else HEDGE.lightened(0.04 * ((k + f) % 4))
				kit.add_panel(xf * Transform3D(face, Vector3(sx, park + (f + 0.5) * fh, cz - d * 0.5 + (k + 0.5) * d / 6.0)), Vector2(d / 6.0 - 0.3, fh - 0.35), col)

	# Name band on the front of the first academic level.
	kit.add_box(xf * _t(Vector3(0, park + 0.9, fz + 0.75)), Vector3(18.0, 1.4, 0.12), ASH_PANEL)
	_add_label("ব্র্যাক বিশ্ববিদ্যালয়", xf * _t(Vector3(0, park + 0.9, fz + 0.82)), Vector2(16.5, 1.0), Color(1, 0.97, 0.9), 200.0)

	# Roof: green courtyard under a "tropical umbrella" of solar panels.
	kit.add_box(xf * _t(Vector3(0, top + 0.35, cz)), Vector3(w * 0.45, 0.7, d * 0.5), HEDGE)
	for k in 4:
		kit.add_sphere(_t(xf * Vector3(-5.0 + k * 3.3, top + 1.4, cz + (k % 2) * 2.0 - 1.0)), 1.0, LEAF.lightened(0.1), 3, 7)
	var ch := top + 5.0
	for i in 4:
		for j in 2:
			var cp := Vector3(-w * 0.5 + 1.0 + i * (w - 2.0) / 3.0, (top + ch) * 0.5, cz - d * 0.5 + 1.0 + j * (d - 2.0))
			kit.add_cylinder(xf * _t(cp), 0.3, ch - top, ASH_DARK, 8)
	var ow := w + 5.0
	var od := d + 5.0
	var iw := w * 0.45
	var idp := d * 0.5
	# Four solar-panel wings around the open centre.
	for wing in [[Vector3(0, ch, cz + (od + idp) * 0.25), Vector3(ow, 0.3, (od - idp) * 0.5)],
			[Vector3(0, ch, cz - (od + idp) * 0.25), Vector3(ow, 0.3, (od - idp) * 0.5)],
			[Vector3((ow + iw) * 0.25, ch, cz), Vector3((ow - iw) * 0.5, 0.3, idp)],
			[Vector3(-(ow + iw) * 0.25, ch, cz), Vector3((ow - iw) * 0.5, 0.3, idp)]]:
		kit.add_box(xf * _t(wing[0]), wing[1], SOLAR)
		kit.add_box(xf * _t(wing[0] - Vector3(0, 0.25, 0)), wing[1] + Vector3(0.3, -0.1, 0.3), Color(0.95, 0.95, 0.93))
	# Panel grid lines on top of the canopy.
	var lines := Color(0.45, 0.55, 0.75)
	for k in 13:
		var lx := -ow * 0.5 + k * ow / 12.0
		kit.add_panel(xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(lx, ch + 0.16, cz + (od + idp) * 0.25)), Vector2(0.08, (od - idp) * 0.5), lines)
		kit.add_panel(xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(lx, ch + 0.16, cz - (od + idp) * 0.25)), Vector2(0.08, (od - idp) * 0.5), lines)


# --- Landmarks -------------------------------------------------------------------

func _build_landmark(lm: Dictionary) -> void:
	var curb: Vector2 = lm.curb
	var facing: Vector2 = lm.facing
	var block := _block_at(curb)
	if block.is_empty():
		push_warning("Landmark %s is not on a block edge" % lm.title)
		return
	# Local space: origin on the curb (top of the sidewalk), +Z towards the road.
	var xf := Transform3D(Basis.looking_at(-_v3(facing)), _v3(curb, SLAB_HEIGHT))
	var w: float = lm.width
	match lm.kind:
		"new_market":
			_build_new_market(block, xf, w, lm.title)
		"footbridge":
			_build_footbridge(block, xf, curb, facing, lm.title)
		"university":
			_build_university_gate(block, xf, w, lm.title)
		"bus_stand":
			_build_bus_stand(block, xf, w, lm.title)
		"bazar":
			_build_bazar(block, xf, w, lm.title)
		"tea_stall":
			_reserve(block, xf, Vector3(-2.5, 0, -0.2), Vector3(2.5, 0, -SIDEWALK), "walkway")
			var tea_xf := xf * _t(Vector3(0, 0, -1.7))
			var tea := _add_prop(block, "tea", tea_xf)
			tea.labels.append(_add_label(lm.title, tea_xf * _t(Vector3(0, 2.62, 0.59)), Vector2(1.8, 0.36), Color(1, 0.95, 0.4)))
		"residential_gate":
			_build_residential_gate(block, xf, w, lm.title)
		"mosque":
			_build_mosque(block, xf, w, lm.title)
		"ghat":
			_build_ghat(block, xf, w, lm.title)
		"park_gate":
			_build_park_gate(block, xf, w, lm.title)
		"garage":
			_build_garage(block, xf, w, lm.title)
		"aarong":
			_build_aarong(block, xf, w, lm.title)


func _build_new_market(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	var depth := 16.0
	var h := 7.5
	var front := -SIDEWALK
	var cx := Vector3(0, 0, front - depth * 0.5)
	_reserve(block, xf, Vector3(-w * 0.5, 0, front), Vector3(w * 0.5, 0, front - depth))
	var cream := Color(0.96, 0.9, 0.74)
	kit.add_box(xf * _t(cx + Vector3(0, h * 0.5, 0)), Vector3(w, h, depth), cream)
	_add_box_collider(block.body, xf * _t(cx + Vector3(0, h * 0.5, 0)), Vector3(w, h, depth))
	# Arcade: dark shop fronts behind a row of columns with arches.
	kit.add_panel(xf * _t(Vector3(0, 2.0, front + 0.01)), Vector2(w - 1.0, 4.0), Color(0.2, 0.14, 0.1))
	var cols := int(w / 3.0)
	for i in cols + 1:
		var x := -w * 0.5 + 0.5 + i * (w - 1.0) / cols
		kit.add_box(xf * _t(Vector3(x, 2.2, front + 0.5)), Vector3(0.5, 4.4, 0.5), Color(0.85, 0.3, 0.2))
		_add_box_collider(block.body, xf * _t(Vector3(x, 1.5, front + 0.5)), Vector3(0.5, 3.0, 0.5))
	kit.add_box(xf * _t(Vector3(0, 4.6, front + 0.5)), Vector3(w, 0.5, 0.7), Color(0.85, 0.3, 0.2))
	for i in cols:
		var x := -w * 0.5 + 0.5 + (i + 0.5) * (w - 1.0) / cols
		kit.add_panel(xf * _t(Vector3(x, 1.3, front + 0.03)), Vector2(1.8, 2.0), SIGN_COLORS[i % SIGN_COLORS.size()])
	# Upper floor windows and a red band.
	for i in int(w / 2.5):
		kit.add_panel(xf * _t(Vector3(-w * 0.5 + 1.25 + i * 2.5, 6.0, front + 0.02)), Vector2(1.4, 1.2), Color(0.18, 0.25, 0.32))
	kit.add_box(xf * _t(Vector3(0, h, front + 0.1)), Vector3(w + 0.2, 0.5, 0.4), Color(0.85, 0.3, 0.2))
	# Big name board on the roof and Bangladesh flags.
	_add_board(kit, xf * _t(Vector3(0, h + 1.3, front + 0.3)), Vector2(w * 0.6, 1.8), Color(0.05, 0.45, 0.25), title, Color(1, 1, 0.9), 120.0)
	for x: float in [-w * 0.45, w * 0.45]:
		_add_flag(kit, xf * _t(Vector3(x, h, front - 0.5)))


func _add_flag(kit, xf: Transform3D) -> void:
	kit.add_cylinder(xf * _t(Vector3(0, 1.5, 0)), 0.04, 3.0, Color(0.8, 0.8, 0.8), 4)
	# Bangladesh flag: green field with a red disc slightly towards the pole.
	kit.add_box(xf * _t(Vector3(0.75, 2.6, 0)), Vector3(1.4, 0.84, 0.02), Color(0.0, 0.42, 0.31))
	var disc := xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.68, 2.6, 0))
	kit.add_cylinder(disc, 0.28, 0.04, Color(0.86, 0.1, 0.15), 12)


func _build_footbridge(block: Dictionary, xf: Transform3D, curb: Vector2, facing: Vector2, title: String) -> void:
	var kit = block.kit
	# Measure the road width under the bridge.
	var span := 0.0
	while CityLayout.is_road(curb.x + facing.x * (span + 0.25), curb.y + facing.y * (span + 0.25)) and span < 40.0:
		span += 0.5
	var deck_y := 6.0
	var steel := Color(0.25, 0.42, 0.55)
	var stair_z := -2.65  # keeps the 1.5 m walking line clear
	var near_far := [stair_z, span - stair_z]
	var deck_len := span - stair_z * 2.0 + 1.6
	kit.add_box(xf * _t(Vector3(0, deck_y, span * 0.5)), Vector3(2.2, 0.3, deck_len), Color(0.7, 0.7, 0.68))
	for side: float in [-1.1, 1.1]:
		kit.add_box(xf * _t(Vector3(side, deck_y + 0.6, span * 0.5)), Vector3(0.06, 0.06, deck_len), steel)
		kit.add_box(xf * _t(Vector3(side, deck_y + 0.3, span * 0.5)), Vector3(0.04, 0.6, deck_len), steel.lightened(0.3))
		# Banner with the area name facing the traffic on both sides.
		var banner := xf * Transform3D(Basis(Vector3.UP, PI * 0.5 * signf(side)), Vector3(side * 1.12, deck_y - 0.55, span * 0.5))
		kit.add_box(banner, Vector3(minf(span, 8.0), 0.8, 0.05), Color(0.85, 0.1, 0.15))
		_add_label(title, banner * _t(Vector3(0, 0, 0.035)), Vector2(minf(span, 8.0) * 0.8, 0.55), Color(1, 1, 0.9), 120.0)
	for z: float in near_far:
		# Columns under the deck end and a stepped staircase along the sidewalk.
		for x: float in [0.8, -0.8]:
			kit.add_box(xf * _t(Vector3(x + 0.2, deck_y * 0.5, z)), Vector3(0.3, deck_y, 0.3), steel)
		var steps := 15
		var run := 0.6
		for i in steps:
			var top := deck_y * (steps - i) / steps
			kit.add_box(xf * _t(Vector3(-1.4 - i * run, top * 0.5, z)), Vector3(run, top, 1.6), Color(0.68, 0.68, 0.66))
		kit.add_box(xf * _t(Vector3(-1.4 - steps * run * 0.5, deck_y * 0.5 + 0.9, z + 0.82)), Vector3(steps * run, 0.05, 0.05), steel)
		var stair_body: StaticBody3D = _block_at(Vector2((xf * Vector3(0, 0, z)).x, (xf * Vector3(0, 0, z)).z)).get("body", block.body)
		_add_box_collider(stair_body, xf * _t(Vector3(-1.4 - steps * run * 0.5 + 0.3, 1.5, z)), Vector3(steps * run, 3.0, 1.6))
		for x: float in [0.8, -0.8]:
			_add_box_collider(stair_body, xf * _t(Vector3(x + 0.2, 1.5, z)), Vector3(0.3, 3.0, 0.3))
		var a := Vector3(1.2, 0, z - 0.9)
		var b := Vector3(-1.4 - steps * run - 0.3, 0, z + 0.9)
		_reserve(block, xf, a, b, "walkway")
		var far := xf * Vector3(0, 0, z)
		_reserve(_block_at(Vector2(far.x, far.z)), xf, a, b, "walkway")


## Modern open entrance to the BRAC University campus park: two concrete
## sign walls with the name, bollards and a small security booth.
func _build_university_gate(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	block["campus_front"] = xf.basis.z  # the campus faces this road
	var z := -SIDEWALK - 0.8
	# The opening (no hedges) spans the sign walls too, so the names stay visible.
	_reserve(block, xf, Vector3(-w * 0.5 - 5.0, 0, -SIDEWALK + 0.2), Vector3(w * 0.5 + 5.0, 0, -SIDEWALK - 6.0))
	_reserve(block, xf, Vector3(-w * 0.5 - 5.0, 0, 0), Vector3(w * 0.5 + 5.0, 0, -SIDEWALK), "walkway")
	for side: float in [-1.0, 1.0]:
		var wall_xf := xf * Transform3D(Basis(Vector3.UP, -side * 0.25), Vector3(side * (w * 0.5 + 2.2), 1.1, z))
		kit.add_box(wall_xf, Vector3(4.4, 2.2, 0.5), ASH_DARK)
		kit.add_box(wall_xf * _t(Vector3(0, 0.75, 0.0)), Vector3(4.5, 0.35, 0.55), ASH_PANEL)
		_add_box_collider(block.body, wall_xf, Vector3(4.4, 2.2, 0.5))
		_add_label(title, wall_xf * _t(Vector3(0, -0.15, 0.27)), Vector2(4.0, 0.7), Color(0.97, 0.96, 0.92), 120.0)
		for k in 3:
			kit.add_cylinder(xf * _t(Vector3(side * (w * 0.5 - 0.6 - k * 1.6), 0.45, -SIDEWALK + 0.3)), 0.12, 0.9, Color(0.3, 0.3, 0.32), 6)
	# Security booth.
	var booth := Vector3(w * 0.5 + 2.4, 1.3, z - 3.0)
	kit.add_box(xf * _t(booth), Vector3(1.8, 2.6, 1.8), ASH_DARK)
	kit.add_panel(xf * _t(booth + Vector3(0, 0.3, 0.91)), Vector2(1.2, 0.8), GLASS_DARK)
	kit.add_box(xf * _t(booth + Vector3(0, 1.4, 0)), Vector3(2.3, 0.2, 2.3), ASH_PANEL)


func _build_bus_stand(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	_reserve(block, xf, Vector3(-w * 0.5, 0, -0.2), Vector3(w * 0.5, 0, -SIDEWALK), "walkway")
	var green := Color(0.05, 0.45, 0.25)
	var z := -2.5  # keeps the 1.5 m walking line clear
	var l := w - 1.5
	for x: float in [-l * 0.5, l * 0.5]:
		kit.add_box(xf * _t(Vector3(x, 1.3, z - 0.8)), Vector3(0.12, 2.6, 0.12), green)
		kit.add_box(xf * _t(Vector3(x, 1.2, z + 0.8)), Vector3(0.12, 2.4, 0.12), green)
	kit.add_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 2.6, z)), Vector3(l + 0.6, 0.1, 2.2), Color(0.85, 0.85, 0.82))
	kit.add_box(xf * _t(Vector3(0, 1.4, z - 0.85)), Vector3(l, 1.6, 0.05), Color(0.95, 0.75, 0.15))
	kit.add_box(xf * _t(Vector3(0, 0.45, z - 0.55)), Vector3(l - 0.4, 0.08, 0.45), WOOD)
	_add_board(kit, xf * _t(Vector3(0, 3.05, z + 0.9)), Vector2(3.4, 0.6), green, title)
	# Bus stop pole sign at the curb.
	kit.add_cylinder(xf * _t(Vector3(l * 0.5 + 1.0, 1.4, -0.5)), 0.05, 2.8, Color(0.6, 0.6, 0.6), 6)
	var disc := xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(l * 0.5 + 1.0, 2.9, -0.5))
	kit.add_cylinder(disc, 0.35, 0.05, Color(0.85, 0.1, 0.15), 12)
	_add_prop(block, "bench", xf * _t(Vector3(-l * 0.5 - 2.0, 0, -2.6)))
	# The shelter is solid (its open front stays clear of the walking line).
	_add_box_collider(block.body, xf * _t(Vector3(0, 1.3, z - 0.2)), Vector3(l + 0.3, 2.6, 1.4))


func _build_bazar(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	# Open market shed: tin roof on posts, rows of produce and baskets.
	var kit = block.kit
	var depth := 12.0
	var front := -SIDEWALK
	_reserve(block, xf, Vector3(-w * 0.5, 0, front), Vector3(w * 0.5, 0, front - depth))
	var posts_x := int(w / 4.0)
	for i in posts_x + 1:
		for zi in 3:
			var p := Vector3(-w * 0.5 + i * w / posts_x, 2.2, front - 0.3 - zi * (depth - 0.6) / 2.0)
			kit.add_box(xf * _t(p), Vector3(0.18, 4.4, 0.18), WOOD)
	for side: float in [-1.0, 1.0]:
		var roof := xf * Transform3D(Basis(Vector3.RIGHT, -0.22 * side), Vector3(0, 4.75, front - depth * 0.5 + side * depth * 0.25))
		kit.add_box(roof, Vector3(w + 1.0, 0.06, depth * 0.52), TIN if side > 0 else TIN.darkened(0.1))
	_add_box_collider(block.body, xf * _t(Vector3(0, 0.5, front - depth * 0.5)), Vector3(w, 1.0, depth))
	for row in 3:
		var rz := front - 2.0 - row * 3.6
		for i in int(w / 2.2):
			var sx := -w * 0.5 + 1.1 + i * 2.2
			kit.add_box(xf * _t(Vector3(sx, 0.4, rz)), Vector3(1.8, 0.8, 1.2), WOOD.darkened(0.15))
			var col: Color = PRODUCE_COLORS[_rng.randi() % PRODUCE_COLORS.size()]
			for k in 4:
				kit.add_sphere(xf * _t(Vector3(sx - 0.55 + k * 0.37, 0.95, rz)), 0.22, col.lightened(k * 0.05), 3, 6)
			kit.add_cylinder(xf * _t(Vector3(sx + 0.6, 0.2, rz + 0.9)), 0.3, 0.4, Color(0.75, 0.6, 0.3), 8)
	_add_board(kit, xf * _t(Vector3(0, 5.3, front - 0.2)), Vector2(minf(w * 0.7, 10.0), 1.3), Color(0.85, 0.1, 0.12), title, Color(1, 1, 0.85), 120.0)


func _build_residential_gate(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	var z := -SIDEWALK - 0.3
	_reserve(block, xf, Vector3(-w * 0.5 - 1.0, 0, -SIDEWALK + 0.2), Vector3(w * 0.5 + 1.0, 0, -SIDEWALK - 30.0))
	var col := Color(0.92, 0.88, 0.8)
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * (w * 0.5 + 0.4), 2.1, z)
		kit.add_box(xf * _t(p), Vector3(0.8, 4.2, 0.8), col)
		_add_box_collider(block.body, xf * _t(p), Vector3(0.8, 4.2, 0.8))
	kit.add_box(xf * _t(Vector3(0, 4.6, z)), Vector3(w + 1.6, 0.9, 0.6), Color(0.1, 0.45, 0.3))
	_add_board(kit, xf * _t(Vector3(0, 4.6, z + 0.35)), Vector2(w * 0.8, 0.7), Color(0.1, 0.45, 0.3), title, Color(1, 1, 0.9), 120.0)
	# A quiet inner lane with trees.
	for i in 4:
		for side: float in [-1.0, 1.0]:
			_add_tree(kit, xf * Vector3(side * (w * 0.5 - 0.5), 0, z - 4.0 - i * 6.0), block.body)


func _build_mosque(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	var depth := 14.0
	var front := -SIDEWALK - 1.0
	var c := Vector3(0, 0, front - depth * 0.5)
	_reserve(block, xf, Vector3(-w * 0.5, 0, -SIDEWALK), Vector3(w * 0.5, 0, front - depth))
	var white := Color(0.96, 0.96, 0.93)
	var green := Color(0.08, 0.5, 0.32)
	var hall_h := 6.0
	kit.add_box(xf * _t(c + Vector3(0, hall_h * 0.5, 0)), Vector3(w - 3.0, hall_h, depth), white)
	_add_box_collider(block.body, xf * _t(c + Vector3(0, hall_h * 0.5, 0)), Vector3(w - 3.0, hall_h, depth))
	kit.add_box(xf * _t(c + Vector3(0, hall_h + 0.2, 0)), Vector3(w - 2.6, 0.4, depth + 0.4), green)
	if "সাত গম্বুজ" in title:
		# Seven domes, like the real Saat Gambuj Mosque: three over the prayer
		# hall and four on the corner towers.
		var dome := Color(0.95, 0.92, 0.88)
		for x: float in [-4.0, 0.0, 4.0]:
			var p := c + Vector3(x, hall_h + 0.4, 0)
			kit.add_sphere(Transform3D(xf.basis.scaled(Vector3(1, 0.9, 1)), xf * p), 2.1, dome, 4, 10)
			kit.add_cylinder(xf * _t(p + Vector3(0, 2.2, 0)), 0.06, 0.6, Color(0.85, 0.7, 0.2), 4)
		var hw := (w - 3.0) * 0.5
		for cx: float in [-hw, hw]:
			for cz: float in [-7.0, 7.0]:
				var t := c + Vector3(cx, 0, cz)
				kit.add_cylinder(xf * _t(t + Vector3(0, hall_h * 0.5 + 0.8, 0)), 0.75, hall_h + 1.6, Color(0.82, 0.42, 0.32), 8)
				kit.add_sphere(xf * _t(t + Vector3(0, hall_h + 1.7, 0)), 0.8, dome, 3, 8)
	else:
		kit.add_sphere(Transform3D(xf.basis.scaled(Vector3(1, 0.85, 1)), xf * (c + Vector3(0, hall_h + 0.4, 0))), 4.0, Color(0.55, 0.85, 0.7), 5, 12)
		kit.add_cylinder(xf * _t(c + Vector3(0, hall_h + 4.2, 0)), 0.08, 1.2, Color(0.85, 0.7, 0.2), 4)
		kit.add_sphere(xf * _t(c + Vector3(0, hall_h + 4.9, 0)), 0.22, Color(0.95, 0.8, 0.2), 3, 6)
	# Arched doorways (dark panels with green frames).
	for i in 3:
		var x := -3.0 + i * 3.0
		kit.add_panel(xf * _t(Vector3(x, 1.7, front + 0.02)), Vector2(1.6, 3.0), Color(0.15, 0.25, 0.2))
		kit.add_panel(xf * _t(Vector3(x, 3.4, front + 0.02)), Vector2(1.9, 0.35), green)
	# Minaret.
	var m := Vector3(w * 0.5 - 1.0, 0, front - 1.0)
	kit.add_cylinder(xf * _t(m + Vector3(0, 7.5, 0)), 0.8, 15.0, white, 10)
	_add_box_collider(block.body, xf * _t(m + Vector3(0, 7.5, 0)), Vector3(1.6, 15.0, 1.6))
	kit.add_cylinder(xf * _t(m + Vector3(0, 11.5, 0)), 1.1, 0.4, green, 10)
	kit.add_sphere(xf * _t(m + Vector3(0, 15.2, 0)), 0.9, green, 4, 10)
	_add_board(kit, xf * _t(Vector3(-1.0, hall_h - 1.0, front + 0.1)), Vector2(8.0, 1.0), green, title, Color(1, 1, 0.9))


## Rickshaw mechanic: an open workshop with tyres, tools and a painted repair
## bay on the road in front of it.
## Aarong (আড়ং): a three-storey showroom in cream with terracotta fins, a
## glass ground floor full of colourful saris and kurtas, and the lower-case
## "aarong" name in the brand's red over the door and on the roof.
const AARONG_RED := Color(0.78, 0.11, 0.14)
const TERRACOTTA := Color(0.72, 0.36, 0.22)


func _build_aarong(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	var depth := 14.0
	var floor_h := 3.6
	var h := floor_h * 3.0
	var front := -SIDEWALK - 0.6
	var cx := Vector3(0, 0, front - depth * 0.5)
	_reserve(block, xf, Vector3(-w * 0.5 - 0.5, 0, -SIDEWALK + 0.2), Vector3(w * 0.5 + 0.5, 0, front - depth))
	var cream := Color(0.95, 0.91, 0.82)
	kit.add_box(xf * _t(cx + Vector3(0, h * 0.5, 0)), Vector3(w, h, depth), cream)
	_add_box_collider(block.body, xf * _t(cx + Vector3(0, h * 0.5, 0)), Vector3(w, h, depth))
	# Ground floor: a glass shop front framed in terracotta, with a door.
	var glass := Color(0.2, 0.27, 0.32)
	kit.add_panel(xf * _t(Vector3(0, 1.6, front + 0.02)), Vector2(w - 1.0, 3.0), glass)
	kit.add_box(xf * _t(Vector3(0, floor_h - 0.25, front + 0.15)), Vector3(w, 0.5, 0.3), TERRACOTTA)
	kit.add_box(xf * _t(Vector3(0, 0.1, front + 0.4)), Vector3(w, 0.2, 0.8), Color(0.55, 0.5, 0.45))  # front step
	for x: float in [-w * 0.5 + 0.25, w * 0.5 - 0.25]:
		kit.add_box(xf * _t(Vector3(x, floor_h * 0.5, front + 0.15)), Vector3(0.5, floor_h, 0.3), TERRACOTTA)
	kit.add_panel(xf * _t(Vector3(0, 1.25, front + 0.05)), Vector2(2.4, 2.5), Color(0.75, 0.82, 0.85))  # glass doors
	kit.add_panel(xf * _t(Vector3(0, 1.25, front + 0.06)), Vector2(0.06, 2.5), Color(0.3, 0.3, 0.3))
	# Display windows: saris and kurtas on mannequins either side of the door.
	var cloth := [Color(0.85, 0.1, 0.35), Color(0.95, 0.75, 0.1), Color(0.1, 0.55, 0.35),
		Color(0.9, 0.4, 0.1), Color(0.35, 0.2, 0.6), Color(0.95, 0.95, 0.9), Color(0.75, 0.05, 0.1)]
	var i := 0
	for side: float in [-1.0, 1.0]:
		for k in 4:
			var x := side * (2.4 + k * (w * 0.5 - 3.4) / 4.0 + 0.6)
			var col: Color = cloth[i % cloth.size()]
			i += 1
			kit.add_box(xf * _t(Vector3(x, 1.25, front - 0.45)), Vector3(0.55, 1.7, 0.3), col)  # draped cloth
			kit.add_cylinder(xf * _t(Vector3(x, 2.25, front - 0.45)), 0.13, 0.26, Color(0.85, 0.75, 0.62), 8)  # head
			kit.add_box(xf * _t(Vector3(x + 0.18, 1.5, front - 0.3)), Vector3(0.12, 1.1, 0.05), col.lightened(0.25))  # anchal
	# Upper floors: windows behind rows of terracotta fins, a crafts motif.
	for f in 2:
		var y := floor_h * (f + 1.5)
		kit.add_panel(xf * _t(Vector3(0, y, front + 0.02)), Vector2(w - 1.0, floor_h - 0.9), glass)
		var fins := int(w / 0.9)
		for k in fins + 1:
			var x := -w * 0.5 + 0.5 + k * (w - 1.0) / fins
			kit.add_box(xf * _t(Vector3(x, y, front + 0.3)), Vector3(0.14, floor_h - 0.6, 0.5), TERRACOTTA)
		kit.add_box(xf * _t(Vector3(0, floor_h * (f + 2) - 0.2, front + 0.2)), Vector3(w, 0.4, 0.4), cream.darkened(0.08))
	# The name over the door: "aarong" in red on white, "আড়ং" below.
	var sign_xf := xf * _t(Vector3(0, floor_h + 0.35, front + 0.55))
	kit.add_box(sign_xf, Vector3(12.0, 2.5, 0.12), Color(0.98, 0.97, 0.95))
	_add_label("aarong", sign_xf * _t(Vector3(0, 0.35, 0.07)), Vector2(11.0, 1.55), AARONG_RED, 150.0)
	_add_label(title, sign_xf * _t(Vector3(0, -0.8, 0.07)), Vector2(4.0, 0.7), AARONG_RED, 90.0)
	# And big on the roof, readable from down the road both ways.
	var roof_xf := xf * _t(Vector3(0, h + 2.0, front - 0.6))
	kit.add_box(roof_xf, Vector3(17.0, 3.4, 0.15), Color(0.98, 0.97, 0.95))
	for k: float in [-6.5, 0.0, 6.5]:
		kit.add_box(xf * _t(Vector3(k, h + 0.15, front - 0.6)), Vector3(0.15, 0.6, 0.15), Color(0.3, 0.3, 0.3))
	_add_label("aarong", roof_xf * _t(Vector3(0, 0, 0.08)), Vector2(16.0, 2.8), AARONG_RED, 220.0)
	var back := Transform3D(roof_xf.basis * Basis(Vector3.UP, PI), roof_xf.origin)
	_add_label("aarong", back * _t(Vector3(0, 0, 0.08)), Vector2(16.0, 2.8), AARONG_RED, 220.0)
	# Potted plants by the door.
	for x: float in [-2.0, 2.0]:
		kit.add_cylinder(xf * _t(Vector3(x, 0.3, front + 0.6)), 0.3, 0.6, TERRACOTTA, 8)
		kit.add_box(xf * _t(Vector3(x, 0.85, front + 0.6)), Vector3(0.6, 0.6, 0.6), LEAF)


func _build_garage(block: Dictionary, xf: Transform3D, w: float, title: String) -> void:
	var kit = block.kit
	var depth := 8.0
	var front := -SIDEWALK
	var back := front - depth
	_reserve(block, xf, Vector3(-w * 0.5, 0, front), Vector3(w * 0.5, 0, back))
	var wall := Color(0.55, 0.6, 0.65)
	var h := 3.2
	for spec in [[Vector3(0, h * 0.5, back + 0.1), Vector3(w, h, 0.2)],
			[Vector3(-w * 0.5 + 0.1, h * 0.5, front - depth * 0.5), Vector3(0.2, h, depth)],
			[Vector3(w * 0.5 - 0.1, h * 0.5, front - depth * 0.5), Vector3(0.2, h, depth)]]:
		kit.add_box(xf * _t(spec[0]), spec[1], wall)
		_add_box_collider(block.body, xf * _t(spec[0]), spec[1])
	kit.add_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, h + 0.25, front - depth * 0.5)), Vector3(w + 0.6, 0.06, depth + 0.6), TIN)
	kit.add_panel(xf * _t(Vector3(0, 1.4, back + 0.21)), Vector2(w - 0.6, 2.4), Color(0.25, 0.22, 0.2))
	# Stacked tyres, a hanging rickshaw wheel, a workbench with tools.
	var tyre := Color(0.07, 0.07, 0.08)
	for i in 5:
		kit.add_torus(xf * _t(Vector3(-w * 0.5 + 1.2, 0.08 + i * 0.13, front - 1.6)), 0.38, 0.065, tyre, 14, 4)
	kit.add_torus(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-1.5, 2.1, back + 0.35)), 0.33, 0.035, tyre, 16, 4)
	kit.add_torus(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.3, 2.2, back + 0.35)), 0.3, 0.012, Color(0.7, 0.72, 0.75), 16, 3)
	kit.add_box(xf * _t(Vector3(w * 0.5 - 1.6, 0.45, back + 0.8)), Vector3(2.2, 0.9, 0.8), WOOD)
	for i in 4:
		kit.add_box(xf * _t(Vector3(w * 0.5 - 2.4 + i * 0.4, 1.7, back + 0.25)), Vector3(0.06, 0.5, 0.03), Color(0.6, 0.62, 0.65))
	kit.add_cylinder(xf * _t(Vector3(w * 0.5 - 1.0, 1.05, back + 0.8)), 0.15, 0.3, Color(0.85, 0.15, 0.1), 8)
	_add_board(kit, xf * _t(Vector3(0, h + 0.85, front + 0.2)), Vector2(w * 0.75, 1.0), Color(0.85, 0.1, 0.12), title, Color(1, 0.95, 0.4), 120.0)
	# Painted repair bay on the road (local +Z is the road side).
	var road_y := -SLAB_HEIGHT + 0.014
	var bay := Vector3(0, road_y, CityLayout.DEST_OFFSET)
	var paint := Color(0.95, 0.85, 0.2)
	for line in [[Vector3(0, 0, -1.6), Vector2(4.6, 0.12)], [Vector3(0, 0, 1.6), Vector2(4.6, 0.12)],
			[Vector3(-2.3, 0, 0), Vector2(0.12, 3.2)], [Vector3(2.3, 0, 0), Vector2(0.12, 3.2)]]:
		kit.add_panel(xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), bay + line[0]), line[1], paint)
	var flat := xf * Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5), bay + Vector3(0, 0.002, 0))
	_add_label("মেরামত", flat, Vector2(3.0, 1.0), paint, 60.0)


## Small roadside tea stall (চায়ের দোকান) with a bench and plastic stools.
func _add_tea_stall(kit, xf: Transform3D) -> void:
	kit.add_box(xf * _t(Vector3(0, 0.5, -0.3)), Vector3(2.2, 1.0, 0.9), WOOD)
	kit.add_box(xf * _t(Vector3(0, 1.02, -0.3)), Vector3(2.3, 0.05, 1.0), Color(0.3, 0.6, 0.35))
	for x: float in [-1.05, 1.05]:
		kit.add_box(xf * _t(Vector3(x, 1.2, -0.7)), Vector3(0.08, 2.4, 0.08), WOOD)
		kit.add_box(xf * _t(Vector3(x, 1.0, 0.2)), Vector3(0.08, 2.0, 0.08), WOOD)
	kit.add_box(xf * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 2.25, -0.2)), Vector3(2.6, 0.04, 1.6), TIN)
	kit.add_cylinder(xf * _t(Vector3(-0.6, 1.2, -0.3)), 0.16, 0.3, Color(0.75, 0.75, 0.7), 8)
	kit.add_cylinder(xf * _t(Vector3(-0.6, 1.36, -0.3)), 0.06, 0.06, Color(0.2, 0.2, 0.2), 6)
	for i in 3:
		kit.add_cylinder(xf * _t(Vector3(0.2 + i * 0.28, 1.17, -0.4)), 0.1, 0.25, Color(0.85, 0.95, 1.0), 8)
		kit.add_cylinder(xf * _t(Vector3(0.2 + i * 0.28, 1.2, -0.4)), 0.08, 0.12, [Color(0.95, 0.7, 0.3), Color(0.9, 0.4, 0.2), Color(0.95, 0.85, 0.5)][i], 8)
	for i in 4:
		kit.add_cylinder(xf * _t(Vector3(-0.2 + i * 0.12, 1.08, 0.0)), 0.035, 0.07, Color(0.97, 0.97, 0.95), 6)
	kit.add_box(xf * _t(Vector3(0, 0.45, 0.9)), Vector3(1.8, 0.08, 0.4), WOOD)
	for x: float in [-0.8, 0.8]:
		kit.add_box(xf * _t(Vector3(x, 0.22, 0.9)), Vector3(0.08, 0.45, 0.35), WOOD)
	for x: float in [1.6, 2.1]:
		kit.add_cylinder(xf * _t(Vector3(x, 0.22, 0.5)), 0.17, 0.44, Color(0.85, 0.15, 0.15), 8)
	kit.add_box(xf * _t(Vector3(0, 2.62, 0.55)), Vector3(2.0, 0.5, 0.06), Color(0.85, 0.1, 0.12))


# --- Roads, intersections and signs ----------------------------------------------

func _build_road_markings(kit) -> void:
	var white := Color(0.92, 0.92, 0.88)
	var y := 0.012
	for r in CityLayout.road_rects():
		var vertical := r.size.y > r.size.x
		var width := r.size.x if vertical else r.size.y
		if width < 9.0:
			continue  # narrow lanes have no centre line
		var length := r.size.y if vertical else r.size.x
		var center := r.get_center()
		var start := r.position.y if vertical else r.position.x
		var t := start + 2.0
		while t < start + length - 2.0:
			var p := Vector3(center.x, y, t) if vertical else Vector3(t, y, center.y)
			# Skip dashes where another road crosses (and its zebra crossings).
			var crossing := false
			for d in [-5.0, 0.0, 5.0]:
				if vertical:
					crossing = crossing or CityLayout.is_road(r.end.x + 1.0, t + d) or CityLayout.is_road(r.position.x - 1.0, t + d)
				else:
					crossing = crossing or CityLayout.is_road(t + d, r.end.y + 1.0) or CityLayout.is_road(t + d, r.position.y - 1.0)
			if not crossing:
				var half := Vector3(0.08, 0, 1.0) if vertical else Vector3(1.0, 0, 0.08)
				kit.add_quad(p + Vector3(-half.x, 0, half.z), p + Vector3(half.x, 0, half.z),
					p + Vector3(half.x, 0, -half.z), p + Vector3(-half.x, 0, -half.z), white)
			t += 4.0


func _add_zebra(kit, center: Vector3, across: Vector3, width: float) -> void:
	var along := Vector3(across.z, 0, -across.x)
	var y := Vector3(0, 0.013, 0)
	for i in int(width):
		var o := center + across * (-width * 0.5 + 0.5 + i) + y
		var a := along * 1.5
		var b := across * 0.25
		kit.add_quad(o - a - b, o - a + b, o + a + b, o + a - b, Color(0.92, 0.92, 0.88))


func _build_intersections(kit) -> void:
	var post := Color(0.6, 0.6, 0.6)
	for it in CityLayout.intersections():
		var c: Vector2 = it[0]
		var v: Array = it[1]
		var h: Array = it[2]
		var vw: float = v[1]
		var hw: float = h[1]
		# Zebra crossings (রাস্তা পারাপার) across the wide roads.
		for s: float in [-1.0, 1.0]:
			var pz := c.y + s * (hw * 0.5 + 2.5)
			if vw >= 10.0 and CityLayout.is_road(c.x, pz):
				_add_zebra(kit, Vector3(c.x, 0, pz), Vector3.RIGHT, vw)
			var px := c.x + s * (vw * 0.5 + 2.5)
			if hw >= 10.0 and CityLayout.is_road(px, c.y):
				_add_zebra(kit, Vector3(px, 0, c.y), Vector3.BACK, hw)
		# Street name boards on two corners.
		var se := Vector3(c.x + vw * 0.5 + 1.3, SLAB_HEIGHT, c.y + hw * 0.5 + 1.3)
		var nw := Vector3(c.x - vw * 0.5 - 1.3, SLAB_HEIGHT, c.y - hw * 0.5 - 1.3)
		var green := Color(0.05, 0.42, 0.22)
		kit.add_beam(se, se + Vector3(0, 3.2, 0), 0.08, 0.08, post)
		_add_board(kit, Transform3D(Basis(), se + Vector3(0, 3.0, 0)), Vector2(2.4, 0.6), green, v[2])
		kit.add_beam(nw, nw + Vector3(0, 3.2, 0), 0.08, 0.08, post)
		_add_board(kit, Transform3D(Basis(Vector3.UP, PI * 0.5), nw + Vector3(0, 3.0, 0)), Vector2(2.4, 0.6), green, CityLayout.h_name(h, c.x))
		# A tangle of wires across the junction, from corner to corner.
		var ne := Vector3(c.x + vw * 0.5 + 0.6, 7.6, c.y - hw * 0.5 - 0.6)
		var sw := Vector3(c.x - vw * 0.5 - 0.6, 7.6, c.y + hw * 0.5 + 0.6)
		var se_top := Vector3(c.x + vw * 0.5 + 0.6, 7.6, c.y + hw * 0.5 + 0.6)
		var nw_top := Vector3(c.x - vw * 0.5 - 0.6, 7.6, c.y - hw * 0.5 - 0.6)
		for k in 3:
			var dy := Vector3(0, -k * 0.2, 0)
			_add_wire(kit, ne + dy, sw + dy, _rng.randf_range(0.8, 1.6), Color(0.06, 0.06, 0.06))
			_add_wire(kit, nw_top + dy, se_top + dy, _rng.randf_range(0.8, 1.6), Color(0.06, 0.06, 0.06))


func _build_caution_signs(kit) -> void:
	var red := Color(0.8, 0.1, 0.12)
	var blue := Color(0.1, 0.3, 0.75)
	# [position on the sidewalk, sign front direction, text, colour]
	var signs := [
		[Vector2(-9.3, 22.0), Vector3.BACK, "সামনে যানজট", red],
		[Vector2(9.3, -26.0), Vector3.FORWARD, "রাস্তা পারাপার", blue],
		[Vector2(308.3, -110.0), Vector3.LEFT, "ধীরে চলুন", red],  # outside BRAC University
		[Vector2(-9.3, 80.0), Vector3.BACK, "সাবধানে চলুন", red],
		[Vector2(-9.3, -75.0), Vector3.BACK, "হর্ন বাজাবেন না", blue],
		[Vector2(66.3, 75.0), Vector3.BACK, "আবাসিক এলাকা, ধীরে চলুন", blue],
		[Vector2(-228.3, -30.0), Vector3.RIGHT, "ছিনতাই থেকে সাবধান!", red],  # Mohammadpur
	]
	for s in signs:
		var pos: Vector3 = _v3(s[0], SLAB_HEIGHT)
		kit.add_beam(pos, pos + Vector3(0, 3.0, 0), 0.08, 0.08, Color(0.6, 0.6, 0.6))
		_add_board(kit, Transform3D(Basis.looking_at(-s[1]), pos + Vector3(0, 2.9, 0)), Vector2(2.2, 0.7), s[3], s[2])


func _build_boundary(kit) -> void:
	# A brick wall around the playable area, hidden behind the outer buildings.
	var body := _new_static_body("BoundaryWalls")
	var h := 3.0
	var m := CityLayout.MAP
	var cx := m.get_center().x
	var cz := m.get_center().y
	for wall in [
		[Vector3(cx, h * 0.5, m.position.y - 0.5), Vector3(m.size.x + 2, h, 1)],
		[Vector3(cx, h * 0.5, m.end.y + 0.5), Vector3(m.size.x + 2, h, 1)],
		[Vector3(m.position.x - 0.5, h * 0.5, cz), Vector3(1, h, m.size.y + 2)],
		[Vector3(m.end.x + 0.5, h * 0.5, cz), Vector3(1, h, m.size.y + 2)],
	]:
		kit.add_box(_t(wall[0]), wall[1], BRICK)
		_add_box_collider(body, _t(wall[0]), wall[1])

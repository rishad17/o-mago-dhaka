## Procedural low-poly models of Dhaka traffic: local bus, green CNG
## auto-rickshaw, car, microbus and motorcycle.
##
## Each model is built once per variant with MeshKit and cached. Local space:
## -Z is forward, origin on the ground at the centre of the vehicle.
## build() returns:
##   mesh   - the merged ArrayMesh
##   half   - half extents of the collision box (centred at y = half.y)
##   labels - Bangla texts to place as Label3D: [{text, xf, size, color}]
extends RefCounted

const MeshKit := preload("res://scripts/mesh_kit.gd")

const TIRE := Color(0.07, 0.07, 0.08)
const HUB := Color(0.6, 0.62, 0.65)
const GLASS := Color(0.16, 0.22, 0.3)
const DARK := Color(0.12, 0.12, 0.13)
const HEADLIGHT := Color(1.0, 0.95, 0.75)
const TAIL := Color(0.85, 0.08, 0.08)
const INDICATOR := Color(1.0, 0.55, 0.05)
const SKIN := Color(0.5, 0.31, 0.2)
const HAIR := Color(0.05, 0.04, 0.04)

const BUS_SCHEMES := [
	[Color(0.1, 0.5, 0.25), Color(0.98, 0.8, 0.15)],
	[Color(0.8, 0.12, 0.12), Color(0.95, 0.95, 0.9)],
	[Color(0.12, 0.35, 0.75), Color(0.95, 0.95, 0.9)],
	[Color(0.95, 0.55, 0.1), Color(0.15, 0.4, 0.2)],
]
const BUS_COMPANIES := ["সবুজ বাংলা পরিবহন", "লাল সবুজ পরিবহন", "নগর পরিবহন", "মৌমিতা পরিবহন"]
const BUS_ROUTES := ["মিরপুর - ফার্মগেট - গুলিস্তান", "মোহাম্মদপুর - সায়েদাবাদ",
	"আজিমপুর - উত্তরা", "গাবতলী - যাত্রাবাড়ী"]
const CAR_COLORS := [Color(0.92, 0.92, 0.9), Color(0.7, 0.72, 0.75), Color(0.1, 0.1, 0.12),
	Color(0.7, 0.1, 0.1), Color(0.15, 0.3, 0.6)]
const SHIRTS := [Color(0.9, 0.9, 0.85), Color(0.2, 0.4, 0.8), Color(0.8, 0.2, 0.2),
	Color(0.2, 0.6, 0.3), Color(0.95, 0.7, 0.2)]

static var _cache := {}


static func variant_count(type: String) -> int:
	match type:
		"bus":
			return BUS_SCHEMES.size()
		"car":
			return CAR_COLORS.size()
		"microbus":
			return 3
		"motorcycle":
			return 4
	return 1


static func build(type: String, variant: int) -> Dictionary:
	var key := "%s:%d" % [type, variant]
	if _cache.has(key):
		return _cache[key]
	var result: Dictionary
	match type:
		"bus":
			result = _bus(variant)
		"cng":
			result = _cng(variant)
		"car":
			result = _car(variant)
		"microbus":
			result = _microbus(variant)
		"motorcycle":
			result = _motorcycle(variant)
		"motorcycle_empty":  # the bike alone, after its riders fell off
			result = _motorcycle(variant, false)
		_:
			push_error("Unknown vehicle type " + type)
			result = _car(0)
	_cache[key] = result
	return result


static func _t(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


## Panel on a side face: side = +1 (right, +X) or -1 (left, -X).
static func _side_panel(kit, side: float, x: float, y: float, z: float, size: Vector2, color: Color) -> void:
	kit.add_panel(Transform3D(Basis(Vector3.UP, PI * 0.5 * side), Vector3(x * side, y, z)), size, color)


static func _front_panel(kit, y: float, z: float, x: float, size: Vector2, color: Color) -> void:
	kit.add_panel(Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, z)), size, color)


static func _wheel(kit, center: Vector3, radius: float, width: float) -> void:
	var axis := Basis(Vector3.BACK, PI * 0.5)
	kit.add_cylinder(Transform3D(axis, center), radius, width, TIRE, 12)
	kit.add_cylinder(Transform3D(axis, center), radius * 0.55, width + 0.02, HUB, 8)


static func _label(text: String, xf: Transform3D, size: Vector2, color: Color) -> Dictionary:
	return {"text": text, "xf": xf, "size": size, "color": color}


# --- Local bus ---------------------------------------------------------------------

static func _bus(variant: int) -> Dictionary:
	var kit := MeshKit.new()
	var scheme: Array = BUS_SCHEMES[variant % BUS_SCHEMES.size()]
	var paint: Color = scheme[0]
	var stripe: Color = scheme[1]
	var w := 2.5
	var l := 10.0
	var hw := w * 0.5
	var hl := l * 0.5
	kit.add_box_at(Vector3(0, 1.8, 0), Vector3(w, 2.4, l), paint)
	kit.add_box_at(Vector3(0, 0.75, 0), Vector3(w - 0.05, 0.5, l - 0.2), paint.darkened(0.35))
	kit.add_box_at(Vector3(0, 3.05, 0), Vector3(w - 0.1, 0.12, l - 0.3), paint.lightened(0.3))
	kit.add_box_at(Vector3(0, 3.15, 1.0), Vector3(1.6, 0.12, 3.0), Color(0.3, 0.3, 0.32))
	for side: float in [-1.0, 1.0]:
		# Stripe, window band with pillars, wheel arches.
		_side_panel(kit, side, hw + 0.01, 1.25, 0, Vector2(l - 0.4, 0.35), stripe)
		_side_panel(kit, side, hw + 0.01, 2.2, 0.3, Vector2(l - 1.4, 0.95), GLASS)
		for i in 8:
			_side_panel(kit, side, hw + 0.02, 2.2, -hl + 1.6 + i * 1.12, Vector2(0.14, 0.95), paint)
		for z in [-3.3, 3.3]:
			_side_panel(kit, side, hw + 0.015, 0.75, z, Vector2(1.3, 0.8), DARK)
			_wheel(kit, Vector3(side * (hw - 0.2), 0.5, z), 0.5, 0.38)
		# A few dents and repainted patches: Dhaka buses lead hard lives.
		for i in 3:
			var pz := -hl + 1.5 + fmod(i * 3.1 + variant * 1.7, l - 3.0)
			_side_panel(kit, side, hw + 0.012, 1.0 + fmod(i * 0.37 + variant * 0.2, 0.5), pz, Vector2(0.6, 0.35), paint.darkened(0.25))
		# Mirror arm at the front.
		kit.add_bar(Vector3(side * hw, 2.3, -hl + 0.2), Vector3(side * (hw + 0.35), 2.1, -hl - 0.1), 0.04, DARK)
		kit.add_box_at(Vector3(side * (hw + 0.38), 1.9, -hl - 0.12), Vector3(0.1, 0.35, 0.05), DARK)
	# Doors on the left (kerb) side, as traffic keeps left.
	for z in [-3.9, 0.6]:
		_side_panel(kit, -1.0, hw + 0.03, 1.55, z, Vector2(0.95, 2.1), Color(0.2, 0.2, 0.22))
	# The helper (হেলপার) hanging out of the front door.
	kit.add_beam(Vector3(-hw - 0.15, 0.95, -3.9), Vector3(-hw - 0.25, 1.6, -3.9), 0.28, 0.2, SHIRTS[(variant + 1) % SHIRTS.size()])
	kit.add_sphere(_t(Vector3(-hw - 0.27, 1.82, -3.9)), 0.13, SKIN, 3, 6)
	kit.add_bar(Vector3(-hw - 0.2, 1.5, -3.9), Vector3(-hw - 0.05, 2.1, -3.6), 0.07, SKIN)
	kit.add_beam(Vector3(-hw - 0.12, 0.95, -3.9), Vector3(-hw - 0.05, 0.4, -3.8), 0.22, 0.15, Color(0.2, 0.25, 0.4))
	# Front: windscreen, destination board, lights, bumper.
	_front_panel(kit, 2.15, -hl - 0.01, 0, Vector2(w - 0.3, 1.25), GLASS)
	_front_panel(kit, 2.95, -hl - 0.02, 0, Vector2(w - 0.3, 0.42), DARK)
	_front_panel(kit, 1.25, -hl - 0.01, 0, Vector2(w - 0.2, 0.3), stripe)
	for side: float in [-1.0, 1.0]:
		_front_panel(kit, 0.95, -hl - 0.02, side * 0.9, Vector2(0.35, 0.22), HEADLIGHT)
		_front_panel(kit, 0.95, -hl - 0.02, side * 0.55, Vector2(0.18, 0.15), INDICATOR)
		kit.add_panel(_t(Vector3(side * 0.95, 0.95, hl + 0.02)), Vector2(0.3, 0.3), TAIL)
	kit.add_box_at(Vector3(0, 0.55, -hl - 0.08), Vector3(w, 0.25, 0.18), DARK)
	kit.add_box_at(Vector3(0, 0.55, hl + 0.08), Vector3(w, 0.25, 0.18), DARK)
	# Rear window and name strip.
	kit.add_panel(_t(Vector3(0, 2.3, hl + 0.01)), Vector2(w - 0.5, 0.9), GLASS)
	kit.add_panel(_t(Vector3(0, 1.55, hl + 0.01)), Vector2(w - 0.3, 0.42), stripe)
	var text_col := Color(0.1, 0.1, 0.1) if stripe.get_luminance() > 0.6 else Color(1, 1, 1)
	var company: String = BUS_COMPANIES[variant % BUS_COMPANIES.size()]
	var labels := [
		_label(BUS_ROUTES[variant % BUS_ROUTES.size()], Transform3D(Basis(Vector3.UP, PI), Vector3(0, 2.95, -hl - 0.04)), Vector2(w - 0.45, 0.32), Color(1.0, 0.75, 0.15)),
		_label(company, _t(Vector3(0, 1.55, hl + 0.03)), Vector2(w - 0.5, 0.32), text_col),
	]
	for side: float in [-1.0, 1.0]:
		labels.append(_label(company, Transform3D(Basis(Vector3.UP, PI * 0.5 * side), Vector3(side * (hw + 0.03), 1.25, 0.8)), Vector2(5.0, 0.3), text_col))
	return {"mesh": kit.build(), "half": Vector3(hw + 0.05, 1.6, hl + 0.1), "labels": labels}


# --- Green CNG auto-rickshaw ---------------------------------------------------------
#
# Modelled on the Bajaj-style three-wheelers of Dhaka: a narrow rounded nose
# with one round headlight, a slanted windscreen, a curved metal roof that
# sweeps down into a closed rear, green bodywork with a thin yellow stripe,
# lockable metal grill cages on both sides, a spare wheel on the back, a
# handlebar-steered driver in front and a black bench seat behind.

## Roof profile (z, y) from the windscreen top to the rear bumper.
static func _cng_roof_profile() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-0.6, 1.66), Vector2(-0.2, 1.73), Vector2(0.45, 1.73)])
	for i in range(1, 9):
		var a := PI * 0.5 * i / 8.0
		pts.append(Vector2(0.45 + 0.68 * sin(a), 0.95 + 0.78 * cos(a)))
	pts.append(Vector2(1.13, 0.62))
	return pts


## Half width of the body at height y (it bulges slightly at the waist).
static func _cng_half_width(y: float) -> float:
	return 0.66 - 0.08 * clampf((y - 1.2) / 0.55, 0.0, 1.0)


static func _cng(variant: int) -> Dictionary:
	var kit := MeshKit.new()
	var green: Color = [Color(0.07, 0.52, 0.22), Color(0.1, 0.58, 0.26), Color(0.05, 0.46, 0.2)][variant % 3]
	var roof_col: Color = green.darkened(0.25)
	var inside := Color(0.06, 0.1, 0.07)
	var yellow := Color(0.98, 0.82, 0.15)
	var chrome := Color(0.78, 0.8, 0.82)
	var grill := Color(0.16, 0.2, 0.17)
	var seat := Color(0.08, 0.08, 0.09)

	# Lower tub (floor and sides up to the waist).
	kit.add_box_at(Vector3(0, 0.52, 0.2), Vector3(1.3, 0.42, 1.82), green)
	kit.add_box_at(Vector3(0, 0.3, 0.2), Vector3(1.22, 0.06, 1.8), Color(0.12, 0.12, 0.12))
	for side: float in [-1.0, 1.0]:
		_side_panel(kit, side, 0.651, 0.66, 0.2, Vector2(1.8, 0.05), yellow)
		_side_panel(kit, side, 0.651, 0.6, 0.2, Vector2(1.8, 0.02), Color(0.95, 0.95, 0.9))
	# Rounded rear corners of the tub.
	for side: float in [-1.0, 1.0]:
		kit.add_cylinder(_t(Vector3(side * 0.5, 0.52, 1.0)), 0.16, 0.42, green, 8)

	# Nose: tapers forward and down, with a black bumper below.
	var nose := {}
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var front: bool = sz < 0
				var w := (0.3 if front else 0.52) * (0.85 if sy > 0 else 1.0)
				var y := (1.08 if sy > 0 else 0.34) - (0.04 if front and sy > 0 else 0.0)
				var z := (-1.24 if sy < 0 else -1.14) if front else -0.7
				nose[Vector3i(sx, sy, sz)] = Vector3(sx * w, y, z)
	kit.add_hexa(nose, green)
	kit.add_box_at(Vector3(0, 0.36, -1.27), Vector3(0.66, 0.12, 0.12), Color(0.1, 0.1, 0.1))
	# Round headlight with a chrome ring, indicators, the "CNG" badge strip.
	var hl := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.88, -1.2))
	kit.add_cylinder(hl, 0.12, 0.06, chrome, 12)
	kit.add_cylinder(hl.translated(Vector3(0, 0, -0.02)), 0.095, 0.05, HEADLIGHT, 12)
	for side: float in [-1.0, 1.0]:
		kit.add_box_at(Vector3(side * 0.22, 0.7, -1.2), Vector3(0.09, 0.06, 0.04), INDICATOR)
	_front_panel(kit, 0.55, -1.235, 0, Vector2(0.42, 0.1), yellow)
	# Front wheel with fork and mudguard.
	_wheel(kit, Vector3(0, 0.22, -1.08), 0.22, 0.13)
	for side: float in [-1.0, 1.0]:
		kit.add_bar(Vector3(side * 0.09, 0.22, -1.08), Vector3(side * 0.09, 0.5, -1.0), 0.04, chrome)
	kit.add_box(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.47, -1.13)), Vector3(0.24, 0.04, 0.42), green.darkened(0.15))

	# Windscreen: slanted glass between two pillars, wiper, roof visor.
	kit.add_quad(Vector3(0.52, 1.08, -1.1), Vector3(-0.52, 1.08, -1.1), Vector3(-0.56, 1.66, -0.6), Vector3(0.56, 1.66, -0.6), GLASS)
	kit.add_quad(Vector3(-0.52, 1.08, -1.095), Vector3(0.52, 1.08, -1.095), Vector3(0.56, 1.66, -0.595), Vector3(-0.56, 1.66, -0.595), GLASS)
	for side: float in [-1.0, 1.0]:
		kit.add_bar(Vector3(side * 0.54, 1.06, -1.12), Vector3(side * 0.58, 1.68, -0.6), 0.05, green.darkened(0.3))
	kit.add_bar(Vector3(-0.15, 1.12, -1.07), Vector3(0.18, 1.3, -0.92), 0.015, Color(0.1, 0.1, 0.1))
	kit.add_box(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 1.69, -0.66)), Vector3(1.22, 0.04, 0.2), roof_col)
	# Side mirrors on stalks.
	for side: float in [-1.0, 1.0]:
		kit.add_bar(Vector3(side * 0.56, 1.25, -0.95), Vector3(side * 0.74, 1.35, -1.0), 0.02, Color(0.1, 0.1, 0.1))
		kit.add_box_at(Vector3(side * 0.76, 1.38, -1.0), Vector3(0.1, 0.13, 0.03), Color(0.1, 0.1, 0.1))

	# Curved roof shell (outside green, inside dark), extruded across the width.
	var prof := _cng_roof_profile()
	for i in prof.size() - 1:
		var a := prof[i]
		var b := prof[i + 1]
		var wa := _cng_half_width(a.y)
		var wb := _cng_half_width(b.y)
		var p0 := Vector3(-wa, a.y, a.x)
		var p1 := Vector3(wa, a.y, a.x)
		var p2 := Vector3(wb, b.y, b.x)
		var p3 := Vector3(-wb, b.y, b.x)
		var col: Color = roof_col if a.y > 1.6 else green
		# Outward = up/back: list the corners so the face points out of the cab.
		kit.add_quad(p0, p3, p2, p1, col)
		var dn := Vector3(0, -0.02, 0.0)
		kit.add_quad(p0 + dn, p1 + dn, p2 + dn, p3 + dn, inside)
	# Rounded rain-gutter trim along both roof edges.
	for i in prof.size() - 1:
		for side: float in [-1.0, 1.0]:
			var a := prof[i]
			var b := prof[i + 1]
			kit.add_rod(Vector3(side * _cng_half_width(a.y), a.y, a.x), Vector3(side * _cng_half_width(b.y), b.y, b.x), 0.03, green.darkened(0.3), 5)
	# Closed rear quarters: fill under the roof curve behind the passengers.
	for side: float in [-1.0, 1.0]:
		var hub := Vector3(side * 0.66, 0.74, 0.62)
		for i in range(3, prof.size() - 1):
			var a := prof[i]
			var b := prof[i + 1]
			var pa := Vector3(side * _cng_half_width(a.y), a.y, a.x)
			var pb := Vector3(side * _cng_half_width(b.y), b.y, b.x)
			# Green faces outwards on both sides (+X on the right, -X on the left).
			if side > 0.0:
				kit.add_tri(hub, pa, pb, green)
				kit.add_tri(hub, pb, pa, inside)
			else:
				kit.add_tri(hub, pb, pa, green)
				kit.add_tri(hub, pa, pb, inside)
		kit.add_bar(Vector3(side * 0.66, 0.74, 0.62), Vector3(side * 0.66, 1.73, 0.5), 0.05, green.darkened(0.3))
	# Small rear window in the sweep of the roof.
	kit.add_quad(Vector3(-0.32, 1.25, 1.09), Vector3(0.32, 1.25, 1.09), Vector3(0.3, 1.5, 0.945), Vector3(-0.3, 1.5, 0.945), GLASS)

	# Lockable metal grill cages over the passenger openings.
	for side: float in [-1.0, 1.0]:
		var x := side * 0.665
		var z0 := -0.32
		var z1 := 0.6
		for k in 9:
			var z := lerpf(z0, z1, k / 8.0)
			kit.add_bar(Vector3(x, 0.74, z), Vector3(x, 1.7, z), 0.022, grill)
		for y: float in [0.76, 1.08, 1.4, 1.69]:
			kit.add_bar(Vector3(x, y, z0), Vector3(x, y, z1), 0.026, grill)
		# Diagonal bracing and the padlock.
		kit.add_bar(Vector3(x, 0.78, z0), Vector3(x, 1.66, z1), 0.018, grill)
		kit.add_box_at(Vector3(x + side * 0.02, 1.0, 0.12), Vector3(0.03, 0.09, 0.06), Color(0.75, 0.6, 0.2))
		# Door post behind the driver.
		kit.add_bar(Vector3(x, 0.74, -0.34), Vector3(side * 0.58, 1.68, -0.4), 0.05, green.darkened(0.3))

	# Driver: seat, handlebar, the man himself.
	kit.add_box_at(Vector3(0, 0.92, -0.48), Vector3(0.44, 0.12, 0.34), seat)
	kit.add_rod(Vector3(0, 0.95, -0.95), Vector3(0, 1.18, -0.85), 0.03, chrome)
	kit.add_rod(Vector3(-0.3, 1.18, -0.83), Vector3(0.3, 1.18, -0.83), 0.022, Color(0.1, 0.1, 0.1))
	kit.add_beam(Vector3(0, 0.98, -0.48), Vector3(0, 1.43, -0.56), 0.34, 0.2, SHIRTS[(variant + 2) % SHIRTS.size()])
	kit.add_sphere(_t(Vector3(0, 1.57, -0.58)), 0.11, SKIN, 3, 6)
	kit.add_sphere(Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0, 1.62, -0.57)), 0.115, HAIR, 3, 6)
	for side: float in [-1.0, 1.0]:
		kit.add_bar(Vector3(side * 0.16, 1.38, -0.6), Vector3(side * 0.28, 1.18, -0.83), 0.06, SKIN)
		kit.add_bar(Vector3(side * 0.1, 0.95, -0.55), Vector3(side * 0.12, 0.6, -0.78), 0.08, Color(0.2, 0.25, 0.4))
	# Passenger bench with a backrest.
	kit.add_box_at(Vector3(0, 0.92, 0.48), Vector3(1.16, 0.14, 0.48), seat)
	kit.add_box(Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 1.22, 0.74)), Vector3(1.16, 0.5, 0.1), seat)

	# Rear: tail lights, number plate, bumper, spare wheel.
	for side: float in [-1.0, 1.0]:
		kit.add_box_at(Vector3(side * 0.48, 0.66, 1.12), Vector3(0.16, 0.1, 0.03), TAIL)
		kit.add_box_at(Vector3(side * 0.48, 0.58, 1.12), Vector3(0.16, 0.05, 0.03), INDICATOR)
	kit.add_box_at(Vector3(0, 0.6, 1.12), Vector3(0.56, 0.2, 0.02), Color(0.95, 0.95, 0.92))
	kit.add_box_at(Vector3(0, 0.36, 1.16), Vector3(1.24, 0.08, 0.08), chrome)
	var spare := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.0, 1.17))
	kit.add_cylinder(spare, 0.23, 0.13, TIRE, 12)
	kit.add_cylinder(spare.translated(Vector3(0, 0.02, 0)), 0.12, 0.14, chrome, 8)
	# Rear wheels and mudflaps.
	for side: float in [-1.0, 1.0]:
		_wheel(kit, Vector3(side * 0.6, 0.23, 0.72), 0.23, 0.16)
		kit.add_box_at(Vector3(side * 0.6, 0.2, 1.0), Vector3(0.18, 0.2, 0.02), Color(0.1, 0.1, 0.1))

	var labels := [
		_label("ঢাকা মেট্রো-থ ১১-৪২৭৫", _t(Vector3(0, 0.6, 1.135)), Vector2(0.52, 0.15), Color(0.05, 0.05, 0.05)),
		_label("সিএনজি", _t(Vector3(0, 0.84, 1.14)), Vector2(0.34, 0.12), Color(1, 0.95, 0.6)),
		_label("CNG", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.55, -1.25)), Vector2(0.36, 0.08), Color(0.1, 0.1, 0.1)),
	]
	return {"mesh": kit.build(), "half": Vector3(0.7, 0.9, 1.3), "labels": labels}


# --- Car and microbus ---------------------------------------------------------------

static func _car(variant: int) -> Dictionary:
	var kit := MeshKit.new()
	var paint: Color = CAR_COLORS[variant % CAR_COLORS.size()]
	kit.add_box_at(Vector3(0, 0.58, 0), Vector3(1.75, 0.55, 4.3), paint)
	kit.add_box_at(Vector3(0, 1.1, 0.2), Vector3(1.55, 0.5, 2.1), paint)
	for side: float in [-1.0, 1.0]:
		_side_panel(kit, side, 0.78, 1.12, 0.2, Vector2(1.9, 0.38), GLASS)
		_side_panel(kit, side, 0.88, 0.55, 0, Vector2(4.0, 0.06), paint.darkened(0.3))
		for z in [-1.35, 1.35]:
			_wheel(kit, Vector3(side * 0.75, 0.32, z), 0.32, 0.24)
		_front_panel(kit, 0.65, -2.16, side * 0.6, Vector2(0.35, 0.14), HEADLIGHT)
		kit.add_panel(_t(Vector3(side * 0.62, 0.68, 2.16)), Vector2(0.3, 0.14), TAIL)
	kit.add_panel(Transform3D(Basis(Vector3.RIGHT, 0.6) * Basis(Vector3.UP, PI), Vector3(0, 1.08, -0.88)), Vector2(1.45, 0.55), GLASS)
	kit.add_panel(Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0, 1.08, 1.28)), Vector2(1.45, 0.5), GLASS)
	_front_panel(kit, 0.5, -2.16, 0, Vector2(0.7, 0.18), DARK)
	kit.add_box_at(Vector3(0, 0.35, -2.18), Vector3(1.75, 0.15, 0.1), DARK)
	kit.add_box_at(Vector3(0, 0.35, 2.18), Vector3(1.75, 0.15, 0.1), DARK)
	kit.add_panel(_t(Vector3(0, 0.5, 2.24)), Vector2(0.55, 0.16), Color(0.95, 0.95, 0.92))
	var labels := [_label("ঢাকা মেট্রো-গ ২৭-৮১৯০", _t(Vector3(0, 0.5, 2.25)), Vector2(0.5, 0.12), Color(0.05, 0.05, 0.05))]
	return {"mesh": kit.build(), "half": Vector3(0.9, 0.75, 2.2), "labels": labels}


static func _microbus(variant: int) -> Dictionary:
	var kit := MeshKit.new()
	var paint: Color = [Color(0.95, 0.95, 0.93), Color(0.75, 0.77, 0.8), Color(0.85, 0.8, 0.6)][variant % 3]
	kit.add_box_at(Vector3(0, 1.15, 0.1), Vector3(1.9, 1.7, 4.6), paint)
	kit.add_box_at(Vector3(0, 0.8, -2.25), Vector3(1.85, 0.9, 0.3), paint)
	for side: float in [-1.0, 1.0]:
		_side_panel(kit, side, 0.96, 1.5, 0.3, Vector2(3.8, 0.6), GLASS)
		_side_panel(kit, side, 0.96, 0.9, 0.1, Vector2(4.4, 0.08), Color(0.2, 0.4, 0.7))
		for z in [-1.5, 1.5]:
			_wheel(kit, Vector3(side * 0.82, 0.33, z), 0.33, 0.25)
		_front_panel(kit, 0.85, -2.41, side * 0.65, Vector2(0.38, 0.18), HEADLIGHT)
		kit.add_panel(_t(Vector3(side * 0.75, 0.9, 2.41)), Vector2(0.2, 0.35), TAIL)
	kit.add_panel(Transform3D(Basis(Vector3.RIGHT, 0.35) * Basis(Vector3.UP, PI), Vector3(0, 1.55, -2.18)), Vector2(1.7, 0.75), GLASS)
	kit.add_panel(_t(Vector3(0, 1.5, 2.41)), Vector2(1.6, 0.6), GLASS)
	kit.add_box_at(Vector3(0, 0.45, -2.42), Vector3(1.9, 0.18, 0.1), DARK)
	kit.add_box_at(Vector3(0, 0.45, 2.42), Vector3(1.9, 0.18, 0.1), DARK)
	kit.add_box_at(Vector3(0, 2.05, 0.4), Vector3(1.4, 0.08, 2.6), DARK)  # roof rack
	return {"mesh": kit.build(), "half": Vector3(0.97, 1.05, 2.45), "labels": []}


# --- Motorcycle ---------------------------------------------------------------------

static func _rider(kit, hip: Vector3, hands_z: float, shirt: Color, helmet: Color, lean: float) -> void:
	var shoulder := hip + Vector3(0, 0.52, -lean)
	kit.add_beam(hip, shoulder, 0.34, 0.2, shirt)
	kit.add_sphere(_t(shoulder + Vector3(0, 0.2, -0.04)), 0.14, helmet, 4, 8)
	for side: float in [-1.0, 1.0]:
		kit.add_bar(shoulder + Vector3(side * 0.17, -0.05, 0), Vector3(side * 0.3, hip.y + 0.12, hands_z), 0.07, shirt)
		var knee := Vector3(side * 0.2, hip.y - 0.05, hip.z - 0.38)
		kit.add_bar(hip + Vector3(side * 0.1, 0, 0), knee, 0.11, Color(0.15, 0.17, 0.25))
		kit.add_bar(knee, Vector3(side * 0.2, 0.32, hip.z - 0.2), 0.09, Color(0.15, 0.17, 0.25))


static func _motorcycle(variant: int, with_riders := true) -> Dictionary:
	var kit := MeshKit.new()
	var paint: Color = [Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.12), Color(0.15, 0.35, 0.75), Color(0.9, 0.9, 0.9)][variant % 4]
	var axis := Basis(Vector3.BACK, PI * 0.5)
	for z in [-0.68, 0.62]:
		kit.add_torus(Transform3D(axis, Vector3(0, 0.3, z)), 0.26, 0.05, TIRE, 12, 4)
		kit.add_cylinder(Transform3D(axis, Vector3(0, 0.3, z)), 0.08, 0.1, HUB, 6)
	kit.add_box_at(Vector3(0, 0.82, -0.15), Vector3(0.32, 0.24, 0.5), paint)
	kit.add_box_at(Vector3(0, 0.86, 0.32), Vector3(0.28, 0.1, 0.62), DARK)
	kit.add_box_at(Vector3(0, 0.5, 0.0), Vector3(0.3, 0.3, 0.42), Color(0.35, 0.35, 0.38))
	kit.add_box_at(Vector3(0, 0.62, 0.62), Vector3(0.22, 0.08, 0.4), paint)
	kit.add_rod(Vector3(0.14, 0.42, 0.1), Vector3(0.16, 0.5, 0.75), 0.04, HUB)
	for side: float in [-1.0, 1.0]:
		kit.add_rod(Vector3(side * 0.07, 0.3, -0.68), Vector3(side * 0.07, 1.0, -0.5), 0.025, HUB)
	kit.add_rod(Vector3(-0.32, 1.02, -0.48), Vector3(0.32, 1.02, -0.48), 0.02, DARK)
	kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.92, -0.62)), 0.08, 0.08, HEADLIGHT, 8)
	kit.add_panel(_t(Vector3(0, 0.75, 0.84)), Vector2(0.12, 0.08), TAIL)
	var helmet: Color = [Color(0.9, 0.9, 0.9), Color(0.85, 0.1, 0.1), Color(0.1, 0.1, 0.1), Color(0.95, 0.75, 0.1)][variant % 4]
	if with_riders:
		_rider(kit, Vector3(0, 0.95, 0.2), -0.46, SHIRTS[variant % SHIRTS.size()], helmet, 0.12)
	if with_riders and variant % 2 == 1:
		# Passenger on the back.
		_rider(kit, Vector3(0, 0.98, 0.52), -0.05, SHIRTS[(variant + 2) % SHIRTS.size()], Color(0.2, 0.2, 0.25), 0.02)
	return {"mesh": kit.build(), "half": Vector3(0.38, 0.8, 1.0), "labels": []}

## Small helper for building low-poly, flat-shaded meshes out of boxes,
## cylinders, spheres and quads.
##
## Everything added to one MeshKit is merged into a single ArrayMesh: all
## plain-coloured parts share one vertex-coloured material, and each texture
## gets one extra surface. A whole rickshaw therefore costs only a handful of
## draw calls, which matters on integrated graphics.
##
## Winding convention for the helpers below: pass the points of a face in
## counter-clockwise order as seen from OUTSIDE. The kit flips them to the
## clockwise order Godot expects and computes the outward normal itself.
extends RefCounted

const FLAT_KEY := "__flat__"

static var _flat_material: StandardMaterial3D
static var _texture_materials := {}

# key -> { "verts", "normals", "colors", "uvs", "material" }
var _surfaces := {}


static func flat_material() -> StandardMaterial3D:
	if _flat_material == null:
		_flat_material = StandardMaterial3D.new()
		_flat_material.vertex_color_use_as_albedo = true
		_flat_material.roughness = 0.9
		_flat_material.metallic_specular = 0.2
		_use_phone_shading(_flat_material)
	return _flat_material


## Phones light the world per vertex instead of per pixel: far less work for
## their small GPUs, and with flat colours it looks nearly the same.
static func _use_phone_shading(mat: StandardMaterial3D) -> void:
	if Settings.touch_mode:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX


static func textured_material(texture: Texture2D) -> StandardMaterial3D:
	var key := texture.resource_path if texture.resource_path != "" else str(texture.get_instance_id())
	if not _texture_materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.85
		mat.metallic_specular = 0.2
		_use_phone_shading(mat)
		_texture_materials[key] = mat
	return _texture_materials[key]


## Returns a basis whose Y axis points along `dir`, keeping X close to `x_hint`.
static func basis_along(dir: Vector3, x_hint := Vector3.RIGHT) -> Basis:
	var y := dir.normalized()
	var z := x_hint.cross(y)
	if z.length_squared() < 0.0001:
		z = Vector3.FORWARD.cross(y)
	z = z.normalized()
	var x := y.cross(z)
	return Basis(x, y, z)


func is_empty() -> bool:
	return _surfaces.is_empty()


func _surface(key: String, material: Material) -> Dictionary:
	if not _surfaces.has(key):
		_surfaces[key] = {
			"verts": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"colors": PackedColorArray(),
			"uvs": PackedVector2Array(),
			"material": material,
		}
	return _surfaces[key]


## The plain vertex-coloured surface, looked up once (it gets most geometry).
var _flat_surf := {}

## For each face of a box: outward normal n and two tangents u, v with u x v = n.
const _BOX_FACES := [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]


func _flat() -> Dictionary:
	if _flat_surf.is_empty():
		_flat_surf = _surface(FLAT_KEY, flat_material())
	return _flat_surf


## Appends ready-made triangles (all one colour, no texture) in one go.
func _push(surf: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array, color: Color) -> void:
	var n := verts.size()
	if n == 0:
		return
	surf.verts.append_array(verts)
	surf.normals.append_array(normals)
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(color)
	surf.colors.append_array(cols)
	var uvs := PackedVector2Array()
	uvs.resize(n)  # all zero
	surf.uvs.append_array(uvs)


## A quad as two triangles, exactly as add_quad() makes them, into the arrays
## at index k. Returns the new k (unchanged if the quad is degenerate).
static func _quad_into(verts: PackedVector3Array, normals: PackedVector3Array, k: int,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> int:
	var n1 := (p1 - p0).cross(p2 - p0)
	var n2 := (p2 - p0).cross(p3 - p0)
	if n1.length_squared() >= 1e-12:
		n1 = n1.normalized()
		verts[k] = p0
		verts[k + 1] = p2
		verts[k + 2] = p1
		normals[k] = n1
		normals[k + 1] = n1
		normals[k + 2] = n1
		k += 3
	if n2.length_squared() >= 1e-12:
		n2 = n2.normalized()
		verts[k] = p0
		verts[k + 1] = p3
		verts[k + 2] = p2
		normals[k] = n2
		normals[k + 1] = n2
		normals[k + 2] = n2
		k += 3
	return k


func _emit(surf: Dictionary, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return  # degenerate triangle (e.g. at a sphere pole)
	n = n.normalized()
	# Godot treats clockwise triangles as front faces, so emit a, c, b.
	surf.verts.append_array([a, c, b])
	surf.normals.append_array([n, n, n])
	surf.colors.append_array([color, color, color])
	surf.uvs.append_array([ua, uc, ub])


func add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_emit(_flat(), a, b, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color)


func add_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color) -> void:
	var verts := PackedVector3Array()
	verts.resize(6)
	var normals := PackedVector3Array()
	normals.resize(6)
	var k := _quad_into(verts, normals, 0, p0, p1, p2, p3)
	verts.resize(k)
	normals.resize(k)
	_push(_flat(), verts, normals, color)


## Textured quad. UVs follow the same order as the points.
func add_quad_uv(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2,
		texture: Texture2D, tint := Color.WHITE) -> void:
	if texture == null:
		add_quad(p0, p1, p2, p3, tint)
		return
	var key := texture.resource_path if texture.resource_path != "" else str(texture.get_instance_id())
	var s := _surface(key, textured_material(texture))
	_emit(s, p0, p1, p2, uv0, uv1, uv2, tint)
	_emit(s, p0, p2, p3, uv0, uv2, uv3, tint)


## Axis-aligned box (in the space of `xf`) centred on xf.origin.
func add_box(xf: Transform3D, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	# All six faces in one go (boxes are most of the city: this is the hot path).
	var verts := PackedVector3Array()
	verts.resize(36)
	var normals := PackedVector3Array()
	normals.resize(36)
	var k := 0
	for f: Array in _BOX_FACES:
		var n: Vector3 = f[0] * h
		var u: Vector3 = f[1] * h
		var v: Vector3 = f[2] * h
		k = _quad_into(verts, normals, k, xf * (n - u - v), xf * (n + u - v), xf * (n + u + v), xf * (n - u + v))
	verts.resize(k)
	normals.resize(k)
	_push(_flat(), verts, normals, color)


## Only the front (+Z) face of a box: cheap flat detail stuck on a wall,
## such as window glass, grills or painted stripes.
func add_panel(xf: Transform3D, size: Vector2, color: Color) -> void:
	var h := size * 0.5
	add_quad(xf * Vector3(-h.x, -h.y, 0), xf * Vector3(h.x, -h.y, 0),
		xf * Vector3(h.x, h.y, 0), xf * Vector3(-h.x, h.y, 0), color)


## Box with freely placed corners (tapered noses, slanted panels).
## `corners` maps each corner's sign Vector3i(±1, ±1, ±1) to its position.
func add_hexa(corners: Dictionary, color: Color) -> void:
	var faces := [
		[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0)],
		[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0)],
		[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
		[Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3i = f[0]
		var u: Vector3i = f[1]
		var v: Vector3i = f[2]
		add_quad(corners[n - u - v], corners[n + u - v], corners[n + u + v], corners[n - u + v], color)


func add_box_at(center: Vector3, size: Vector3, color: Color) -> void:
	add_box(Transform3D(Basis(), center), size, color)


## Rectangular beam from a to b. `x_hint` chooses which way the width faces.
func add_beam(a: Vector3, b: Vector3, width: float, depth: float, color: Color,
		x_hint := Vector3.RIGHT) -> void:
	var dir := b - a
	if dir.length_squared() < 1e-8:
		return
	var basis := basis_along(dir, x_hint)
	add_box(Transform3D(basis, (a + b) * 0.5), Vector3(width, dir.length(), depth), color)


## Thin square bar from a to b (frames, spokes, wires).
func add_bar(a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	add_beam(a, b, thickness, thickness, color)


## Cylinder along the local Y axis of `xf`, centred on xf.origin.
func add_cylinder(xf: Transform3D, radius: float, height: float, color: Color,
		segments := 10, caps := true) -> void:
	var hh := height * 0.5
	var top := []
	var bottom := []
	for i in segments + 1:
		var a := TAU * i / segments
		var p := Vector3(cos(a) * radius, 0, sin(a) * radius)
		top.append(xf * (p + Vector3(0, hh, 0)))
		bottom.append(xf * (p - Vector3(0, hh, 0)))
	var top_c := xf * Vector3(0, hh, 0)
	var bot_c := xf * Vector3(0, -hh, 0)
	for i in segments:
		add_quad(bottom[i], top[i], top[i + 1], bottom[i + 1], color)
		if caps:
			add_tri(top_c, top[i + 1], top[i], color)
			add_tri(bot_c, bottom[i], bottom[i + 1], color)


## Round rod from a to b.
func add_rod(a: Vector3, b: Vector3, radius: float, color: Color, segments := 6) -> void:
	var dir := b - a
	if dir.length_squared() < 1e-8:
		return
	var xf := Transform3D(basis_along(dir), (a + b) * 0.5)
	add_cylinder(xf, radius, dir.length(), color, segments)


## Low-poly sphere. Scale `xf` to make ellipsoids.
func add_sphere(xf: Transform3D, radius: float, color: Color, rings := 5, segments := 8) -> void:
	for j in rings:
		var p0 := PI * j / rings
		var p1 := PI * (j + 1) / rings
		for i in segments:
			var t0 := TAU * i / segments
			var t1 := TAU * (i + 1) / segments
			var a := xf * (Vector3(sin(p0) * cos(t0), cos(p0), sin(p0) * sin(t0)) * radius)
			var b := xf * (Vector3(sin(p0) * cos(t1), cos(p0), sin(p0) * sin(t1)) * radius)
			var c := xf * (Vector3(sin(p1) * cos(t1), cos(p1), sin(p1) * sin(t1)) * radius)
			var d := xf * (Vector3(sin(p1) * cos(t0), cos(p1), sin(p1) * sin(t0)) * radius)
			add_quad(a, b, c, d, color)


## Torus around the local Y axis of `xf` (used for tyres).
func add_torus(xf: Transform3D, major: float, minor: float, color: Color,
		seg_u := 16, seg_v := 5) -> void:
	for i in seg_u:
		var u0 := TAU * i / seg_u
		var u1 := TAU * (i + 1) / seg_u
		for j in seg_v:
			var v0 := TAU * j / seg_v
			var v1 := TAU * (j + 1) / seg_v
			var p00 := xf * _torus_point(u0, v0, major, minor)
			var p01 := xf * _torus_point(u0, v1, major, minor)
			var p11 := xf * _torus_point(u1, v1, major, minor)
			var p10 := xf * _torus_point(u1, v0, major, minor)
			add_quad(p00, p01, p11, p10, color)


func _torus_point(u: float, v: float, major: float, minor: float) -> Vector3:
	var r := major + minor * cos(v)
	return Vector3(r * cos(u), minor * sin(v), r * sin(u))


## Appends an existing MeshKit-built mesh, moved by `xf` (used to merge the
## separate moving parts of a model into one low-detail mesh).
func add_mesh(mesh: ArrayMesh, xf: Transform3D) -> void:
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var material := mesh.surface_get_material(i)
		var key := FLAT_KEY
		if material is StandardMaterial3D and material != flat_material():
			var tex: Texture2D = (material as StandardMaterial3D).albedo_texture
			key = tex.resource_path if tex and tex.resource_path != "" else str(material.get_instance_id())
		var s := _surface(key, material)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for v in verts:
			s.verts.append(xf * v)
		for n in normals:
			s.normals.append((xf.basis * n).normalized())
		s.colors.append_array(arrays[Mesh.ARRAY_COLOR])
		s.uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])


## Builds the merged mesh. Returns null if nothing was added.
func build() -> ArrayMesh:
	if _surfaces.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for key in _surfaces:
		var s: Dictionary = _surfaces[key]
		if s.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s.material)
	return mesh


## Convenience: builds the mesh into a new MeshInstance3D (or null if empty).
func build_instance(node_name := "Mesh") -> MeshInstance3D:
	var mesh := build()
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	return mi
